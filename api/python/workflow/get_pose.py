#!/usr/bin/env python
"""Compute per-frame head/face visibility scores for a video.

Copyright (c) 2026 Fortuna Cournot. MIT License. www.3d-gallery.org

This script is designed for the VrWeAre/ComfyUI pipeline and is typically called
from the bash workflow (e.g. detect_face_appearance). It runs inside a ComfyUI
installation that also contains:

    - custom_nodes/comfyui_controlnet_aux

It uses that node pack's DWPose implementation to estimate pose + face keypoints
and outputs *one numeric score per frame*.

The central design constraints are:
    - stdout must stay machine-readable (scores only)
    - progress/log output must go to stderr (or be suppressed)
    - Windows/PowerShell should work reliably (prefer --out-file over shell redirection)

---------------------------------
Output formats
---------------------------------
By default the script prints a JSON array of floats to stdout.

    --format json
            Example stdout: [0.0, 0.25, 1.0, ...]

    --format lines
            Example stdout:
                    0.000000
                    0.250000
                    1.000000

If you specify --out-file, nothing is written to stdout; the file is written
atomically via a temporary file + rename.

---------------------------------
What the score means
---------------------------------
All metrics ultimately produce a value in [0.0, 1.0] where:

    - 1.0  means "face/head is clearly visible / frontal-ish"
    - 0.0  means "no face" or "fully turned away" depending on metric

The default workflow metric is:

    --visibility-metric combined_min

which is:
    min(pose_yaw_visibility, pose_head_geom_visibility)

This makes the score conservative: it only becomes high when both the yaw-based
head visibility AND the pose-geometry sanity checks look plausible.

---------------------------------
Metrics ("--visibility-metric")
---------------------------------
Available values:

    combined_min (default)
            Conservative metric intended for chunk-boundary decisions.
            Computes:
                min( pose_yaw , pose_head_geom )

    pose_yaw
            Head visibility derived from a head-yaw estimate, then mapped to a score:
                visibility = max(0, 1 - |yaw_deg|/90)

            How yaw is estimated (2D heuristic, not true 3D):
                - Uses the DWPose "head vectors" (eye -> ear) from body keypoints.
                - Computes confidence-weighted left/right vector lengths and an
                    asymmetry measure.
                - Applies a small deadzone to treat minor asymmetry as "frontal".
                - Computes yaw sign relative to the person's body left-right axis
                    (shoulders, fallback hips). This avoids relying on image axes and is
                    robust for rotated / lying / upside-down subjects.

            Important: pose_yaw is *camera-view* yaw (relative to the camera), not a
            head-vs-torso relative yaw angle.

    pose_head
            Simple presence-based head visibility from body pose keypoints.
            Counts nose + both eyes confidence above --conf-threshold.

    pose_head_geom
            Like pose_head, but adds geometry sanity checks:
                - requires plausible eye-distance / shoulder-distance ratio
                - treats near-origin (0,0) points as missing

    face_landmarks
            Face visibility based on face landmark keypoint *scores*.

            Notes:
                - This code intentionally avoids the controlnet_aux JSON encoder for
                    scoring, because that encoder collapses scores into 0/1.
                - Uses a two-threshold scheme:
                        * presence gate via --score-threshold
                        * gradation via --count-threshold

---------------------------------
Primary-person selection
---------------------------------
Frames can contain multiple people. We pick one "primary" person first, then
compute the visibility score for that person.

    --primary-person body (default)
            Selects the person with the largest body bbox (pose_keypoints_2d).

    --primary-person face
            Selects the person with the largest face bbox (face_keypoints_2d).

---------------------------------
Thresholds and tuning
---------------------------------
    --conf-threshold FLOAT
            Used by pose_head / pose_head_geom and by yaw helpers to decide if a body
            keypoint is present. Default: 0.1

    --eye-ratio-min FLOAT
            Used by pose_head_geom: minimum (eye distance)/(shoulder distance).
            Default: 0.12

    --score-threshold FLOAT
            Used by metrics that gate on face presence (pose_yaw, face_landmarks,
            combined_min). If the strongest valid face keypoint score is <= this value,
            the frame is treated as "no face" => score 0.0. Default: 0.6

    --count-threshold FLOAT
            Used only by face_landmarks/combined_min's face-landmark portion when that
            path is active: counts face keypoints with score > count_threshold.
            Default: 0.1

---------------------------------
Progress / logs
---------------------------------
    --progress
            Prints a progress bar to stderr.

    --no-progress
            Disables progress output.

    --aux-logs ignore|stderr
            Where to send noisy prints from the pose detector.
            Default: ignore (suppressed).

---------------------------------
Model parameters
---------------------------------
These options select which DWPose detector/estimator weights to load:

    --resolution INT
    --bbox-detector NAME    (e.g. yolox_l.onnx or None)
    --pose-estimator NAME   (e.g. dw-ll_ucoco_384_bs5.torchscript.pt)

The defaults match the workflow's expected setup.

---------------------------------
Usage examples
---------------------------------
Git-Bash (recommended, writes file atomically):

        VID="/c/Users/User/Downloads/fullface.mp4"
        PY="/e/SD/vrweare/ComfyUI_windows_portable/python_embeded/python.exe"
        SCRIPT="/e/SD/vrweare/ComfyUI_windows_portable/ComfyUI/custom_nodes/comfyui_stereoscopic/api/python/workflow/get_pose.py"
        OUT="$(cygpath -m "${TEMP:-/tmp}")/face_visibility.txt"

        "$PY" "$SCRIPT" \
            --format lines \
            --primary-person body \
            --visibility-metric combined_min \
            --conf-threshold 0.1 \
            --score-threshold 0.6 \
            --eye-ratio-min 0.12 \
            --no-progress \
            --out-file "$OUT" \
            "$VID"

PowerShell (also prefer --out-file):

        $py = 'e:\\SD\\vrweare\\ComfyUI_windows_portable\\python_embeded\\python.exe'
        $script = 'e:\\SD\\vrweare\\ComfyUI_windows_portable\\ComfyUI\\custom_nodes\\comfyui_stereoscopic\\api\\python\\workflow\\get_pose.py'
        $vid = 'C:\\Users\\User\\Downloads\\fullface.mp4'
        $out = Join-Path $env:TEMP 'face_visibility.txt'

        & $py $script --format lines --visibility-metric combined_min --out-file $out $vid
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

    NOTE: When running through comfyui_controlnet_aux DWPose, the *raw* model
    outputs keypoint scores in [0..1]. If you go through its JSON encoder,
    those scores are reduced to 1.0/0.0 and are not useful for filtering.

    Prefer `_face_visibility_from_openpose_dict_threshold(..., score_threshold)`
    when the input confidence values are real scores.
    """

    return _face_visibility_from_openpose_dict_threshold(openpose_dict, score_threshold=0.0)


def _face_visibility_from_openpose_dict_threshold(
    openpose_dict: Dict[str, Any],
    score_threshold: float = 0.6,
    count_threshold: float = 0.1,
) -> float:
    """Face visibility with score thresholds.

    Two-threshold scheme:
    - Presence gate: if the strongest valid face keypoint score is <= score_threshold,
      treat the frame as "no face" => 0.0 (suppresses false positives).
    - If present, compute gradation as:
        (# face keypoints with score > count_threshold) / (total face keypoints)
      This recovers a smooth-ish visibility signal instead of mostly 0/1.
    """

    people = openpose_dict.get("people") or []
    best_vis = 0.0
    best_area = -1.0

    # DWPose draw_facepose() ignores points when x<=eps or y<=eps (eps=0.01).
    # Treat near-origin points as missing.
    xy_eps = 1e-6

    for person in people:
        face = person.get("face_keypoints_2d")
        if not face or not isinstance(face, list):
            continue
        confs = face[2::3]
        if not confs:
            continue

        total = len(confs)
        visible = 0
        max_score = 0.0
        xs: List[float] = []
        ys: List[float] = []
        for i in range(0, len(face) - 2, 3):
            c = face[i + 2]
            if not isinstance(c, (int, float)):
                continue
            x = face[i]
            y = face[i + 1]
            if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                continue
            xf = float(x)
            yf = float(y)
            # Treat near-origin points as missing, even if c==1.0.
            if (abs(xf) + abs(yf)) <= xy_eps:
                continue
            cf = float(c)
            if cf > max_score:
                max_score = cf
            if cf > count_threshold:
                visible += 1
            xs.append(xf)
            ys.append(yf)

        # Strict "face present" gate.
        if max_score <= score_threshold:
            continue

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


def _keypoints_bbox_area(keypoints: Any, conf_threshold: float = 0.3) -> float:
    """Compute bounding-box area from OpenPose-style keypoints list.

    Expects a flat list: [x0, y0, c0, x1, y1, c1, ...].
    Uses points with confidence > conf_threshold.
    """

    if not keypoints or not isinstance(keypoints, list):
        return 0.0

    xs: List[float] = []
    ys: List[float] = []
    for i in range(0, len(keypoints) - 2, 3):
        c = keypoints[i + 2]
        if not _is_number_string(str(c)):
            continue
        if float(c) <= conf_threshold:
            continue
        x = keypoints[i]
        y = keypoints[i + 1]
        try:
            xs.append(float(x))
            ys.append(float(y))
        except Exception:
            continue

    if len(xs) < 2 or len(ys) < 2:
        return 0.0
    return max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))


def _openpose_kp_conf(keypoints: Any, idx: int) -> float:
    """Return confidence value for OpenPose-style keypoints at index idx."""

    if not keypoints or not isinstance(keypoints, list):
        return 0.0
    base = idx * 3
    if base + 2 >= len(keypoints):
        return 0.0
    c = keypoints[base + 2]
    try:
        return float(c)
    except Exception:
        return 0.0


def _openpose_kp_xyc(keypoints: Any, idx: int) -> Tuple[float, float, float]:
    """Return (x,y,c) for OpenPose-style keypoints at index idx."""

    if not keypoints or not isinstance(keypoints, list):
        return 0.0, 0.0, 0.0
    base = idx * 3
    if base + 2 >= len(keypoints):
        return 0.0, 0.0, 0.0
    try:
        x = float(keypoints[base])
        y = float(keypoints[base + 1])
        c = float(keypoints[base + 2])
        return x, y, c
    except Exception:
        return 0.0, 0.0, 0.0


def _kp_present(x: float, y: float, c: float, conf_threshold: float, xy_epsilon: float = 1e-6) -> bool:
    # Some encoders output (0,0,1) for missing points; treat (0,0) as missing.
    return (c > conf_threshold) and ((abs(x) + abs(y)) > xy_epsilon)


def _unit_vec(dx: float, dy: float) -> Optional[Tuple[float, float]]:
    n = (dx * dx + dy * dy) ** 0.5
    if n <= 1e-6:
        return None
    return dx / n, dy / n


def _body_lr_axis_unit(person: Dict[str, Any], conf_threshold: float = 0.1) -> Optional[Tuple[float, float]]:
    """Return unit left->right body axis in image coordinates.

    Uses shoulders when available, else hips, else None.
    This gives a rotation-invariant reference even if the person is lying or upside-down.
    """

    pose = person.get("pose_keypoints_2d")
    n_points = (len(pose) // 3) if isinstance(pose, list) else 0

    # Shared indices for COCO-18 and BODY-25 for shoulders.
    sh_r_idx, sh_l_idx = 2, 5

    # Hips differ between COCO-18 and BODY-25.
    if n_points >= 25:
        hip_r_idx, hip_l_idx = 9, 12
    else:
        hip_r_idx, hip_l_idx = 8, 11

    rs_x, rs_y, rs_c = _openpose_kp_xyc(pose, sh_r_idx)
    ls_x, ls_y, ls_c = _openpose_kp_xyc(pose, sh_l_idx)
    if _kp_present(rs_x, rs_y, rs_c, conf_threshold) and _kp_present(ls_x, ls_y, ls_c, conf_threshold):
        # Left->Right axis.
        return _unit_vec(rs_x - ls_x, rs_y - ls_y)

    rh_x, rh_y, rh_c = _openpose_kp_xyc(pose, hip_r_idx)
    lh_x, lh_y, lh_c = _openpose_kp_xyc(pose, hip_l_idx)
    if _kp_present(rh_x, rh_y, rh_c, conf_threshold) and _kp_present(lh_x, lh_y, lh_c, conf_threshold):
        return _unit_vec(rh_x - lh_x, rh_y - lh_y)

    return None


def _pose_head_visibility(person: Dict[str, Any], conf_threshold: float = 0.1) -> float:
    """Estimate face/head visibility from body pose keypoints.

    We intentionally use only the *core* head indicators (nose + eyes).
    This avoids false positives where face-landmarks are hallucinated on a
    back-of-head view.


    Indices depend on the pose format:
      - COCO-18: 0 nose, 14 right_eye, 15 left_eye
      - BODY-25: 0 nose, 15 right_eye, 16 left_eye
    """

    pose = person.get("pose_keypoints_2d")
    n_points = (len(pose) // 3) if isinstance(pose, list) else 0
    if n_points >= 25:
        eye_r_idx, eye_l_idx = 15, 16
    else:
        eye_r_idx, eye_l_idx = 14, 15

    nose = _openpose_kp_conf(pose, 0)
    reye = _openpose_kp_conf(pose, eye_r_idx)
    leye = _openpose_kp_conf(pose, eye_l_idx)

    present = 0
    for c in (nose, reye, leye):
        if c > conf_threshold:
            present += 1
    return max(0.0, min(1.0, present / 3.0))


def _pose_head_geom_visibility(
    person: Dict[str, Any],
    conf_threshold: float = 0.1,
    eye_ratio_min: float = 0.12,
) -> float:
    """Pose-based head visibility with a geometry sanity check.

    Motivation: In some cases DWPose may still output head keypoints with
    confidence=1.0 even when a face is not truly visible (e.g. back-of-head).
    This metric requires that the eye distance is plausible relative to the
    shoulder distance, and treats (0,0) keypoints as missing.
    """

    pose = person.get("pose_keypoints_2d")
    n_points = (len(pose) // 3) if isinstance(pose, list) else 0
    if n_points >= 25:
        eye_r_idx, eye_l_idx = 15, 16
        ear_r_idx, ear_l_idx = 17, 18
        sh_r_idx, sh_l_idx = 2, 5
        neck_idx = 1
    else:
        eye_r_idx, eye_l_idx = 14, 15
        ear_r_idx, ear_l_idx = 16, 17
        sh_r_idx, sh_l_idx = 2, 5
        neck_idx = 1

    nose_x, nose_y, nose_c = _openpose_kp_xyc(pose, 0)
    re_x, re_y, re_c = _openpose_kp_xyc(pose, eye_r_idx)
    le_x, le_y, le_c = _openpose_kp_xyc(pose, eye_l_idx)
    re_ear_x, re_ear_y, re_ear_c = _openpose_kp_xyc(pose, ear_r_idx)
    le_ear_x, le_ear_y, le_ear_c = _openpose_kp_xyc(pose, ear_l_idx)
    neck_x, neck_y, neck_c = _openpose_kp_xyc(pose, neck_idx)
    rs_x, rs_y, rs_c = _openpose_kp_xyc(pose, sh_r_idx)
    ls_x, ls_y, ls_c = _openpose_kp_xyc(pose, sh_l_idx)

    nose_ok = _kp_present(nose_x, nose_y, nose_c, conf_threshold)
    re_ok = _kp_present(re_x, re_y, re_c, conf_threshold)
    le_ok = _kp_present(le_x, le_y, le_c, conf_threshold)

    # Base visibility from presence.
    present = int(nose_ok) + int(re_ok) + int(le_ok)
    base_vis = max(0.0, min(1.0, present / 3.0))
    if base_vis <= 0.0:
        return 0.0

    # Geometry sanity check (requires both eyes and both shoulders).
    rs_ok = _kp_present(rs_x, rs_y, rs_c, conf_threshold)
    ls_ok = _kp_present(ls_x, ls_y, ls_c, conf_threshold)
    if re_ok and le_ok and rs_ok and ls_ok:
        eye_dx = re_x - le_x
        eye_dy = re_y - le_y
        sh_dx = rs_x - ls_x
        sh_dy = rs_y - ls_y
        eye_dist = (eye_dx * eye_dx + eye_dy * eye_dy) ** 0.5
        sh_dist = (sh_dx * sh_dx + sh_dy * sh_dy) ** 0.5
        if sh_dist > 1e-6:
            ratio = eye_dist / sh_dist
            if ratio < eye_ratio_min:
                return 0.0

            # Degeneracy checks using the same head-limb connections DWPose draws
            # (see comfyui_controlnet_aux dwpose/util.py limbSeq: neck->eyes, eyes->ears).
            # On side/back/no-face views these vectors often collapse/overlap.
            neck_ok = _kp_present(neck_x, neck_y, neck_c, conf_threshold)
            re_ear_ok = _kp_present(re_ear_x, re_ear_y, re_ear_c, conf_threshold)
            le_ear_ok = _kp_present(le_ear_x, le_ear_y, le_ear_c, conf_threshold)

            # Minimum lengths as a fraction of shoulder width.
            min_neck_eye = 0.05 * sh_dist
            min_eye_ear = 0.02 * sh_dist

            if neck_ok:
                drn = ((re_x - neck_x) ** 2 + (re_y - neck_y) ** 2) ** 0.5
                dln = ((le_x - neck_x) ** 2 + (le_y - neck_y) ** 2) ** 0.5
                if drn < min_neck_eye and dln < min_neck_eye:
                    return 0.0

            if re_ear_ok:
                dre = ((re_x - re_ear_x) ** 2 + (re_y - re_ear_y) ** 2) ** 0.5
                if dre < min_eye_ear:
                    return 0.0
            if le_ear_ok:
                dle = ((le_x - le_ear_x) ** 2 + (le_y - le_ear_y) ** 2) ** 0.5
                if dle < min_eye_ear:
                    return 0.0

    return base_vis


def _face_max_valid_score_for_person(person: Dict[str, Any], xy_eps: float = 1e-6) -> float:
    """Return max face keypoint score for a person, ignoring missing near-origin points."""

    face = person.get("face_keypoints_2d")
    if not face or not isinstance(face, list):
        return 0.0
    max_score = 0.0
    for i in range(0, len(face) - 2, 3):
        x = face[i]
        y = face[i + 1]
        c = face[i + 2]
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
            continue
        if (abs(float(x)) + abs(float(y))) <= xy_eps:
            continue
        if not isinstance(c, (int, float)):
            continue
        cf = float(c)
        if cf > max_score:
            max_score = cf
    return max_score


def _pose_head_yaw_degrees_from_vectors(
    person: Dict[str, Any],
    conf_threshold: float = 0.1,
) -> Optional[float]:
    """Estimate head yaw angle in degrees [-90, 90] from body head vectors.

        Primary signal: asymmetry of the DWPose-drawn head vectors (eye -> ear).
        We compute confidence-weighted lengths:
            Lr = ||right_eye - right_ear|| * min(c_right_eye, c_right_ear)
            Ll = ||left_eye  - left_ear || * min(c_left_eye,  c_left_ear)
        Then ratio = min(Lr, Ll) / max(Lr, Ll) in [0..1].

        - Frontal: both sides similar => ratio ~ 1 => yaw ~ 0°
        - Profile/back: one side collapses/missing => ratio ~ 0 => yaw ~ 90°

        This tends to work even when face-landmarks/eyes are hallucinated.
    """

    import math

    pose = person.get("pose_keypoints_2d")
    n_points = (len(pose) // 3) if isinstance(pose, list) else 0
    if n_points >= 25:
        eye_r_idx, eye_l_idx = 15, 16
        ear_r_idx, ear_l_idx = 17, 18
        nose_idx = 0
    else:
        eye_r_idx, eye_l_idx = 14, 15
        ear_r_idx, ear_l_idx = 16, 17
        nose_idx = 0

    re_x, re_y, re_c = _openpose_kp_xyc(pose, eye_r_idx)
    le_x, le_y, le_c = _openpose_kp_xyc(pose, eye_l_idx)
    r_ear_x, r_ear_y, r_ear_c = _openpose_kp_xyc(pose, ear_r_idx)
    l_ear_x, l_ear_y, l_ear_c = _openpose_kp_xyc(pose, ear_l_idx)
    nose_x, nose_y, nose_c = _openpose_kp_xyc(pose, nose_idx)

    re_ok = _kp_present(re_x, re_y, re_c, conf_threshold)
    le_ok = _kp_present(le_x, le_y, le_c, conf_threshold)
    r_ear_ok = _kp_present(r_ear_x, r_ear_y, r_ear_c, conf_threshold)
    l_ear_ok = _kp_present(l_ear_x, l_ear_y, l_ear_c, conf_threshold)

    def dist(ax: float, ay: float, bx: float, by: float) -> float:
        dx = ax - bx
        dy = ay - by
        return (dx * dx + dy * dy) ** 0.5

    lr = 0.0
    if re_ok and r_ear_ok:
        lr = dist(re_x, re_y, r_ear_x, r_ear_y) * max(0.0, min(re_c, r_ear_c))
    ll = 0.0
    if le_ok and l_ear_ok:
        ll = dist(le_x, le_y, l_ear_x, l_ear_y) * max(0.0, min(le_c, l_ear_c))

    s = lr + ll
    if s <= 1e-6:
        return None
    asym = abs(lr - ll) / s
    if asym < 0.0:
        asym = 0.0
    elif asym > 1.0:
        asym = 1.0

    # Small asymmetries are common even for frontal faces (detector noise).
    # Treat a small deadzone as "frontal" (yaw=0), then rescale the remainder.
    asym_deadzone = 0.12
    if asym <= asym_deadzone:
        asym_adj = 0.0
    else:
        asym_adj = (asym - asym_deadzone) / max(1e-6, (1.0 - asym_deadzone))
        if asym_adj < 0.0:
            asym_adj = 0.0
        elif asym_adj > 1.0:
            asym_adj = 1.0

    yaw_mag = 90.0 * asym_adj
    if yaw_mag < 0.0:
        yaw_mag = 0.0
    elif yaw_mag > 90.0:
        yaw_mag = 90.0

    # Sign: project head center offset onto the body left->right axis.
    # This avoids using image X/Y directly, so it's stable even when the person is
    # rotated in the frame (lying / upside-down).
    sign = 1.0
    axis = _body_lr_axis_unit(person, conf_threshold=conf_threshold)
    nose_ok = _kp_present(nose_x, nose_y, nose_c, conf_threshold)
    if axis is not None and nose_ok and re_ok and le_ok:
        ux, uy = axis
        mid_x = 0.5 * (re_x + le_x)
        mid_y = 0.5 * (re_y + le_y)
        off_x = nose_x - mid_x
        off_y = nose_y - mid_y
        proj = off_x * ux + off_y * uy
        if proj < 0.0:
            sign = -1.0
        else:
            sign = 1.0
    else:
        # Fallback: use which side has the larger eye->ear vector (still rotation invariant).
        if lr > ll:
            sign = 1.0
        elif ll > lr:
            sign = -1.0

    yaw = sign * yaw_mag
    if yaw < -90.0:
        yaw = -90.0
    elif yaw > 90.0:
        yaw = 90.0
    return yaw


def _pose_yaw_visibility(
    person: Dict[str, Any],
    conf_threshold: float = 0.1,
    score_threshold: float = 0.6,
) -> float:
    """Visibility based on yaw angle.

    - Gate on face presence using max face keypoint score (suppresses noface/back-head).
    - Estimate yaw in degrees [-90, 90] from head vectors.
    - Map abs(yaw) linearly to visibility: 0° => 1.0, 90° => 0.0.
    """

    if _face_max_valid_score_for_person(person) <= score_threshold:
        return 0.0

    yaw_deg = _pose_head_yaw_degrees_from_vectors(
        person,
        conf_threshold=conf_threshold,
    )
    if yaw_deg is None:
        return 0.0

    a = abs(float(yaw_deg))
    if a >= 90.0:
        return 0.0
    vis = 1.0 - (a / 90.0)
    if vis < 0.0:
        return 0.0
    if vis > 1.0:
        return 1.0
    return vis


def _select_primary_person(
    people: List[Dict[str, Any]],
    strategy: str = "body",
) -> Optional[Dict[str, Any]]:
    """Select the primary person from an OpenPose-style people list.

    strategy:
      - body: largest bbox area from pose_keypoints_2d (overall body)
      - face: largest bbox area from face_keypoints_2d

    Tiebreaker: higher face visibility.
    """

    best: Optional[Dict[str, Any]] = None
    best_area = -1.0
    best_vis = -1.0

    for person in people:
        if not isinstance(person, dict):
            continue
        if strategy == "face":
            area = _keypoints_bbox_area(person.get("face_keypoints_2d"))
        else:
            # Prefer whole-body pose keypoints.
            area = _keypoints_bbox_area(person.get("pose_keypoints_2d"))

            # Fallback: if pose area is missing, consider all keypoints.
            if area <= 0.0:
                area = max(
                    _keypoints_bbox_area(person.get("pose_keypoints_2d")),
                    _keypoints_bbox_area(person.get("face_keypoints_2d")),
                    _keypoints_bbox_area(person.get("hand_left_keypoints_2d")),
                    _keypoints_bbox_area(person.get("hand_right_keypoints_2d")),
                )

        vis = _face_visibility_from_openpose_dict({"people": [person]})

        if area > best_area:
            best = person
            best_area = area
            best_vis = vis
        elif area == best_area and vis > best_vis:
            best = person
            best_vis = vis

    return best


def _pose_results_to_openpose_dict(poses: Any) -> Dict[str, Any]:
    """Convert comfyui_controlnet_aux dwpose PoseResult list to openpose-like dict.

    Important: we preserve keypoint scores (as the 'c' field).
    """

    people: List[Dict[str, Any]] = []

    if not poses or not isinstance(poses, list):
        return {"people": []}

    def flatten_keypoints(kps: Any, limit: Optional[int] = None) -> Optional[List[float]]:
        if not kps or not isinstance(kps, list):
            return None
        if limit is not None:
            kps = kps[:limit]
        out: List[float] = []
        for kp in kps:
            if kp is None:
                out.extend([0.0, 0.0, 0.0])
                continue
            try:
                out.extend([float(kp.x), float(kp.y), float(getattr(kp, "score", 1.0))])
            except Exception:
                out.extend([0.0, 0.0, 0.0])
        return out

    for pose in poses:
        # Body is always present as BodyResult with .keypoints list.
        body_kps = getattr(getattr(pose, "body", None), "keypoints", None)
        face_kps = getattr(pose, "face", None)

        # DWPose provides 68 face points; its helper may append eyes to reach 70.
        # For visibility scoring we only want the actual 68 face points.
        face_flat = flatten_keypoints(face_kps, limit=68)
        body_flat = flatten_keypoints(body_kps)

        people.append(
            {
                "pose_keypoints_2d": body_flat,
                "face_keypoints_2d": face_flat,
            }
        )

    return {"people": people}


def _face_visibility_for_primary_person(
    openpose_dict: Dict[str, Any],
    primary_person: str = "body",
    visibility_metric: str = "pose_head",
    conf_threshold: float = 0.1,
    eye_ratio_min: float = 0.12,
    score_threshold: float = 0.6,
    count_threshold: float = 0.1,
) -> float:
    people = openpose_dict.get("people") or []
    if not isinstance(people, list) or not people:
        return 0.0

    person = _select_primary_person(people, strategy=primary_person)
    if not person:
        return 0.0
    if visibility_metric == "face_landmarks":
        return _face_visibility_from_openpose_dict_threshold(
            {"people": [person]},
            score_threshold=score_threshold,
            count_threshold=count_threshold,
        )
    if visibility_metric == "pose_head_geom":
        return _pose_head_geom_visibility(
            person,
            conf_threshold=conf_threshold,
            eye_ratio_min=eye_ratio_min,
        )
    if visibility_metric == "pose_yaw":
        return _pose_yaw_visibility(
            person,
            conf_threshold=conf_threshold,
            score_threshold=score_threshold,
        )
    if visibility_metric == "combined_min":
        face_v = _pose_yaw_visibility(
            person,
            conf_threshold=conf_threshold,
            score_threshold=score_threshold,
        )
        pose_v = _pose_head_geom_visibility(
            person,
            conf_threshold=conf_threshold,
            eye_ratio_min=eye_ratio_min,
        )
        return min(face_v, pose_v)
    return _pose_head_visibility(person, conf_threshold=conf_threshold)


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
    primary_person: str = "body",
    visibility_metric: str = "pose_head",
    conf_threshold: float = 0.1,
    eye_ratio_min: float = 0.12,
    score_threshold: float = 0.6,
    count_threshold: float = 0.1,
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

    # Ensure we request the keypoints required by the chosen strategy/metric.
    need_body = (primary_person == "body") or (
        visibility_metric in ("pose_head", "pose_head_geom", "pose_yaw", "combined_min")
    )
    include_body_call = bool(include_body or need_body)

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

            # Prefer score-preserving poses instead of binary JSON.
            with contextlib.redirect_stdout(aux_sink):
                poses = model.detect_poses(frame_rgb)

            pose_dict = _pose_results_to_openpose_dict(poses)

            scores.append(
                _face_visibility_for_primary_person(
                    pose_dict,
                    primary_person=primary_person,
                    visibility_metric=visibility_metric,
                    conf_threshold=conf_threshold,
                    eye_ratio_min=eye_ratio_min,
                    score_threshold=score_threshold,
                    count_threshold=count_threshold,
                )
            )
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
        "--out-file",
        default="",
        help="Write output to this file instead of stdout (useful on Windows/PowerShell)",
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
    p.add_argument(
        "--primary-person",
        choices=("body", "face"),
        default="body",
        help="How to choose the primary person per frame before computing face visibility (default: body)",
    )
    p.add_argument(
        "--visibility-metric",
        choices=("combined_min", "pose_yaw", "pose_head_geom", "pose_head", "face_landmarks"),
        default="combined_min",
        help="How to score visibility once the primary person is selected (default: combined_min)",
    )
    p.add_argument(
        "--conf-threshold",
        type=float,
        default=0.1,
        help="Confidence threshold used by pose_head / pose_head_geom metrics (default: 0.1)",
    )
    p.add_argument(
        "--score-threshold",
        type=float,
        default=0.6,
        help="Presence threshold for face_landmarks / combined_min when using pose scores (default: 0.6)",
    )
    p.add_argument(
        "--count-threshold",
        type=float,
        default=0.1,
        help="Count threshold for gradation once present (default: 0.1)",
    )
    p.add_argument(
        "--eye-ratio-min",
        type=float,
        default=0.12,
        help="Minimum eye-distance / shoulder-distance ratio for pose_head_geom (default: 0.12)",
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
            primary_person=args.primary_person,
            visibility_metric=args.visibility_metric,
            conf_threshold=float(args.conf_threshold),
            eye_ratio_min=float(args.eye_ratio_min),
            score_threshold=float(args.score_threshold),
            count_threshold=float(args.count_threshold),
        )
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if args.format == "lines":
        out_text = "\n".join(f"{v:.6f}" for v in scores) + "\n"
    else:
        out_text = json.dumps(scores)

    if args.out_file:
        out_path = os.path.abspath(args.out_file)
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        tmp_path = out_path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(out_text)
        os.replace(tmp_path, out_path)
    else:
        sys.stdout.write(out_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
