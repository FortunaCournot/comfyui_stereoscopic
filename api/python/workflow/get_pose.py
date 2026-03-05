#!/usr/bin/env python
"""Compute per-frame face visibility scores for a video.

This script is intended to run inside a ComfyUI installation that also has
`custom_nodes/comfyui_controlnet_aux` available. It uses the DWPose implementation
from that node pack to estimate pose/face keypoints.

Output: a JSON array of floats in [0.0, 1.0], one value per processed frame.

Default model parameters match the user's requested setup:
- resolution=512
- bbox_detector=yolox_l.onnx
- pose_estimator=dw-ll_ucoco_384_bs5.torchscript.pt

The score represents the visibility of the most significant face in the frame.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
import tempfile
import time
import warnings
from typing import Any, Dict, List, Optional, Tuple

import cv2


def _add_controlnet_aux_to_syspath() -> None:
    """Ensure `custom_controlnet_aux` can be imported.

    Repo layout (typical portable ComfyUI):
    ComfyUI/
      custom_nodes/
        comfyui_stereoscopic/
          api/python/workflow/get_pose.py  (this file)
        comfyui_controlnet_aux/
          src/custom_controlnet_aux/
    """

    here = os.path.abspath(os.path.dirname(__file__))
    comfyui_path = os.path.abspath(
        os.path.join(here, "..", "..", "..", "..", "..")
    )
    aux_src = os.path.join(
        comfyui_path, "custom_nodes", "comfyui_controlnet_aux", "src"
    )

    # Allow importing ComfyUI's own packages (e.g. `comfy.model_management`)
    # even when the script is launched outside the ComfyUI working directory.
    if os.path.isdir(comfyui_path) and comfyui_path not in sys.path:
        sys.path.insert(0, comfyui_path)

    if os.path.isdir(aux_src) and aux_src not in sys.path:
        sys.path.insert(0, aux_src)


def _pick_torchscript_device() -> str:
    """Best-effort device selection compatible with controlnet_aux DWPose."""

    try:
        import comfy.model_management as model_management  # type: ignore

        dev = model_management.get_torch_device()
        # model_management may return torch.device or a string.
        return str(dev)
    except Exception:
        pass

    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass

    return "cpu"


def _is_number_string(s: Optional[str]) -> bool:
    if s is None:
        return False
    try:
        float(s)
        return True
    except Exception:
        return False


def _face_visibility_from_openpose_dict(openpose_dict: Dict[str, Any]) -> float:
    """Compute a [0..1] face visibility score from an OpenPose-style dict.

    For each detected person we compute:
    - visibility = (#face keypoints present) / (total face keypoints)
    We pick the 'most significant' face as the one with the largest estimated
    face bounding box area among present keypoints.

    The DWPose encoder used here encodes confidence as 1.0 (present) or 0.0
    (missing), so visibility is a stable proxy for how much of the face is visible.
    """

    people = openpose_dict.get("people") or []
    best_vis = 0.0
    best_area = -1.0

    for person in people:
        face = person.get("face_keypoints_2d")
        if not face or not isinstance(face, list):
            continue
        confs = face[2::3]
        if not confs:
            continue

        total = len(confs)
        visible = 0
        xs: List[float] = []
        ys: List[float] = []
        for i in range(0, len(face) - 2, 3):
            c = face[i + 2]
            if isinstance(c, (int, float)) and c > 0.0:
                visible += 1
                x = face[i]
                y = face[i + 1]
                if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                    xs.append(float(x))
                    ys.append(float(y))

        vis = float(visible) / float(total) if total > 0 else 0.0
        if visible >= 2 and xs and ys:
            area = max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))
        else:
            area = 0.0

        if area > best_area:
            best_area = area
            best_vis = vis
        elif area == best_area and vis > best_vis:
            best_vis = vis

    if best_vis < 0.0:
        return 0.0
    if best_vis > 1.0:
        return 1.0
    return best_vis


def analyze_video(
    video_path: str,
    resolution: int = 512,
    bbox_detector: str = "yolox_l.onnx",
    pose_estimator: str = "dw-ll_ucoco_384_bs5.torchscript.pt",
    include_body: bool = False,
    include_hand: bool = False,
    include_face: bool = True,
    progress: bool = False,
    aux_logs: str = "ignore",
) -> List[float]:
    _add_controlnet_aux_to_syspath()

    # Silence known noisy warnings that are not actionable for normal runs.
    # This must happen before importing controlnet_aux (which imports torch).
    warnings.filterwarnings(
        "ignore",
        message=r"The pynvml package is deprecated\..*",
        category=FutureWarning,
        module=r"torch\.cuda.*",
    )

    # custom_controlnet_aux/util.py warns when these env vars are unset.
    # Set defaults here so the console stays clean.
    here = os.path.abspath(os.path.dirname(__file__))
    comfyui_path = os.path.abspath(os.path.join(here, "..", "..", "..", "..", ".."))
    aux_ckpts_default = os.path.join(
        comfyui_path, "custom_nodes", "comfyui_controlnet_aux", "ckpts"
    )
    os.environ.setdefault("AUX_ANNOTATOR_CKPTS_PATH", aux_ckpts_default)
    os.environ.setdefault("AUX_USE_SYMLINKS", "False")
    os.environ.setdefault("AUX_TEMP_DIR", tempfile.gettempdir())

    try:
        from custom_controlnet_aux.dwpose import DwposeDetector  # type: ignore
    except Exception as exc:
        raise RuntimeError(
            "Could not import custom_controlnet_aux.dwpose. "
            "Ensure ComfyUI has custom_nodes/comfyui_controlnet_aux installed and accessible."
        ) from exc

    device = _pick_torchscript_device()

    # Model repo selection matches the node wrapper in comfyui_controlnet_aux.
    # - yolox_l.onnx is in yzd-v/DWPose
    # - torchscript pose estimator is in hr16/DWPose-TorchScript-BatchSize5
    yolo_repo = "yzd-v/DWPose" if bbox_detector in ("None", "yolox_l.onnx") else "hr16/yolox-onnx"
    pose_repo = "hr16/DWPose-TorchScript-BatchSize5" if pose_estimator.endswith(".torchscript.pt") else "yzd-v/DWPose"

    det_filename = None if bbox_detector == "None" else bbox_detector

    # custom_controlnet_aux and its dependencies may print performance logs via
    # `print(...)` to stdout. We keep stdout clean (scores). By default we also
    # suppress these prints so a progress bar (stderr) stays readable.
    aux_sink = None
    if aux_logs == "stderr":
        aux_sink = sys.stderr
    else:
        aux_sink = open(os.devnull, "w")

    try:
        with contextlib.redirect_stdout(aux_sink):
            model = DwposeDetector.from_pretrained(
                pose_repo,
                yolo_repo,
                det_filename=det_filename,
                pose_filename=pose_estimator,
                torchscript_device=device,
            )
    except Exception:
        if aux_sink is not sys.stderr:
            try:
                aux_sink.close()
            except Exception:
                pass
        raise

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        if aux_sink is not sys.stderr:
            try:
                aux_sink.close()
            except Exception:
                pass
        raise RuntimeError(f"Could not open video: {video_path}")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if total_frames <= 0:
        total_frames = 0

    start_t = time.time()

    def progress_update(done: int) -> None:
        if not progress:
            return
        now = time.time()
        elapsed = now - start_t
        if total_frames > 0:
            pct = min(1.0, max(0.0, done / float(total_frames)))
            bar_w = 30
            filled = int(pct * bar_w)
            bar = "#" * filled + "-" * (bar_w - filled)
            spf = elapsed / float(done) if done > 0 else 0.0
            eta_s = int(spf * (total_frames - done)) if spf > 0 else 0
            msg = f"[{bar}] {pct*100:6.2f}%  {done}/{total_frames}  elapsed {int(elapsed)}s  ETA {eta_s}s"
        else:
            # Unknown total: show a simple spinner-ish bar based on done.
            msg = f"[{'#' * (done % 30):<30}]  {done} frames  elapsed {int(elapsed)}s"

        if sys.stderr.isatty():
            sys.stderr.write("\r" + msg)
            sys.stderr.flush()
        else:
            # Avoid carriage-return spam in non-interactive logs.
            if done == 1 or (done % 10) == 0:
                sys.stderr.write(msg + "\n")
                sys.stderr.flush()

    scores: List[float] = []
    try:
        frame_idx = 0
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            frame_idx += 1
            progress_update(frame_idx)
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)

            # We only need the JSON; ignore the rendered pose image.
            with contextlib.redirect_stdout(aux_sink):
                _pose_img, pose_json = model(
                    frame_rgb,
                    detect_resolution=resolution,
                    include_body=include_body,
                    include_hand=include_hand,
                    include_face=include_face,
                    output_type="np",
                    image_and_json=True,
                )
            if isinstance(pose_json, str):
                try:
                    pose_dict = json.loads(pose_json)
                except Exception:
                    pose_dict = {}
            else:
                pose_dict = pose_json if isinstance(pose_json, dict) else {}

            scores.append(_face_visibility_from_openpose_dict(pose_dict))
    finally:
        if progress and sys.stderr.isatty():
            sys.stderr.write("\n")
            sys.stderr.flush()
        cap.release()
        if aux_sink is not sys.stderr:
            try:
                aux_sink.close()
            except Exception:
                pass

    return scores


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        description="Analyze a video and output per-frame face visibility scores as JSON array."
    )
    p.add_argument("video", help="Path to input video")
    p.add_argument(
        "--format",
        choices=("json", "lines"),
        default="json",
        help="Output format: json (array) or lines (one float per line)",
    )
    p.add_argument(
        "--progress",
        action="store_true",
        help="Show a text progress bar on stderr while processing frames",
    )
    p.add_argument(
        "--no-progress",
        action="store_true",
        help="Disable progress output (useful for clean logs)",
    )
    p.add_argument(
        "--aux-logs",
        choices=("ignore", "stderr"),
        default="ignore",
        help="Where to send noisy auxiliary prints from pose detector (default: ignore)",
    )
    p.add_argument("--resolution", type=int, default=512)
    p.add_argument("--bbox-detector", default="yolox_l.onnx")
    p.add_argument("--pose-estimator", default="dw-ll_ucoco_384_bs5.torchscript.pt")
    args = p.parse_args(argv)

    if args.no_progress:
        progress = False
    elif args.progress:
        progress = True
    else:
        progress = bool(getattr(sys.stderr, "isatty", lambda: False)())

    try:
        scores = analyze_video(
            args.video,
            resolution=args.resolution,
            bbox_detector=args.bbox_detector,
            pose_estimator=args.pose_estimator,
            progress=progress,
            aux_logs=args.aux_logs,
        )
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if args.format == "lines":
        sys.stdout.write("\n".join(f"{v:.6f}" for v in scores))
        sys.stdout.write("\n")
    else:
        sys.stdout.write(json.dumps(scores))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
