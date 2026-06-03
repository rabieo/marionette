# Marionette

A real-time robotics simulation platform on a tile-based deferred Metal
renderer, driven by webcam hand-tracking and stereo triangulation. Move your
hand in front of a camera, the virtual robot mirrors it — position, wrist
orientation, and pinch-to-grip.

> **Status: active personal project.** The renderer and end-to-end
> hand-tracking → IK → robot pipeline are working; a custom differentiable
> physics engine and sim-to-real bridge are the next milestones.

---

## What this is

A working prototype of the kind of simulation platform the
[Canadian DRDC / IDEaS challenge](https://www.canada.ca/en/department-national-defence/programs/defence-ideas.html)
on shared-autonomy robotic teleoperation describes — combined hardware-and-virtual
environment for programming a remote manipulator with human-in-the-loop input,
with future hooks for online learning.

Concretely, what works today:

- **Photorealistic-ish Metal renderer** — tile-based deferred (TBDR) on Apple
  Silicon, with PBR shading, PCF soft shadows, ACES tonemapping, sRGB
  framebuffer, three-point lighting, and a Blender-style procedural grid floor.
- **SO-101 5-DOF robot arm** rendered from the URDF — links placed via each
  STL's `<visual><origin>` metadata, with the correct URDF fixed-axis rpy
  convention (`Rz·Ry·Rx`) rather than the more common (wrong) `Rx·Ry·Rz`.
- **Camera hand-tracking pipeline** — two cameras → MediaPipe HandLandmarker on
  each → essential-matrix stereo geometry → 3D wrist triangulation. Falls back
  to single-camera with a hand-size depth proxy.
- **User-driven calibration** — 8-step "show me where you want max reach"
  wizard that derives the camera-to-robot frame transform, gripper bounds,
  and wrist-roll bounds without any checkerboards or hand-measured units.
- **Inverse kinematics + WebSocket bridge** — ikpy solves a 5-DOF chain for the
  end-effector target, streams normalized motor commands at 30 Hz to the Swift
  renderer's WebSocket client.
- **SwiftUI editor chrome** — Scene Outliner, Inspector with live joint state,
  Bottom dock with a Hand Tracker panel, mode picker, connection pills, E-stop.

## Architecture

```
        ┌─────────────────────────────────┐    WebSocket    ┌────────────────────────┐
        │ python_sender                   │  motor values   │ Swift / Metal app      │
        │                                 │  ────────────>  │                        │
        │  cv2.VideoCapture  →  MediaPipe │                 │  RobotWebSocketClient  │
        │  HandLandmarker (per camera)    │                 │      ↓                 │
        │       ↓                         │                 │  RobotKinematics       │
        │  StereoTriangulator             │                 │  (URDF forward kin.)   │
        │  (essential matrix, R + T̂)      │                 │      ↓                 │
        │       ↓                         │                 │  TBDR render pipeline  │
        │  hand_pose ─→ (wrist_3d,        │                 │  (g-buffer + lighting  │
        │               hand_frame,       │                 │   + shadow pass)       │
        │               gripper_ratio)    │                 │      ↓                 │
        │       ↓                         │                 │  SwiftUI editor UI     │
        │  user_calib ─→ robot frame      │                 │  (Outliner, Inspector, │
        │       ↓                         │                 │   Hand Tracker dock)   │
        │  ikpy.inverse_kinematics        │                 │                        │
        │       ↓                         │                 │                        │
        │  WebSocket server (asyncio)     │                 │                        │
        └─────────────────────────────────┘                 └────────────────────────┘
```

Per-frame data flow at runtime: webcam frames → 21 2D landmarks per view →
triangulate to 3D in arbitrary stereo units → delta from the calibrated home
position → mapped to robot meters via the user calibration matrix → ikpy
solves joint angles → normalized `[-100, 100]` → JSON over WS → Swift's
forward kinematics → world matrices for each STL → Metal renders.

## Tech stack

| Layer | Tech |
|---|---|
| Rendering | Swift, Metal (TBDR pipeline), SwiftUI |
| Hand tracking | Python, OpenCV, MediaPipe HandLandmarker (Tasks API) |
| Stereo geometry | OpenCV essential matrix from pooled 2D correspondences |
| Robot frame calibration | Original 8-step interactive wizard ("show me max" workflow) |
| Inverse kinematics | ikpy with joint-limit clamping + EMA smoothing |
| Transport | WebSocket (asyncio server + URLSessionWebSocketTask client) |
| Robot model | [SO-ARM100 / SO-101 URDF](https://github.com/TheRobotStudio/SO-ARM100) |
| Renderer base | [*Metal by Tutorials* TBDR sample](https://www.kodeco.com/books/metal-by-tutorials) (ch. 15) |

## Repository layout

```
Shared/
  Game/                       — Renderer, scene, kinematics, WS client
  Geometry/                   — Model / mesh / transform / vertex descriptor
  Render Passes/              — Forward, deferred, tiled-deferred, shadow
  Shaders/                    — Metal shaders (gBuffer, lighting, PCF shadow,
                                ACES tonemap, procedural grid floor)
  SwiftUI Views/              — Editor UI (Outliner, Inspector, BottomDock,
                                TopBar, AppState)
  Models/                     — SO-101 STL meshes + scene OBJs
  Input/                      — Input controller, movement
  Utility/                    — MathLibrary, debug overlays

python_sender/
  hand_pose.py                — Shared MediaPipe + triangulation utilities
  calibrate_robot_frame.py    — Interactive robot-frame calibration wizard
  stereo_sender.py            — Main runtime (--mode stereo or --mode mono)
  requirements.txt            — Python dependencies
```

## Setup

### Swift app

Requires Xcode 26+ (macOS 26 SDK) — uses macOS 26 / iOS 26 deployment targets.

```bash
open TBDR.xcodeproj
# Build & Run on macOS or iOS target.
```

### Python sender

```bash
cd python_sender
pip install -r requirements.txt
```

**Stereo mode** (two cameras — better depth + occlusion handling):

```bash
# One-time calibration: ~6 hand poses for stereo geometry.
python calibrate_hand.py --left 0 --right 1

# One-time: derive your hand workspace → robot workspace mapping.
python calibrate_robot_frame.py --mode stereo --left 0 --right 1

# Run.
python stereo_sender.py --mode stereo --left 0 --right 1
```

**Mono mode** (single camera, simpler setup):

```bash
python calibrate_robot_frame.py --mode mono --camera 0
python stereo_sender.py --mode mono --camera 0
```

Run the Swift app; it auto-connects to `ws://localhost:8765`.

### Tips for the camera setup

- Stereo: ~30-45° angle between the two cameras gives the best balance between
  triangulation precision and MediaPipe correspondence quality. 90° is too wide
  — landmarks correspond poorly because perspectives diverge.
- A wired connection (USB-C) for any phone-as-webcam bridge beats wireless —
  Wi-Fi latency (~150 ms with apps like Iriun) hurts stereo sync more than
  resolution helps.

## Roadmap

- [ ] **Custom differentiable physics engine** (NVIDIA Warp / JAX-based) —
      rigid body dynamics + articulated bodies + LIDAR sensor model + MPM
      for deformables. The Genesis-style approach.
- [ ] **Sim-to-real bridge** to physical SO-101 hardware over the same WS
      protocol — kinematics already mirror the LeRobot/Feetech normalization
      convention, so the wire format is identical.
- [ ] **Bottom-dock telemetry plots** + demonstration recording for online
      learning experiments.
- [ ] **Multi-finger end-effector** support and SAM 3D-generated scene assets
      for contact-rich manipulation scenarios.
- [ ] **Haptic teleop** with force feedback to the operator.

## License

MIT for the original work in this repo. The TBDR rendering base from
*Metal by Tutorials* (Kodeco / Razeware) retains its original headers on
the files where it appears. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Metal by Tutorials](https://www.kodeco.com/books/metal-by-tutorials) — Tile-Based Deferred Rendering base
- [SO-ARM100 / SO-101](https://github.com/TheRobotStudio/SO-ARM100) — URDF + STL meshes
- [MediaPipe HandLandmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker) — 2D + 3D hand pose estimation
- [ikpy](https://github.com/Phylliade/ikpy) — Inverse kinematics
- [LeRobot](https://github.com/huggingface/lerobot) — Motor normalization conventions
