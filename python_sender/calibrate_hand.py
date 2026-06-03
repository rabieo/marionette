"""Checkerboard-free stereo geometry calibration using a human hand.

Recovers the relative rotation R and unit-direction translation T̂ between
the two cameras from pooled 2D landmark correspondences across N hand poses.
Absolute scale is NOT recovered — calibrate_robot_frame.py handles the
camera-to-robot mapping and collapses the unknown scale into the user's
preferred workspace size.

Pipeline:
    1. Capture ~6 hand-pose pairs from both cameras.
    2. Pool all 2D landmark correspondences (N × 21 ≈ 126 points).
    3. Recover R, T̂ via cv2.findEssentialMat → cv2.recoverPose.
    4. Sanity-check via reprojection error.

Run:
    python calibrate_hand.py --left 0 --right 1

Output: stereo_calib.npz consumed by stereo_sender.py and
calibrate_robot_frame.py in --mode stereo.
"""

import argparse
import os
import sys
import time
import urllib.request

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision


MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
MODEL_PATH = os.path.join(os.path.dirname(__file__), "hand_landmarker.task")

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (5, 9), (9, 10), (10, 11), (11, 12),
    (9, 13), (13, 14), (14, 15), (15, 16),
    (13, 17), (17, 18), (18, 19), (19, 20),
    (0, 17),
]

# Six captures = minimum diversity to constrain R + T̂ from N × 21 correspondences.
INSTRUCTIONS = [
    "1/6  OPEN HAND (palm flat, 5 fingers spread) at CENTER",
    "2/6  OPEN HAND, move to one CORNER of view",
    "3/6  OPEN HAND, move to the OPPOSITE corner",
    "4/6  OPEN HAND, very CLOSE to cameras (~30 cm)",
    "5/6  OPEN HAND, FAR away (arm fully extended)",
    "6/6  CLOSED FIST at center (breaks the flat-hand ambiguity)",
    "Extras (optional) — any new pose",
]


def ensure_model() -> str:
    if not os.path.exists(MODEL_PATH):
        print(f"downloading hand_landmarker model → {MODEL_PATH}")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    return MODEL_PATH


def default_intrinsics(w: int, h: int) -> tuple[np.ndarray, np.ndarray]:
    """Sane default for unknown webcams (~67° HFOV)."""
    f = 0.65 * w
    K = np.array([[f, 0, w / 2.0],
                  [0, f, h / 2.0],
                  [0, 0,       1]], dtype=np.float64)
    D = np.zeros(5, dtype=np.float64)
    return K, D


def open_camera(index: int) -> cv2.VideoCapture:
    cap = cv2.VideoCapture(index, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        sys.exit(f"Could not open camera {index}")
    return cap


def make_landmarker(model_path: str):
    opts = mp_vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=model_path),
        running_mode=mp_vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.6,
        min_tracking_confidence=0.5)
    return mp_vision.HandLandmarker.create_from_options(opts)


def draw_landmarks(frame: np.ndarray, landmarks) -> None:
    h, w = frame.shape[:2]
    pts = [(int(p.x * w), int(p.y * h)) for p in landmarks]
    for a, b in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], (200, 200, 200), 2)
    for p in pts:
        cv2.circle(frame, p, 4, (0, 200, 255), -1)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--left", type=int, default=0)
    p.add_argument("--right", type=int, default=1)
    p.add_argument("--out", default="stereo_calib.npz")
    p.add_argument("--min-pairs", type=int, default=6)
    args = p.parse_args()

    capL = open_camera(args.left)
    capR = open_camera(args.right)
    model_path = ensure_model()
    lmL = make_landmarker(model_path)
    lmR = make_landmarker(model_path)

    captures: list[dict] = []
    flash_until = 0.0
    sizeL = sizeR = None
    t0 = time.time()

    print("ORIENT HAND so both cameras detect (palm midway between cameras).")
    print("HOLD STILL ~1 sec before SPACE — wireless camera bridges lag ~100 ms.\n")
    print("SPACE=capture · C=calibrate · R=reset · ESC=quit\n")

    while True:
        okL, frameL = capL.read()
        okR, frameR = capR.read()
        if not (okL and okR):
            continue

        rgbL = cv2.cvtColor(frameL, cv2.COLOR_BGR2RGB)
        rgbR = cv2.cvtColor(frameR, cv2.COLOR_BGR2RGB)
        ts = int((time.time() - t0) * 1000)
        resL = lmL.detect_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgbL), ts)
        resR = lmR.detect_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgbR), ts)

        hasL = bool(resL.hand_landmarks)
        hasR = bool(resR.hand_landmarks)
        if hasL: draw_landmarks(frameL, resL.hand_landmarks[0])
        if hasR: draw_landmarks(frameR, resR.hand_landmarks[0])

        both = hasL and hasR
        color = (0, 220, 80) if both else (0, 165, 255)
        n = len(captures)
        status = (f"L:{'OK' if hasL else '--'}  R:{'OK' if hasR else '--'}  "
                  f"captures:{n}/{args.min_pairs}+")
        instruction = INSTRUCTIONS[min(n, len(INSTRUCTIONS) - 1)]
        for f in (frameL, frameR):
            cv2.putText(f, status, (12, 28),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
            cv2.putText(f, instruction, (12, 56),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)
            if both:
                cv2.putText(f, "SPACE = capture", (12, 80),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 220, 80), 1)

        h = min(frameL.shape[0], frameR.shape[0])
        L = cv2.resize(frameL, (int(frameL.shape[1] * h / frameL.shape[0]), h))
        R_ = cv2.resize(frameR, (int(frameR.shape[1] * h / frameR.shape[0]), h))
        combined = np.hstack([L, R_])
        if time.time() < flash_until:
            cv2.rectangle(combined, (0, 0),
                          (combined.shape[1], combined.shape[0]),
                          (255, 255, 255), -1)
        cv2.imshow("Hand stereo calibration  (left | right)", combined)

        sizeL = (frameL.shape[1], frameL.shape[0])
        sizeR = (frameR.shape[1], frameR.shape[0])

        key = cv2.waitKey(1) & 0xFF
        if key == 27:
            capL.release(); capR.release(); cv2.destroyAllWindows()
            sys.exit("Aborted.")
        if key == ord('r'):
            captures.clear()
            print("Reset.")
        if key == ord(' ') and both:
            # Drain stale frames + verify hand is still.
            for _ in range(5):
                capL.read(); capR.read()

            def sample():
                _, fL = capL.read(); _, fR = capR.read()
                tsn = int((time.time() - t0) * 1000)
                rL = lmL.detect_for_video(
                    mp.Image(image_format=mp.ImageFormat.SRGB,
                             data=cv2.cvtColor(fL, cv2.COLOR_BGR2RGB)), tsn)
                rR = lmR.detect_for_video(
                    mp.Image(image_format=mp.ImageFormat.SRGB,
                             data=cv2.cvtColor(fR, cv2.COLOR_BGR2RGB)), tsn + 1)
                if not (rL.hand_landmarks and rR.hand_landmarks):
                    return None
                wL = np.array([[p.x * sizeL[0], p.y * sizeL[1]]
                               for p in rL.hand_landmarks[0]])
                wR = np.array([[p.x * sizeR[0], p.y * sizeR[1]]
                               for p in rR.hand_landmarks[0]])
                return wL, wR

            s1 = sample()
            time.sleep(0.15)
            s2 = sample()
            if s1 is None or s2 is None:
                print("  ⚠ lost detection during stillness check")
                continue
            dL = float(np.linalg.norm(s1[0] - s2[0], axis=1).mean())
            dR = float(np.linalg.norm(s1[1] - s2[1], axis=1).mean())
            if dL > 4 or dR > 4:
                print(f"  ⚠ hand moved (L:{dL:.1f}px R:{dR:.1f}px) — retry")
                continue

            captures.append({"imgL": s2[0], "imgR": s2[1]})
            flash_until = time.time() + 0.08
            print(f"  captured pose {len(captures)}: {instruction}")
        if key == ord('c'):
            if len(captures) < 5:
                print(f"Need 5+ captures (have {len(captures)}).")
                continue
            break

    capL.release(); capR.release(); cv2.destroyAllWindows()

    print(f"\nCalibrating from {len(captures)} captures…")
    K1, D1 = default_intrinsics(*sizeL)
    K2, D2 = default_intrinsics(*sizeR)

    # Pool 2D correspondences across all captures.
    ptsL_all = np.vstack([c["imgL"] for c in captures])
    ptsR_all = np.vstack([c["imgR"] for c in captures])

    # Normalize (undistort) to remove the intrinsics from the essential matrix.
    ptsL_norm = cv2.undistortPoints(
        ptsL_all.reshape(-1, 1, 2), K1, D1).reshape(-1, 2)
    ptsR_norm = cv2.undistortPoints(
        ptsR_all.reshape(-1, 1, 2), K2, D2).reshape(-1, 2)

    # Essential matrix + relative pose recovery.
    E, inlier_mask = cv2.findEssentialMat(
        ptsL_norm, ptsR_norm,
        cameraMatrix=np.eye(3),
        method=cv2.RANSAC, prob=0.999, threshold=0.006)
    if E is None:
        sys.exit("Essential matrix estimation failed.")
    n_inliers = int(inlier_mask.sum())
    print(f"  essential matrix: {n_inliers}/{len(ptsL_norm)} inliers")

    _, R, t_unit, _ = cv2.recoverPose(
        E, ptsL_norm, ptsR_norm,
        cameraMatrix=np.eye(3), mask=inlier_mask)
    T = t_unit.reshape(3, 1)

    # Reprojection sanity check (unit-scale triangulation).
    P1 = np.hstack([np.eye(3), np.zeros((3, 1))])
    P2 = np.hstack([R, T])
    pts4d = cv2.triangulatePoints(P1, P2, ptsL_norm.T, ptsR_norm.T)
    pts3d = (pts4d[:3] / pts4d[3]).T

    proj_L, _ = cv2.projectPoints(pts3d, np.zeros(3), np.zeros(3), K1, D1)
    proj_R, _ = cv2.projectPoints(pts3d, cv2.Rodrigues(R)[0], T, K2, D2)
    err_L = np.linalg.norm(proj_L.reshape(-1, 2) - ptsL_all, axis=1)
    err_R = np.linalg.norm(proj_R.reshape(-1, 2) - ptsR_all, axis=1)
    rms = float(np.sqrt(np.mean(np.concatenate([err_L, err_R])**2)))

    print(f"\nReprojection RMS:    {rms:.2f} px "
          f"({'great' if rms < 4 else 'OK' if rms < 10 else 'recapture'})")
    print(f"Inliers:             {n_inliers}/{len(ptsL_all)} "
          f"({100*n_inliers/len(ptsL_all):.0f}%)")

    if rms > 10:
        print("  ⚠️  RMS is high — recapture with more position/pose variety.")

    np.savez(args.out,
             K1=K1, D1=D1, K2=K2, D2=D2,
             R=R, T=T,
             E=E, F=np.zeros((3, 3)),
             size_left=np.array(sizeL),
             size_right=np.array(sizeR),
             rms=rms)
    print(f"\nSaved {args.out}  (R + unit T̂; scale handled at runtime)")


if __name__ == "__main__":
    main()
