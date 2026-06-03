"""Hand-tracking → SO-101 IK → motor commands over WebSocket.

Two modes:
    stereo  — two cameras + stereo_calib.npz, true 3D triangulation
    mono    — one camera, depth from hand-size proxy

Either mode produces (wrist_3d, hand_frame, gripper_ratio) per frame in
arbitrary units. user_calib.npz (from calibrate_robot_frame.py) maps those
to robot coordinates, gripper [0,100], and wrist_roll joint range.

Workflow:
    Stereo:
        1)  python calibrate_hand.py --left 0 --right 1
        2)  python calibrate_robot_frame.py --mode stereo --left 0 --right 1
        3)  python stereo_sender.py --mode stereo --left 0 --right 1
    Mono:
        1)  python calibrate_robot_frame.py --mode mono --camera 0
        2)  python stereo_sender.py --mode mono --camera 0
"""

import argparse
import asyncio
import json
import math
import os
import threading
import time
from dataclasses import dataclass, field
from typing import Optional

import cv2
import numpy as np
import websockets
from ikpy.chain import Chain
from ikpy.link import OriginLink, URDFLink

from hand_pose import (
    StereoTriangulator,
    make_landmarker,
    mono_pose,
    stereo_pose,
    wrist_roll,
)


# --- SO-101 chain -----------------------------------------------------------

JOINT_DEFS = [
    ("shoulder_pan",  [ 0.0388,  0.0000,  0.0624], [ math.pi,      0.0,         -math.pi    ], -1.92, 1.92),
    ("shoulder_lift", [-0.0304, -0.0183, -0.0542], [-math.pi / 2, -math.pi / 2,  0.0        ], -1.75, 1.75),
    ("elbow_flex",    [-0.1126, -0.0280,  0.0000], [ 0.0,          0.0,          math.pi / 2], -1.69, 1.69),
    ("wrist_flex",    [-0.1349,  0.0052,  0.0000], [ 0.0,          0.0,         -math.pi / 2], -1.66, 1.66),
    ("wrist_roll",    [ 0.0000, -0.0611,  0.0181], [ math.pi / 2,  0.0487,       math.pi    ], -2.74, 2.84),
]
EE_OFFSET = [0.0202, 0.0188, -0.0234]
EE_RPY = [math.pi / 2, 0.0, 0.0]
JOINT_SAFETY = 0.85

ROBOT_HOME_POS = np.array([0.18, 0.0, 0.15])


def build_chain() -> Chain:
    links = [OriginLink()]
    for name, xyz, rpy, lo, hi in JOINT_DEFS:
        mid = 0.5 * (lo + hi)
        half = 0.5 * (hi - lo) * JOINT_SAFETY
        links.append(URDFLink(
            name=name,
            origin_translation=xyz,
            origin_orientation=rpy,
            rotation=[0, 0, 1],
            bounds=(mid - half, mid + half),
        ))
    links.append(URDFLink(
        name="end_effector",
        origin_translation=EE_OFFSET,
        origin_orientation=EE_RPY,
        rotation=[0, 0, 1],
        bounds=(0, 0),
    ))
    mask = [False] + [True] * len(JOINT_DEFS) + [False]
    return Chain(name="so101", links=links, active_links_mask=mask)


def joint_norm(angle: float, lo: float, hi: float) -> float:
    t = (angle - lo) / (hi - lo)
    return float(max(-100.0, min(100.0, t * 200.0 - 100.0)))


# --- Drawing ----------------------------------------------------------------

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (5, 9), (9, 10), (10, 11), (11, 12),
    (9, 13), (13, 14), (14, 15), (15, 16),
    (13, 17), (17, 18), (18, 19), (19, 20),
    (0, 17),
]


def draw_landmarks(frame, lm_img) -> None:
    h, w = frame.shape[:2]
    pts = [(int(p.x * w), int(p.y * h)) for p in lm_img]
    for a, b in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], (200, 200, 200), 2)
    for p in pts:
        cv2.circle(frame, p, 4, (0, 200, 255), -1)


# --- User calibration -------------------------------------------------------

@dataclass
class UserCalib:
    robot_from_cam: np.ndarray
    home_wrist: np.ndarray
    home_frame: np.ndarray
    grip_closed: float
    grip_open: float
    roll_min: float
    roll_max: float

    @classmethod
    def load(cls, path: str) -> "UserCalib":
        d = np.load(path)
        return cls(
            robot_from_cam=d["robot_from_cam"],
            home_wrist=d["home_wrist"],
            home_frame=d["home_frame"],
            grip_closed=float(d["grip_closed"]),
            grip_open=float(d["grip_open"]),
            roll_min=float(d["roll_min"]),
            roll_max=float(d["roll_max"]))


# --- Shared state -----------------------------------------------------------

@dataclass
class State:
    latest_wrist:      Optional[np.ndarray] = None
    latest_hand_frame: Optional[np.ndarray] = None
    latest_gripper:    float = 0.0
    latest_msg:        Optional[dict] = None
    running:           bool = True
    lock:              threading.Lock = field(default_factory=threading.Lock)


# --- Capture loop -----------------------------------------------------------

def step_capture_stereo(capL, capR, lmL, lmR, tri, state, show, t0):
    okL, frameL = capL.read()
    okR, frameR = capR.read()
    if not (okL and okR):
        return
    ts = int((time.time() - t0) * 1000)
    pose = stereo_pose(frameL, frameR, lmL, lmR, tri, ts)
    if pose is not None:
        wrist, frame_r, grip = pose
        with state.lock:
            state.latest_wrist = wrist
            state.latest_hand_frame = frame_r
            state.latest_gripper = grip

    if show:
        h = min(frameL.shape[0], frameR.shape[0])
        L = cv2.resize(frameL, (int(frameL.shape[1] * h / frameL.shape[0]), h))
        R_ = cv2.resize(frameR, (int(frameR.shape[1] * h / frameR.shape[0]), h))
        cv2.imshow("Stereo hand → SO-101", np.hstack([L, R_]))
        if (cv2.waitKey(1) & 0xFF) == 27:
            state.running = False


def step_capture_mono(cap, lm, state, show, t0):
    ok, frame = cap.read()
    if not ok:
        return
    ts = int((time.time() - t0) * 1000)
    pose = mono_pose(frame, lm, ts)
    if pose is not None:
        wrist, frame_r, grip = pose
        with state.lock:
            state.latest_wrist = wrist
            state.latest_hand_frame = frame_r
            state.latest_gripper = grip

    if show:
        cv2.imshow("Mono hand → SO-101", frame)
        if (cv2.waitKey(1) & 0xFF) == 27:
            state.running = False


# --- IK worker --------------------------------------------------------------

def ik_worker(chain: Chain, calib: UserCalib, state: State, hz: float) -> None:
    period = 1.0 / hz
    prev_angles = [0.0] * (len(JOINT_DEFS) + 2)
    smoothed_target: Optional[np.ndarray] = None
    wrist_roll_idx = next(i for i, jd in enumerate(JOINT_DEFS)
                          if jd[0] == "wrist_roll")
    _, _, _, wr_lo, wr_hi = JOINT_DEFS[wrist_roll_idx]

    while state.running:
        t0 = time.perf_counter()
        with state.lock:
            wrist     = state.latest_wrist
            cur_frame = state.latest_hand_frame
            grip      = state.latest_gripper

        if wrist is not None:
            # Position: delta from home, mapped through calibrated matrix.
            delta = calib.robot_from_cam @ (wrist - calib.home_wrist)
            target = ROBOT_HOME_POS + delta
            smoothed_target = target if smoothed_target is None \
                else 0.7 * smoothed_target + 0.3 * target

            angles = chain.inverse_kinematics(
                target_position=smoothed_target.tolist(),
                initial_position=prev_angles)
            prev_angles = list(angles)

            msg: dict = {}
            for i, (name, _, _, lo, hi) in enumerate(JOINT_DEFS):
                msg[f"{name}.pos"] = joint_norm(angles[i + 1], lo, hi)

            # Wrist roll override from calibrated user range.
            if cur_frame is not None:
                roll = wrist_roll(cur_frame, calib.home_frame)
                # Map calibrated user roll range → joint URDF range.
                rmin, rmax = calib.roll_min, calib.roll_max
                if rmax - rmin > 1e-3:
                    t = (roll - rmin) / (rmax - rmin)             # 0..1
                    joint_angle = wr_lo + t * (wr_hi - wr_lo)
                    msg["wrist_roll.pos"] = joint_norm(joint_angle, wr_lo, wr_hi)

            # Gripper from calibrated open/closed range.
            gr = (grip - calib.grip_closed) / max(
                calib.grip_open - calib.grip_closed, 1e-6)
            msg["gripper.pos"] = float(np.clip(gr, 0.0, 1.0) * 100.0)

            with state.lock:
                state.latest_msg = msg

        time.sleep(max(0.0, period - (time.perf_counter() - t0)))


# --- WebSocket server -------------------------------------------------------

async def ws_handler(ws, state: State, send_hz: float) -> None:
    print(f"client connected: {ws.remote_address}")
    period = 1.0 / send_hz
    last_id: Optional[int] = None
    try:
        while state.running:
            with state.lock:
                msg = state.latest_msg
            if msg is not None and id(msg) != last_id:
                await ws.send(json.dumps(msg))
                last_id = id(msg)
            await asyncio.sleep(period)
    except websockets.ConnectionClosed:
        pass
    finally:
        print(f"client disconnected: {ws.remote_address}")


async def capture_task(args, state, capture_args) -> None:
    t0 = time.time()
    show = not args.no_preview
    while state.running:
        if args.mode == "stereo":
            capL, capR, lmL, lmR, tri = capture_args
            step_capture_stereo(capL, capR, lmL, lmR, tri, state, show, t0)
        else:
            cap, lm = capture_args
            step_capture_mono(cap, lm, state, show, t0)
        await asyncio.sleep(0.001)


# --- Main -------------------------------------------------------------------

def open_camera(index: int):
    cap = cv2.VideoCapture(index, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        raise SystemExit(f"Could not open camera {index}")
    return cap


async def main_async(args) -> None:
    if not os.path.exists(args.user_calib):
        raise SystemExit(
            f"{args.user_calib} not found.\nRun calibrate_robot_frame.py first.")
    calib = UserCalib.load(args.user_calib)
    print(f"Loaded {args.user_calib}")

    chain = build_chain()
    state = State()

    cams: list = []   # for release on exit
    if args.mode == "stereo":
        if not os.path.exists(args.calib):
            raise SystemExit(
                f"{args.calib} not found. Run calibrate_hand.py first.")
        tri = StereoTriangulator(args.calib)
        capL = open_camera(args.left)
        capR = open_camera(args.right)
        lmL = make_landmarker()
        lmR = make_landmarker()
        cams = [capL, capR]
        capture_args = (capL, capR, lmL, lmR, tri)
    else:
        cap = open_camera(args.camera)
        lm = make_landmarker()
        cams = [cap]
        capture_args = (cap, lm)

    ik_thread = threading.Thread(
        target=ik_worker, args=(chain, calib, state, args.ik_hz), daemon=True)
    ik_thread.start()

    async def handler(ws):
        await ws_handler(ws, state, args.send_hz)

    async with websockets.serve(handler, args.host, args.port):
        print(f"WS server on ws://{args.host}:{args.port}")
        print(f"mode: {args.mode}  ·  ESC in preview to quit")
        try:
            await capture_task(args, state, capture_args)
        finally:
            state.running = False

    ik_thread.join(timeout=1.0)
    for c in cams:
        c.release()
    cv2.destroyAllWindows()


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["stereo", "mono"], default="stereo")
    p.add_argument("--calib", default="stereo_calib.npz",
                   help="stereo geometry (stereo mode only)")
    p.add_argument("--user-calib", default="user_calib.npz",
                   help="user-driven robot-frame calibration")
    p.add_argument("--left", type=int, default=0)
    p.add_argument("--right", type=int, default=1)
    p.add_argument("--camera", type=int, default=0,
                   help="camera index (mono mode)")
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--send-hz", type=float, default=30.0)
    p.add_argument("--ik-hz", type=float, default=20.0)
    p.add_argument("--no-preview", action="store_true")
    args = p.parse_args()
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
