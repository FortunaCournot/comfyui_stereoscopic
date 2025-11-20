#!/usr/bin/env python3
"""
create_synthetic_dataset.py

Usage (example - use shell script to generate call):
export COMFYUIHOST=127.0.0.1
export COMFYUIPORT=8188
python3 create_synthetic_dataset.py \
  --workflow "Create_Synthetic_Testdata_API.json" \
  --tests 10 \
  --prompt_text "a robot with glowing blue eyes in dramatic cinematic lighting." \
  --width 1280 --height 720 \
  --iterations 4 --target_length 17 \
  --startvalue 0.0 --endvalue 1.0 \
  --steps 20 --cfg 4.0 \
  --fps 16.0 --output_dir output_dataset
"""
from __future__ import annotations
import argparse
import sys
import json
import os
import random
import time
import uuid
import shutil
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, List

import requests
from tqdm import tqdm
from PIL import Image

# ---------------------------
# Fixed Node IDs (your workflow)
# ---------------------------
NODE_PROMPT          = 20
NODE_NEGATIVE_PROMPT = 21
NODE_SEED            = 24
NODE_STEPS           = 25
NODE_CFG             = 3
NODE_VARIATION       = 28
NODE_WIDTH           = 23
NODE_HEIGHT          = 4
NODE_FILENAME        = 30

# ---------------------------
# Timeouts / retries / commands
# ---------------------------
QUEUE_POLL_INTERVAL = 0.5
HISTORY_POLL_INTERVAL = 1.0
HISTORY_POLL_TIMEOUT = 60 * 10  # wait up to 10 minutes for a frame (per-frame)
DOWNLOAD_RETRIES = 3
DOWNLOAD_TIMEOUT = 120  # per request
FFMPEG_CMD = "ffmpeg"
EXIFTOOL_CMD = "exiftool"

# Required: this exact function body must be used to queue prompts
def queue_prompt(prompt):
    response = requests.post("http://" + os.environ["COMFYUIHOST"] + ":" + os.environ["COMFYUIPORT"] + "/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)
        return None
    
    # Get the prompt_id
    prompt_id = response.json()['prompt_id']
    #print(prompt_id)
    return prompt_id
        

# ---------------------------
# Argparse with friendly errors
# ---------------------------
class FriendlyArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write(f"\nERROR: {message}\n\n")
        self.print_help()
        sys.exit(2)

def parse_args():
    parser = FriendlyArgumentParser(
        description="Create synthetic dataset via per-frame queueing to ComfyUI."
    )

    # required
    parser.add_argument("--workflow", help="Path to ComfyUI workflow JSON")
    parser.add_argument("--tests", type=int, help="Number of test videos to create")
    parser.add_argument("--prompt_text", help="Prompt text (can be multiline)")

    # optional
    parser.add_argument("--negative_prompt_text", default="Vibrant colors, overexposure, static, blurred details, subtitles, style, artwork, painting, still image, overall graying, worst quality, low quality, JPEG compression residue, ugly, mutilated, extra fingers, poorly drawn hands, poorly drawn faces, deformed, disfigured, malformed limbs, fused fingers, still image, cluttered background, three legs, crowded background, walking backwards. text, watermark.", help="Negative prompt (optional, multiline)")
    parser.add_argument("--iterations", type=int, default=4, help="Number of generated frames per test (real iterations)")
    parser.add_argument("--target_length", type=int, default=17, help="Final length of video in frames (>= iterations), default 17")
    parser.add_argument("--startvalue", type=float, default=0.0, help="Start value for variation")
    parser.add_argument("--endvalue", type=float, default=1.0, help="End value for variation")
    parser.add_argument("--steps", type=int, default=20, help="Sampler steps injected")
    parser.add_argument("--cfg", type=float, default=4.0, help="CFG scale injected")
    parser.add_argument("--width", type=int, default=720, help="Render width (int)")
    parser.add_argument("--height", type=int, default=1280, help="Render height (int)")
    parser.add_argument("--fps", type=float, default=16.0, help="FPS for the output video")
    parser.add_argument("--codec", default="libx264", help="ffmpeg codec")
    parser.add_argument("--output_dir", default="./output/vr/tasks/forwarder", help="Directory to store videos (frames are temporary)")

    args = parser.parse_args()

    # no-args => help
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    missing = [x for x in ("workflow", "tests", "prompt_text") if getattr(args, x) is None]
    if missing:
        parser.error(f"Missing required arguments: {', '.join(missing)}")

    if args.target_length < args.iterations:
        parser.error("--target_length must be >= --iterations")

    if args.width is None or args.height is None:
        parser.error("--width and --height are required and must be integers")

    return args

# ---------------------------
# Comfy helpers: base URL, queue/history polling
# ---------------------------
def comfy_base_url() -> str:
    host = os.environ.get("COMFYUIHOST")
    port = os.environ.get("COMFYUIPORT")
    if not host or not port:
        raise EnvironmentError("COMFYUIHOST and COMFYUIPORT must be set")
    return f"http://{host}:{port}"

def find_prompt_id_by_runid(run_id: str, timeout: float = 30.0) -> Optional[str]:
    base = comfy_base_url()
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{base}/queue", timeout=5)
            if r.status_code == 200:
                data = r.json()
                items = []
                if isinstance(data, dict):
                    for k in ("queue_pending","queue_running","queue_finished","queue"):
                        part = data.get(k)
                        if isinstance(part, list):
                            items.extend(part)
                elif isinstance(data, list):
                    items = data
                for item in items:
                    try:
                        text = json.dumps(item)
                    except Exception:
                        text = str(item)
                    if run_id in text:
                        # attempt to extract id
                        if isinstance(item, dict):
                            for key in ("prompt_id","id","job_id"):
                                if key in item:
                                    return str(item[key])
                        return None
        except Exception:
            pass
        time.sleep(QUEUE_POLL_INTERVAL)
    return None

def poll_history_until_complete(prompt_id: str, timeout: float = HISTORY_POLL_TIMEOUT) -> Dict[str, Any]:
    base = comfy_base_url()
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{base}/history/{prompt_id}", timeout=10)
            if r.status_code == 200:
                data = r.json()
                entry = data.get(prompt_id, data) # if isinstance(data, dict) else data
                #print("Navigate to list of image outputs...", entry, flush=True)
                #if isinstance(entry, dict):
                status = entry.get("status" ,entry)
                status = status.get("status_str","").lower()
                #print("status", status, flush=True)
                if status in ("done","finished","completed","success"):
                    #print("POLL DONE", status, flush=True)
                    return entry
                # also accept outputs/images present
                #print("outputs", entry.get("outputs"), flush=True)
                #print("images", entry.get("images"), flush=True)
                #if entry.get("outputs") or entry.get("images"):
                #    return entry
        except Exception:
            print("Exception", flush=True)
            pass
        time.sleep(HISTORY_POLL_INTERVAL)
    raise TimeoutError(f"Timeout waiting for prompt {prompt_id} completion")

def extract_filenames_from_history(entry: Dict[str, Any]) -> List[str]:
    #print("---- extract_filenames_from_history", flush=True)
    filenames: List[str] = []
    #if not isinstance(entry, dict):
    #    return filenames
    #if "outputs" in entry and isinstance(entry["outputs"], dict):
    #print("outputs", entry.get("outputs"), flush=True)
    for node_values in entry["outputs"].values():
        #print("node_values", node_values, flush=True)
        if isinstance(node_values, list):
            for v in node_values:
                if isinstance(v, dict) and "filename" in v:
                    filenames.append(v["filename"])
    #if "images" in entry and isinstance(entry["images"], list):
    #    for img in entry["images"]:
    #        if isinstance(img, dict) and "filename" in img:
    #            filenames.append(img["filename"])
    #        elif isinstance(img, str) and img.lower().endswith(".png"):
    #            filenames.append(img)
    # fallback
    s = json.dumps(entry)
    for part in s.split('"'):
        if part.lower().endswith(".png") and part not in filenames:
            filenames.append(part)
    return filenames

# ---------------------------
# Image download / resize / video assembly / metadata
# ---------------------------
def download_image_from_comfy(filename: str, dest: Path):
    base = comfy_base_url()
    url = f"{base}/view?filename={requests.utils.requote_uri(filename)}"
    last_err = None
    for attempt in range(1, DOWNLOAD_RETRIES+1):
        try:
            with requests.get(url, stream=True, timeout=DOWNLOAD_TIMEOUT) as r:
                if r.status_code != 200:
                    last_err = RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
                else:
                    with dest.open("wb") as f:
                        for chunk in r.iter_content(8192):
                            if chunk:
                                f.write(chunk)
                    return
        except Exception as e:
            last_err = e
        time.sleep(0.5 * attempt)
    raise RuntimeError(f"Failed to download {filename}: {last_err}")

def resize_image_inplace(path: Path, width: int, height: int):
    try:
        img = Image.open(path).convert("RGBA")
        if img.size != (width, height):
            img = img.resize((width, height), Image.LANCZOS)
            img.save(path, "PNG")
    finally:
        try:
            img.close()
        except Exception:
            pass

def assemble_video_ffmpeg(frames_dir: Path, prefix: str, total_frames: int, fps: float, width: int, height: int, out_video: Path):
    if shutil.which(FFMPEG_CMD) is None:
        raise RuntimeError("ffmpeg not found in PATH")
    sample = next(frames_dir.glob(f"{prefix}_frame_*.png"), None)
    if sample is None:
        raise RuntimeError("No frames found to assemble into video")
    pad = sample.stem.rsplit("_",1)[-1]
    padw = len(pad)
    pattern = f"{prefix}_frame_%0{padw}d.png"
    temp = out_video.with_suffix(".tmp.mp4")
    cmd = [
        FFMPEG_CMD, "-y",
        "-framerate", str(fps),
        "-start_number", "0",
        "-i", str(frames_dir / pattern),
        "-frames:v", str(total_frames),
        "-s", f"{width}x{height}",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        str(temp)
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {proc.stderr}")
    temp.replace(out_video)

def embed_metadata_exiftool(video_path: Path, meta_str: str):
    if shutil.which(EXIFTOOL_CMD) is None:
        print("[INFO] exiftool not found; skipping metadata embedding")
        return
    cmd = [EXIFTOOL_CMD, f"-comment={meta_str}", f"-XMP-exif:UserComment={meta_str}", "-overwrite_original", str(video_path)]
    subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# ---------------------------
# Workflow helpers: find node, set primitive value (multiline safe)
# ---------------------------
def find_node_by_id(workflow: Dict[str, Any], node_id: int) -> Optional[Dict[str, Any]]:
    # workflows may either have top-level 'nodes' or nested under 'workflow' key
    if str(node_id) in workflow:
        return workflow[str(node_id)]
    else:
        #print("Error: Can't find node", node_id, flush=True)
        return None

def set_primitive_value(node: Dict[str, Any], value):
    """Set various common primitive storage places used in different ComfyUI exports."""
    if node is None:
        return
    try:
        node["inputs"]["value"] = value
        #print("Set value for node:", value, flush=True)
    except:
        print("Error: Can't set value for node", flush=True)
    
# ---------------------------
# Variation computation
# ---------------------------
def compute_variation(i: int, start: float, end: float, iterations: int) -> float:
    if iterations <= 1:
        return start
    step = (end - start) / (iterations - 1)
    return start + i * step

# ---------------------------
# Per-frame orchestration for a single test (video)
# ---------------------------
def run_one_test_per_frame(args, workflow_template: Dict[str, Any], test_index: int):
    out_root = Path(args.output_dir)
    test_dir = out_root / f"test_{test_index:04d}"
    test_dir.mkdir(parents=True, exist_ok=True)

    # deep copy workflow template to not mutate the original file
    wf_template = json.loads(json.dumps(workflow_template))

    # generate seed for this test (same for all frames)
    test_seed = random.randint(1, 2**31 - 1)
    prefix_base = f"test{test_index:04d}_seed{test_seed}"

    downloaded_frames: List[Path] = []

    for i in range(args.iterations):
        # compute variation for this frame
        variation_value = compute_variation(i, args.startvalue, args.endvalue, args.iterations)

        # copy and inject for this frame
        wf = json.loads(json.dumps(wf_template))

        # inject constants
        mapping = {
            NODE_PROMPT: args.prompt_text,
            NODE_NEGATIVE_PROMPT: args.negative_prompt_text,
            NODE_SEED: test_seed,
            NODE_STEPS: args.steps,
            NODE_CFG: args.cfg,
            NODE_WIDTH: args.width,
            NODE_HEIGHT: args.height
        }
        for nid, val in mapping.items():
            node = find_node_by_id(wf, nid)
            if node:
                set_primitive_value(node, val)
            else:
                print(f"[WARN] Node {nid} not found in workflow; skipping injection")


        # set variation per-frame
        var_node = find_node_by_id(wf, NODE_VARIATION)
        if var_node:
            set_primitive_value(var_node, float(variation_value))
        else:
            print(f"[WARN] Variation node {NODE_VARIATION} not found; continuing without it")

        # set SaveImage filename prefix to a unique name so we can find result
        frame_prefix = f"{prefix_base}_frame_{i:03d}"
        save_node = find_node_by_id(wf, NODE_FILENAME)
        if save_node:
            set_primitive_value(save_node, frame_prefix)
        else:
            print(f"[WARN] SaveImage node {NODE_FILENAME} not found; outputs may be in history but filename matching could fail")

        # attach a run_id for later lookup
        run_id = str(uuid.uuid4())
        #wf.setdefault("meta", {})["run_id"] = run_id

        # queue the prompt (user-specified function)
        prompt_id = queue_prompt(wf)

        # try to find prompt_id from queue, then poll history
        #prompt_id = find_prompt_id_by_runid(run_id, timeout=30.0)
        if prompt_id is None:
            # fallback: try to find via history scanning
            # small pause
            time.sleep(0.5)
            # check history eventually via poll_history_until_complete with run_id not prompt_id
            # We'll try to scan /history in poll_history_until_complete if prompt_id is None by using run_id
            # but to keep code simple, we call poll_history_until_complete only if prompt_id known
            # otherwise we try to scan /history directly for run_id
            # do a small manual scan loop:
            found = None
            base = comfy_base_url()
            deadline = time.time() + 30.0
            while time.time() < deadline and found is None:
                try:
                    r = requests.get(f"{base}/history", timeout=5)
                    if r.status_code == 200:
                        data = r.json()
                        # data may be list or dict
                        if isinstance(data, dict):
                            for k, v in data.items():
                                if run_id in json.dumps(v):
                                    found = str(k)
                                    break
                        elif isinstance(data, list):
                            for entry in data:
                                if run_id in json.dumps(entry):
                                    if isinstance(entry, dict) and "id" in entry:
                                        found = str(entry["id"])
                                        break
                except Exception:
                    pass
                time.sleep(1.0)
            if found is None:
                raise RuntimeError("Could not find queued job (prompt_id) for run_id " + run_id)
            prompt_id = found

        # poll history until completion for this prompt_id
        #print("poll history until completion...", flush=True)
        entry = poll_history_until_complete(prompt_id, timeout=HISTORY_POLL_TIMEOUT)

        # collect filenames and pick the one that matches our prefix
        filenames = extract_filenames_from_history(entry)
        matched = [f for f in filenames if frame_prefix in f]
        if not matched:
            # try any png returned (fallback)
            matched = [f for f in filenames if f.lower().endswith(".png")]
        if not matched:
            raise RuntimeError(f"No PNG output found for frame {i} (run_id {run_id})")

        # pick first matched
        remote_name = matched[0]

        # download and resize, save as our canonical filename
        local_path = test_dir / f"{frame_prefix}.png"
        download_image_from_comfy(remote_name, local_path)
        resize_image_inplace(local_path, args.width, args.height)
        downloaded_frames.append(local_path)

        # small throttle to avoid overloading ComfyUI
        time.sleep(0.05)

    # If fewer frames than iterations (shouldn't happen), pad
    if len(downloaded_frames) < args.iterations:
        last = downloaded_frames[-1]
        for idx in range(len(downloaded_frames), args.iterations):
            dst = test_dir / f"{prefix_base}_frame_{idx:03d}.png"
            shutil.copy2(last, dst)
            downloaded_frames.append(dst)

    # Pad to target_length by duplicating last logical frame (iteration-1)
    last_logical = test_dir / f"{prefix_base}_frame_{args.iterations-1:03d}.png"
    if not Path(last_logical).exists():
        last_logical = downloaded_frames[-1]
    existing = len(list(test_dir.glob(f"{prefix_base}_frame_*.png")))
    for idx in range(existing, args.target_length):
        dst = test_dir / f"{prefix_base}_frame_{idx:03d}.png"
        shutil.copy2(last_logical, dst)

    # assemble video
    out_video = Path(args.output_dir) / f"{prefix_base}.mp4"
    assemble_video_ffmpeg(test_dir, prefix_base, args.target_length, args.fps, args.width, args.height, out_video)

    # embed metadata
    meta_str = f"test_index={test_index}, seed={test_seed}, workflow={Path(args.workflow).name}, cfg={args.cfg}, prompt={args.prompt_text}"
    embed_metadata_exiftool(out_video, meta_str)

    # cleanup frames
    for f in test_dir.glob("*.png"):
        try:
            f.unlink()
        except Exception:
            pass
    try:
        test_dir.rmdir()
    except Exception:
        pass

    #print(f"[INFO] Test {test_index} finished: {out_video}")

# ---------------------------
# Main
# ---------------------------
def main():
    args = parse_args()

    # load workflow template
    wf_path = Path(args.workflow)
    if not wf_path.exists():
        print("[ERROR] workflow JSON not found:", wf_path)
        sys.exit(2)
    with wf_path.open("r", encoding="utf-8") as f:
        workflow_template = json.load(f)

    # environment checks
    if not os.environ.get("COMFYUIHOST") or not os.environ.get("COMFYUIPORT"):
        print("[ERROR] Please set COMFYUIHOST and COMFYUIPORT environment variables")
        sys.exit(2)

    if shutil.which(FFMPEG_CMD) is None:
        print("[ERROR] ffmpeg not found in PATH")
        sys.exit(2)

    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"[INFO] Starting generation: tests={args.tests}, iterations={args.iterations}, target_length={args.target_length}")
    for t in tqdm(range(args.tests), desc="Tests", unit="test"):
        try:
            run_one_test_per_frame(args, workflow_template, t)
        except Exception as e:
            print(f"[ERROR] Test {t} failed: {e}")
            # continue with next test
            continue

    print("[INFO] All tests processed.")

if __name__ == "__main__":
    main()
