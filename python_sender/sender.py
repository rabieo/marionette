"""Webcam hand landmarks -> SO-101 IK -> motor commands over WebSocket.

The Swift TBDR app is the WebSocket *client* (RobotWebSocketClient.swift)
connecting to ws://localhost:8765 and expects messages of the form:
    {"shoulder_pan.pos": float, "shoulder_lift.pos": float, ...}

Normalization matches the LeRobot/feetech teleop convention used by
the reference leader-arm sender at /Users/omar/n1o0/robot_sim/src
(so101_leader.py + motors_bus.py): arm joints use RANGE_M100_100 and
the gripper uses RANGE_0_100. Joint limits below are the URDF nominal
limits — same values RobotKinematics.swift decodes against.

Run:
    pip install -r requirements.txt
    python sender.py
"""

import argparse
import asyncio
import json
import math
import os
import threading
import time
import urllib.request
from dataclasses import dataclass, field
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
import websockets
from ikpy.chain import Chain
from ikpy.link import OriginLink, URDFLink
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision


# --- SO-101 kinematic chain (mirrors Shared/Game/RobotKinematics.swift) ----

JOINT_DEFS = [
    # (name, xyz, rpy, min_rad, max_rad)
    ("shoulder_pan",  [ 0.0388,  0.0000,  0.0624], [ math.pi,      0.0,         -math.pi    ], -1.92, 1.92),
    ("shoulder_lift", [-0.0304, -0.0183, -0.0542], [-math.pi / 2, -math.pi / 2,  0.0        ], -1.75, 1.75),
    ("elbow_flex",    [-0.1126, -0.0280,  0.0000], [ 0.0,          0.0,          math.pi / 2], -1.69, 1.69),
    ("wrist_flex",    [-0.1349,  0.0052,  0.0000], [ 0.0,          0.0,         -math.pi / 2], -1.66, 1.66),
    ("wrist_roll",    [ 0.0000, -0.0611,  0.0181], [ math.pi / 2,  0.0487,       math.pi    ], -2.74, 2.84),
]
EE_OFFSET = [0.0202, 0.0188, -0.0234]
EE_RPY = [math.pi / 2, 0.0, 0.0]
GRIPPER_MIN, GRIPPER_MAX = -0.17, 1.75

# IK uses a subset of the URDF range to keep solutions away from joint limits
# (avoids ikpy returning saturated/jittery poses). 0.85 = ±85% of full URDF.
JOINT_SAFETY = 0.85

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
MODEL_PATH = os.path.join(os.path.dirname(__file__), "hand_landmarker.task")


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


def ensure_model() -> str:
    if not os.path.exists(MODEL_PATH):
        print(f"downloading hand_landmarker model -> {MODEL_PATH}")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    return MODEL_PATH


# --- Hand landmarks -> robot target ----------------------------------------

# SO-101 reachable workspace, derived from URDF link lengths in JOINT_DEFS:
#   upper arm ≈ 0.116 m + forearm ≈ 0.135 m + wrist/EE ≈ 0.06 m → ~0.31 m reach.
#   Shoulder origin sits ~0.062 m above the base.
WORKSPACE_X = (0.08, 0.28)   # forward range  (m)
WORKSPACE_Y = (-0.20, 0.20)  # sideways range (m), +Y = robot's left in URDF
WORKSPACE_Z = (0.04, 0.30)   # vertical range (m), measured from base


def hand_to_target(lm_img) -> list[float]:
    """Map normalized image landmarks to a target position in URDF (Z-up) frame.

    Image x ∈ [0,1] (mirrored, so right hand on right of screen) -> robot −Y (right)
    Image y ∈ [0,1] (0=top)                                      -> robot +Z (up)
    Hand size in image (bigger = closer to camera)               -> robot +X (forward)
    """
    wrist = lm_img[0]
    middle_mcp = lm_img[9]
    hand_scale = math.hypot(middle_mcp.x - wrist.x, middle_mcp.y - wrist.y)
    # Empirically: ~0.05 (hand far from camera) .. 0.20 (close).
    s = max(0.0, min(1.0, (hand_scale - 0.05) / 0.15))

    def lerp(rng, t):
        return rng[0] + (rng[1] - rng[0]) * t

    rx = lerp(WORKSPACE_X, s)                    # closer hand → further forward
    ry = lerp(WORKSPACE_Y, 1.0 - wrist.x)        # left-of-image → +Y
    rz = lerp(WORKSPACE_Z, 1.0 - wrist.y)        # top-of-image  → +Z
    return [rx, ry, rz]


def gripper_norm(lm_world) -> float:
    """Thumb-tip ↔ index-tip distance (meters, wrist-origin) -> [0, 100]."""
    t = lm_world[4]
    i = lm_world[8]
    d = math.sqrt((t.x - i.x) ** 2 + (t.y - i.y) ** 2 + (t.z - i.z) ** 2)
    closed, open_ = 0.025, 0.10
    pct = (d - closed) / (open_ - closed) * 100.0
    return float(max(0.0, min(100.0, pct)))


def joint_norm(angle: float, lo: float, hi: float) -> float:
    """Radians -> normalized [-100, 100] using URDF limits."""
    t = (angle - lo) / (hi - lo)
    return float(max(-100.0, min(100.0, t * 200.0 - 100.0)))


# --- Shared state -----------------------------------------------------------

@dataclass
class State:
    # Producer = capture thread, consumer = IK thread.
    latest_target: Optional[np.ndarray] = None   # [x, y, z] in URDF frame
    latest_gripper: float = 0.0                  # [0, 100]
    # Producer = IK thread, consumer = WS handler(s).
    latest_msg: Optional[dict] = None
    running: bool = True
    lock: threading.Lock = field(default_factory=threading.Lock)


# --- Capture loop (main thread: cv2 + MediaPipe + draw) ---------------------

def step_capture(cap, landmarker, state: State, *, t0: float, show: bool):
    ok, frame = cap.read()
    if not ok:
        return
    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    ts_ms = int((time.time() - t0) * 1000)
    result = landmarker.detect_for_video(mp_image, ts_ms)

    if result.hand_landmarks:
        lm_img = result.hand_landmarks[0]
        lm_world = result.hand_world_landmarks[0]
        target = np.array(hand_to_target(lm_img))
        grip = gripper_norm(lm_world)
        with state.lock:
            state.latest_target = target
            state.latest_gripper = grip

        if show:
            draw_landmarks(frame, lm_img)
            cv2.putText(
                frame,
                f"target xyz: {target[0]:+.2f} {target[1]:+.2f} {target[2]:+.2f}",
                (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2,
            )

    if show:
        cv2.imshow("hand -> SO-101", frame)
        if cv2.waitKey(1) & 0xFF == 27:  # esc
            state.running = False


# --- IK worker (background thread) ------------------------------------------

def ik_worker(chain, state: State, hz: float):
    period = 1.0 / hz
    prev_angles = [0.0] * (len(JOINT_DEFS) + 2)
    smoothed: Optional[np.ndarray] = None
    last_warn = 0.0
    while state.running:
        t0 = time.perf_counter()
        with state.lock:
            target = state.latest_target
            grip = state.latest_gripper
        if target is not None:
            smoothed = target if smoothed is None else 0.7 * smoothed + 0.3 * target
            angles = chain.inverse_kinematics(
                target_position=smoothed.tolist(),
                initial_position=prev_angles,
            )
            prev_angles = list(angles)
            msg = {}
            saturated = []
            for i, (name, _, _, lo, hi) in enumerate(JOINT_DEFS):
                mid, half = 0.5 * (lo + hi), 0.5 * (hi - lo) * JOINT_SAFETY
                slo, shi = mid - half, mid + half
                a = angles[i + 1]
                if a < slo + 0.02 or a > shi - 0.02:
                    saturated.append(name)
                msg[f"{name}.pos"] = joint_norm(a, lo, hi)
            msg["gripper.pos"] = grip
            with state.lock:
                state.latest_msg = msg
            if saturated and t0 - last_warn > 1.0:
                print(f"IK saturated: {','.join(saturated)} "
                      f"(target {smoothed[0]:+.2f},{smoothed[1]:+.2f},{smoothed[2]:+.2f})")
                last_warn = t0
        dt = time.perf_counter() - t0
        time.sleep(max(0.0, period - dt))


HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),            # thumb
    (0, 5), (5, 6), (6, 7), (7, 8),            # index
    (5, 9), (9, 10), (10, 11), (11, 12),       # middle
    (9, 13), (13, 14), (14, 15), (15, 16),     # ring
    (13, 17), (17, 18), (18, 19), (19, 20),    # pinky
    (0, 17),                                    # palm
]


def draw_landmarks(frame, lm_img):
    h, w = frame.shape[:2]
    pts = [(int(p.x * w), int(p.y * h)) for p in lm_img]
    for a, b in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], (200, 200, 200), 2)
    for p in pts:
        cv2.circle(frame, p, 4, (0, 200, 255), -1)


# --- WebSocket server -------------------------------------------------------

async def ws_handler(ws, state: State, send_hz: float):
    peer = ws.remote_address
    print(f"client connected: {peer}")
    period = 1.0 / send_hz
    last_sent_id: Optional[int] = None
    try:
        while state.running:
            with state.lock:
                msg = state.latest_msg
            if msg is not None and id(msg) != last_sent_id:
                await ws.send(json.dumps(msg))
                last_sent_id = id(msg)
            await asyncio.sleep(period)
    except websockets.ConnectionClosed:
        pass
    finally:
        print(f"client disconnected: {peer}")


async def capture_task(cap, landmarker, state: State, show: bool):
    """Runs on the asyncio main thread so cv2.imshow stays on macOS's main thread.

    Each iteration blocks ~30-50 ms (cap.read + MediaPipe + draw + imshow).
    The await yield between iterations lets the WS handler send to the client;
    heavy IK runs on a separate thread (ik_worker), not here.
    """
    t0 = time.time()
    while state.running:
        step_capture(cap, landmarker, state, t0=t0, show=show)
        # Yield so ws_handler coroutines can drain the latest_msg.
        await asyncio.sleep(0.001)


async def main_async(args):
    chain = build_chain()
    state = State()

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        raise SystemExit(f"could not open camera {args.camera}")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    model_path = ensure_model()
    options = mp_vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=model_path),
        running_mode=mp_vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.6,
        min_tracking_confidence=0.5,
    )
    landmarker = mp_vision.HandLandmarker.create_from_options(options)

    ik_thread = threading.Thread(
        target=ik_worker, args=(chain, state, args.ik_hz), daemon=True)
    ik_thread.start()

    async def handler(ws):
        await ws_handler(ws, state, args.send_hz)

    async with websockets.serve(handler, args.host, args.port):
        print(f"WS server listening on ws://{args.host}:{args.port}")
        print("press ESC in the preview window (or Ctrl+C) to quit")
        try:
            await capture_task(cap, landmarker, state, not args.no_preview)
        finally:
            state.running = False

    ik_thread.join(timeout=1.0)
    cap.release()
    cv2.destroyAllWindows()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--camera", type=int, default=0)
    p.add_argument("--send-hz", type=float, default=30.0)
    p.add_argument("--ik-hz", type=float, default=20.0,
                   help="IK solve rate. Lower if CPU is pegged.")
    p.add_argument("--no-preview", action="store_true")
    args = p.parse_args()
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
