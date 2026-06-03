"""Shared hand-pose extraction for stereo and mono modes.

Both paths return the same three signals in arbitrary units, then
calibrate_robot_frame.py / stereo_sender.py handle the mapping to robot
coordinates via user_calib.npz.

Returned tuple per frame:
    (wrist_3d, hand_frame, gripper_ratio)
        wrist_3d:      np.ndarray (3,) — position in some arbitrary frame
        hand_frame:    np.ndarray (3,3) — orthonormal cols (right, up, fwd)
        gripper_ratio: float — thumb↔index distance / palm length
"""

from __future__ import annotations

import math
import os
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


def ensure_model() -> str:
    if not os.path.exists(MODEL_PATH):
        print(f"downloading hand_landmarker model → {MODEL_PATH}")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    return MODEL_PATH


def make_landmarker():
    opts = mp_vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=ensure_model()),
        running_mode=mp_vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_tracking_confidence=0.5)
    return mp_vision.HandLandmarker.create_from_options(opts)


def hand_frame(pts_3d: np.ndarray) -> np.ndarray:
    """3×3 orthonormal frame for the palm: cols = (right, up, forward).

    Uses landmarks 0 (wrist), 5 (index MCP), 9 (middle MCP), 17 (pinky MCP).
    Stable under finger articulation since palm landmarks don't move much.
    """
    wrist     = pts_3d[0]
    index_mcp = pts_3d[5]
    middle    = pts_3d[9]
    pinky_mcp = pts_3d[17]

    fwd = middle - wrist
    fwd /= max(float(np.linalg.norm(fwd)), 1e-9)

    right = pinky_mcp - index_mcp
    right -= float(np.dot(right, fwd)) * fwd
    right /= max(float(np.linalg.norm(right)), 1e-9)

    up = np.cross(fwd, right)
    return np.column_stack([right, up, fwd])


def wrist_roll(R_current: np.ndarray, R_home: np.ndarray) -> float:
    """Roll (radians) of current palm relative to home, around forward axis."""
    R_rel = R_home.T @ R_current
    return float(math.atan2(R_rel[1, 0], R_rel[0, 0]))


def gripper_ratio(pts_3d: np.ndarray) -> float:
    """Thumb-tip to index-tip distance, normalized by palm length.

    Scale-invariant — works in any 3D unit system (meters, pixels, stereo).
    Returns ratio (~0.1 for tight pinch, ~0.8+ for fully spread).
    """
    palm_len = float(np.linalg.norm(pts_3d[9] - pts_3d[0]))
    if palm_len < 1e-9:
        return 0.0
    return float(np.linalg.norm(pts_3d[4] - pts_3d[8])) / palm_len


class StereoTriangulator:
    """Triangulate corresponding 2D pixel points from two calibrated cameras.

    Returns 3D points in ARBITRARY units — calibration only resolved R, T̂
    so absolute scale is unknown. user_calib.npz handles the mapping.
    """

    def __init__(self, calib_path: str) -> None:
        d = np.load(calib_path)
        self.K1, self.D1 = d["K1"], d["D1"]
        self.K2, self.D2 = d["K2"], d["D2"]
        self.R,  self.T  = d["R"],  d["T"]
        self.P1 = np.hstack([np.eye(3), np.zeros((3, 1))])
        self.P2 = np.hstack([self.R, self.T.reshape(3, 1)])

    def triangulate(self, ptsL: np.ndarray, ptsR: np.ndarray) -> np.ndarray:
        ptsLn = cv2.undistortPoints(ptsL.reshape(-1, 1, 2).astype(np.float64),
                                    self.K1, self.D1).reshape(-1, 2)
        ptsRn = cv2.undistortPoints(ptsR.reshape(-1, 1, 2).astype(np.float64),
                                    self.K2, self.D2).reshape(-1, 2)
        pts_h = cv2.triangulatePoints(self.P1, self.P2, ptsLn.T, ptsRn.T)
        return (pts_h[:3] / pts_h[3]).T


def landmarks_2d(landmarks, width: int, height: int) -> np.ndarray:
    """Convert MediaPipe normalized landmarks to pixel coords (N, 2)."""
    return np.array([[p.x * width, p.y * height] for p in landmarks])


def world_landmarks_3d(world_landmarks) -> np.ndarray:
    """MediaPipe per-camera 3D landmarks (meters, hand-centered) as (N, 3)."""
    return np.array([[p.x, p.y, p.z] for p in world_landmarks])


def stereo_pose(
    frameL, frameR, lmL, lmR, tri: StereoTriangulator, ts_ms: int
) -> tuple[np.ndarray, np.ndarray, float] | None:
    """Stereo path: triangulate all 21 landmarks → pose in stereo units."""
    rgbL = cv2.cvtColor(frameL, cv2.COLOR_BGR2RGB)
    rgbR = cv2.cvtColor(frameR, cv2.COLOR_BGR2RGB)
    resL = lmL.detect_for_video(
        mp.Image(image_format=mp.ImageFormat.SRGB, data=rgbL), ts_ms)
    resR = lmR.detect_for_video(
        mp.Image(image_format=mp.ImageFormat.SRGB, data=rgbR), ts_ms + 1)
    if not (resL.hand_landmarks and resR.hand_landmarks):
        return None
    hL, wL = frameL.shape[:2]
    hR, wR = frameR.shape[:2]
    ptsL = landmarks_2d(resL.hand_landmarks[0], wL, hL)
    ptsR = landmarks_2d(resR.hand_landmarks[0], wR, hR)
    pts_3d = tri.triangulate(ptsL, ptsR)
    return pts_3d[0], hand_frame(pts_3d), gripper_ratio(pts_3d)


def mono_pose(
    frame, lm, ts_ms: int
) -> tuple[np.ndarray, np.ndarray, float] | None:
    """Single-camera path: wrist 3D = (image-x, image-y, 1/hand-size).

    Orientation comes from MediaPipe's per-frame world_landmarks (which are
    metric and hand-centered but only useful for orientation, not position).
    Gripper from the same world_landmarks (scale-invariant ratio).
    """
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    res = lm.detect_for_video(
        mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), ts_ms)
    if not res.hand_landmarks:
        return None
    lm2d = res.hand_landmarks[0]
    world = world_landmarks_3d(res.hand_world_landmarks[0])

    # Wrist position: image-x, image-y (centered), depth-proxy from hand size.
    # Hand size = wrist→middle-MCP distance in normalized image coords.
    wrist_x = lm2d[0].x - 0.5
    wrist_y = lm2d[0].y - 0.5
    middle_x = lm2d[9].x - 0.5
    middle_y = lm2d[9].y - 0.5
    hand_size_2d = math.hypot(middle_x - wrist_x, middle_y - wrist_y)
    depth_proxy = 1.0 / max(hand_size_2d, 1e-3)

    wrist_3d = np.array([wrist_x, wrist_y, depth_proxy])
    return wrist_3d, hand_frame(world), gripper_ratio(world)
