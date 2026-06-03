"""Interactive camera→robot frame calibration ("show me max" workflow).

You move your hand to define each robot axis and the gripper / wrist-roll
ranges. The script computes a single 3×3 matrix that maps stereo (or mono)
hand units into robot meters, plus gripper and roll calibration. No manual
WORKSPACE_SCALE or ROBOT_FROM_CAM tuning required.

Works in two modes:

  Stereo (default — needs stereo_calib.npz from calibrate_hand.py):
      python calibrate_robot_frame.py --mode stereo \
             --calib stereo_calib.npz --left 0 --right 1

  Mono (single camera, no prior calibration needed):
      python calibrate_robot_frame.py --mode mono --camera 0

Output: user_calib.npz, automatically loaded by stereo_sender.py.

Steps (press SPACE at each, R to restart, ESC to quit):
  1  HOME — hand at the position the robot's end-effector should rest at
  2  RIGHT extreme — hand at the far-right reach of your workspace
  3  UP extreme — hand at the top of your workspace
  4  FORWARD extreme — hand reached away from cameras
  5  PINCH CLOSED — thumb + index tightly touching
  6  PINCH OPEN — thumb + index spread as wide as comfortable
  7  ROLL CW — wrist rotated clockwise (palm-down twist) as far as comfortable
  8  ROLL CCW — wrist rotated counter-clockwise as far as comfortable
"""

import argparse
import math
import sys
import time

import cv2
import numpy as np

from hand_pose import (
    StereoTriangulator,
    make_landmarker,
    mono_pose,
    stereo_pose,
    wrist_roll,
)


# Maximum hand-driven motion from home, in robot meters per axis.
# 12 cm = ~SO-101 reasonable reach in each direction from a central home pose.
ROBOT_REACH_M = 0.12

STEPS = [
    ("HOME",         "Hold hand at the ROBOT'S HOME POSITION"),
    ("RIGHT",        "Move hand to YOUR RIGHT (workspace right extreme)"),
    ("UP",           "Move hand UP (workspace top extreme)"),
    ("FORWARD",      "Move hand AWAY from the cameras (forward extreme)"),
    ("PINCH_CLOSED", "Thumb + index touching tightly (gripper CLOSED)"),
    ("PINCH_OPEN",   "Thumb + index spread WIDE (gripper OPEN)"),
    ("ROLL_CW",      "Rotate wrist CLOCKWISE as far as comfortable"),
    ("ROLL_CCW",     "Rotate wrist COUNTER-CLOCKWISE as far as comfortable"),
]


def open_camera(index: int) -> cv2.VideoCapture:
    cap = cv2.VideoCapture(index, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        sys.exit(f"Could not open camera {index}")
    return cap


def draw_overlay(frame, step_idx, step_label, ok, n_steps):
    color = (0, 220, 80) if ok else (0, 165, 255)
    cv2.putText(frame, f"step {step_idx+1}/{n_steps}", (12, 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
    cv2.putText(frame, step_label, (12, 56),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)
    hint = "SPACE = capture this step" if ok \
        else "waiting for both cameras to detect hand…"
    cv2.putText(frame, hint, (12, 80),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["stereo", "mono"], default="stereo")
    p.add_argument("--calib", default="stereo_calib.npz",
                   help="stereo geometry calibration (stereo mode only)")
    p.add_argument("--left", type=int, default=0)
    p.add_argument("--right", type=int, default=1)
    p.add_argument("--camera", type=int, default=0,
                   help="camera index (mono mode)")
    p.add_argument("--out", default="user_calib.npz")
    args = p.parse_args()

    if args.mode == "stereo":
        tri = StereoTriangulator(args.calib)
        capL = open_camera(args.left)
        capR = open_camera(args.right)
        lmL = make_landmarker()
        lmR = make_landmarker()
        cams = (capL, capR)
        landmarkers = (lmL, lmR)
    else:
        cap = open_camera(args.camera)
        lm = make_landmarker()
        cams = (cap,)
        landmarkers = (lm,)
        tri = None

    captures: dict[str, tuple[np.ndarray, np.ndarray, float]] = {}
    t0 = time.time()

    print("\nSPACE = capture · R = restart · ESC = quit\n")
    for step_key, step_label in STEPS:
        print(f"  step '{step_key}': {step_label}")

    step_idx = 0
    while step_idx < len(STEPS):
        frames = []
        bad = False
        for c in cams:
            ok, f = c.read()
            if not ok or f is None:
                bad = True
                break
            frames.append(f)
        if bad:
            continue

        ts = int((time.time() - t0) * 1000)
        if args.mode == "stereo":
            lmL_, lmR_ = landmarkers[0], landmarkers[-1]
            pose = stereo_pose(frames[0], frames[1], lmL_, lmR_, tri, ts)
        else:
            pose = mono_pose(frames[0], landmarkers[0], ts)

        ok = pose is not None
        step_key, step_label = STEPS[step_idx]
        for f in frames:
            draw_overlay(f, step_idx, step_label, ok, len(STEPS))

        # Side-by-side display
        h = min(f.shape[0] for f in frames)
        resized = [cv2.resize(f, (int(f.shape[1] * h / f.shape[0]), h))
                   for f in frames]
        cv2.imshow("Robot-frame calibration", np.hstack(resized))

        key = cv2.waitKey(1) & 0xFF
        if key == 27:                                # ESC
            sys.exit("Aborted")
        if key == ord('r'):
            captures.clear()
            step_idx = 0
            print("Restarted.")
        if key == ord(' ') and pose is not None:
            captures[step_key] = pose
            print(f"  ✓ {step_key}")
            step_idx += 1

    for c in cams: c.release()
    cv2.destroyAllWindows()

    # -------------- Compute calibration --------------

    print("\nComputing calibration…")
    home_wrist, home_frame, _ = captures["HOME"]
    right_w,    _, _          = captures["RIGHT"]
    up_w,       _, _          = captures["UP"]
    fwd_w,      _, _          = captures["FORWARD"]

    # Camera-space direction vectors (from home to each extreme)
    M = np.column_stack([
        right_w - home_wrist,
        up_w    - home_wrist,
        fwd_w   - home_wrist,
    ]).astype(np.float64)

    # Robot-space motions we want these to map to (URDF Y-up).
    # User RIGHT → robot -Y (right = negative left)
    # User UP    → robot +Z
    # User FWD   → robot +X (forward)
    D = np.column_stack([
        np.array([0, -ROBOT_REACH_M, 0]),     # cam right vector → robot -Y
        np.array([0,  0,  ROBOT_REACH_M]),    # cam up    vector → robot +Z
        np.array([ROBOT_REACH_M, 0,  0]),     # cam fwd   vector → robot +X
    ]).astype(np.float64)

    try:
        robot_from_cam = D @ np.linalg.inv(M)
    except np.linalg.LinAlgError:
        sys.exit("Calibration failed: axis captures were collinear. "
                 "Make sure RIGHT / UP / FORWARD are in genuinely different "
                 "directions.")

    # Gripper bounds
    _, _, grip_closed = captures["PINCH_CLOSED"]
    _, _, grip_open   = captures["PINCH_OPEN"]
    if grip_open <= grip_closed:
        sys.exit("PINCH_OPEN ratio ≤ PINCH_CLOSED — captures were swapped?")

    # Roll bounds (radians, relative to HOME orientation)
    _, frame_cw,  _ = captures["ROLL_CW"]
    _, frame_ccw, _ = captures["ROLL_CCW"]
    roll_cw  = wrist_roll(frame_cw,  home_frame)
    roll_ccw = wrist_roll(frame_ccw, home_frame)
    # CW should be more negative-roll-ish or more positive depending on sign;
    # store both and let the sender pick the correct mapping by sign.
    roll_min = roll_cw if roll_cw < roll_ccw else roll_ccw
    roll_max = roll_cw if roll_cw > roll_ccw else roll_ccw

    print(f"\nROBOT_FROM_CAM:\n{robot_from_cam}")
    print(f"home_wrist (cam units): {home_wrist}")
    print(f"gripper range: {grip_closed:.3f} .. {grip_open:.3f}")
    print(f"roll range:    {roll_min:.3f} .. {roll_max:.3f} rad "
          f"({math.degrees(roll_min):.0f} .. {math.degrees(roll_max):.0f}°)")

    np.savez(args.out,
             mode=args.mode,
             robot_from_cam=robot_from_cam,
             home_wrist=home_wrist,
             home_frame=home_frame,
             grip_closed=grip_closed,
             grip_open=grip_open,
             roll_min=roll_min,
             roll_max=roll_max)
    print(f"\nSaved {args.out}")
    print(f"Next: python stereo_sender.py --mode {args.mode} "
          f"--user-calib {args.out}"
          f"{' --calib ' + args.calib if args.mode == 'stereo' else ''}")


if __name__ == "__main__":
    main()
