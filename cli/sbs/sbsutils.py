import sys , signal , psutil , os , cpuinfo , torch , json , argparse
import numpy as np
from pathlib import Path
from dataclasses import fields
from typing import get_origin, get_args
from types import UnionType

def detect_nvenc_support():
    """
    Returns True if FFmpeg NVENC encoder (h264_nvenc) is both compiled AND usable.
    """
    import subprocess, tempfile, os

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp_out:
        tmp_name = tmp_out.name

    try:
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "color=c=black:s=256x256:d=0.1",
            "-c:v", "h264_nvenc", "-frames:v", "1", tmp_name
        ]
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,   
            timeout=5
        )
        success = result.returncode == 0
    except subprocess.TimeoutExpired:
        print("NVENC test timeout (ffmpeg hung, skipping)")
        success = False
    except Exception:
        success = False
    finally:
        try:
            os.remove(tmp_name)
        except OSError:
            pass

    return success

def force_exit(sig=None, frame=None):
    try:
        parent = psutil.Process(os.getpid())
        for child in parent.children(recursive=True):
            try:
                child.kill()
            except Exception:
                pass
        parent.kill()
    except Exception:
        pass
    sys.exit(1)
    
def load_preset(mode: str, name: str, path: str = "presets.json") -> dict:
    path = Path(path)
    
    if not path.exists():
        raise FileNotFoundError(f"Preset file not found: {path.resolve()}")
    
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(f"Failed to parse {path.name}: {e}")

    try:
        return data[mode][name]
    except KeyError as e:
        raise ValueError(f"Preset '{name}' not found for mode '{mode}' in {path}")
        
def merge_with_preset(args: argparse.Namespace, preset_data: dict, cls_type) -> dict:
    """
    Combines CLI arguments with preset.
    CLI always has priority.
    """
    merged = {}
    args_dict = vars(args)
    
    field_types = {f.name: f.type for f in fields(cls_type)}
    valid_keys = set(field_types.keys())

    alias_map = {
        "input": "video_path",
        "output": "output_path",
        "preprocess": "n_preprocess",
        "processors": "n_processors",
        "savers": "n_savers",
        "feeders": "n_feeders",
        "model": "model_name"
    }

    # start with preset
    for k, v in preset_data.items():
        if k not in valid_keys:
            print(f"Unknown key in preset: '{k}' (ignored)")
            continue

        expected_type = field_types[k]

        # Checking type compatibility
        if get_origin(expected_type) in (list, tuple, dict, UnionType):
            expected_types = get_args(expected_type)
        else:
            expected_types = (expected_type,)

        if not isinstance(v, expected_types):
            print(f"Type mismatch for key '{k}' — expected {expected_types}, got {type(v)}")

        merged[k] = v
        
    # Optional NVENC auto-switch
    if (
        preset_data.get("codec", "").startswith("libx")
        and args_dict.get("codec") is None
        and preset_data.get("input_type", "video") == "video"
    ):
        if detect_nvenc_support():
            merged["codec"] = "h264_nvenc"
            print("NVENC available — using GPU encoder (h264_nvenc).")
        else:
            print(f"Using CPU encoder: {preset_data.get('codec', 'libx264')}")
        
    # overwrite from CLI
    for k, v in args_dict.items():
        if v is None:
            continue
        if k in alias_map and alias_map[k] in valid_keys:
            merged[alias_map[k]] = v
        elif k in valid_keys:
            merged[k] = v

    # Remove any keys not defined in PipelineContext
    merged = {k: v for k, v in merged.items() if k in valid_keys}

    return merged

def get_system_info():
    info = {}

    # CPU
    try:
        cpu = cpuinfo.get_cpu_info()
        info["CPU"] = cpu.get("brand_raw", "Unknown CPU")
        info["Arch"] = cpu.get("arch", "Unknown")
        info["Cores (logical/physical)"] = f"{psutil.cpu_count(logical=True)}/{psutil.cpu_count(logical=False)}"
    except Exception as e:
        info["CPU"] = f"Error: {e}"

    # RAM
    try:
        vm = psutil.virtual_memory()
        info["RAM total"] = f"{vm.total / (1024**3):.1f} GB"
    except Exception:
        info["RAM total"] = "Unknown"

    # GPU (PyTorch)
    if torch.cuda.is_available():
        try:
            gpu_count = torch.cuda.device_count()
            gpus = []
            for i in range(gpu_count):
                name = torch.cuda.get_device_name(i)
                props = torch.cuda.get_device_properties(i)
                mem = props.total_memory / (1024**3)
                gpus.append(f"{i}: {name} ({mem:.1f} GB, CC {props.major}.{props.minor})")
            info["GPU(s)"] = ", ".join(gpus)
        except Exception as e:
            info["GPU(s)"] = f"Error: {e}"
    else:
        info["GPU(s)"] = "None (CPU only)"

    return info

def prepare_batch(images: list[tuple[int, np.ndarray]], depth_maps: list[np.ndarray]) -> tuple[np.ndarray, np.ndarray]:
    """
    Prepares a batch of images and depth maps for processing.
    """

    # get the sort order by indexes
    indices = [idx for idx, _ in images]
    if all(idx is None for idx in indices):
        order = list(range(len(indices)))
    else:
        order = np.argsort(indices).tolist()  # index order in ascending order

    # Сортируем изображения 
    images_sorted = [images[i][1] for i in order]
    depth_sorted = [depth_maps[i] for i in order]

    base_image = np.stack([img.astype(np.float32) / 255.0
    for img in images_sorted
    ], axis=0)  # shape: [B, H, W, 3]

    depth_image = np.stack(depth_sorted, axis=0).astype(np.float32)

    return base_image, depth_image

def validate_config(params, parser=None):
    """
    Universal validation for both dict and argparse.Namespace.
    Skips None values. Raises ValueError or parser.error().
    """

    # If argparse.Namespace is passed, convert to dict
    if isinstance(params, argparse.Namespace):
        params = vars(params)

    input_type = params.get("input_type")
    input_path = params.get("video_path") or params.get("input")
    output_path = params.get("output_path") or params.get("output")
    feeders = params.get("n_feeders") or params.get("feeders")
    savers = params.get("n_savers") or params.get("savers")
    codec = params.get("codec")
    preset = params.get("preset") 
    
    def fail(msg):
        if parser:
            parser.error(msg)
        else:
            raise ValueError(msg)

    if input_type == "video":
        if input_path and not os.path.isfile(input_path):
            fail(f"--input must be a video file when --input-type=video (got {input_path})")
        if savers is not None and savers != 1:
            fail("--savers must be 1 when --input-type=video")
        if feeders is not None and feeders != 1:
            fail("--feeders must be 1 when --input-type=video")
        if output_path and not output_path.lower().endswith((".mp4", ".mkv", ".avi", ".mov")):
            fail("--output must be a video file path (with extension .mp4/.mkv/...)")

    elif input_type == "folder":
        if input_path and not os.path.isdir(input_path):
            fail("--input must be a directory when --input-type=folder")
        if codec is not None:
            print("--codec is ignored in folder mode (images are saved as PNG).")
        if output_path and not os.path.isdir(output_path):
            try:
                os.makedirs(output_path, exist_ok=True)
            except Exception as e:
                fail(f"Failed to create output directory: {e}")

    elif input_type == "i2i":
        if input_path and os.path.isfile(input_path):
            if output_path and os.path.isdir(output_path):
                fail("For single image input (--input=file) you must provide --output as a file, not a folder.")
            if savers is not None and savers != 1:
                fail("--savers must be 1 when --input-type=i2i with single image")
        elif input_path and os.path.isdir(input_path):
            if output_path and not os.path.isdir(output_path):
                try:
                    os.makedirs(output_path, exist_ok=True)
                except Exception as e:
                    fail(f"Failed to create output directory: {e}")
            if savers is not None and savers != 1:
                fail("--savers must be 1 when --input-type=i2i (folder)")
        else:
            fail(f"--input must be a file or directory when --input-type=i2i (got {input_path})")
        if codec:
            fail(f"--codec is only supported for --input-type=video")
        if preset:
            fail(f"Presets are available only for 'video' and 'folder' --input-type.")

    else:
        fail(f"Unknown input type: {input_type}")

# Collect and display runtime statistics for performance and debugging
def debug_report(ctx):
    # stop monitors
    if ctx.debug and ctx.q_mon: ctx.q_mon.stop()
    if ctx.debug and ctx.mem_mon: ctx.mem_mon.stop()

    # report
    if ctx.debug:
        elapsed = ctx.t_end - ctx.t_start if ctx.t_end else 0.0
        total_frames = ctx.result_dict.get("frames", 0)
        fps_eff = (total_frames / elapsed) if elapsed > 0 else 0.0

        print("\n===== Debug Report =====")
        print(f"Release version: {ctx.version}")
        print(f"Input path: {ctx.video_path}")
        print(f"Output: {ctx.output_path}")
        print(f"Mode: {ctx.input_type}")
        print(f"Multimedia fps & resolution: {ctx.fps}  {ctx.W}x{ctx.H}")
        print(f"Frames processed: {total_frames}")
        print(f"Elapsed time: {elapsed:.2f} sec")
        print(f"Effective FPS: {fps_eff:.2f}")

        print("\n--- System Info ---")
        for k, v in get_system_info().items():
            print(f"{k}: {v}")
        
        print("\n--- Settings ---")
        print(f"Batch size: {ctx.batch_size}")
        print(f"feeders threads: {ctx.n_feeders}")
        print(f"Preprocess threads: {ctx.n_preprocess}")
        print(f"Processing threads: {ctx.n_processors}")
        print(f"Savers threads: {ctx.n_savers}")
        print(f"Model: {ctx.model_name}")
        print(f"Codec: {ctx.codec}")
        print(f"Queue sizes: raw={ctx.r_queue}, input={ctx.in_queue}, "
              f"process={ctx.p_queue}, save={ctx.s_queue}")
              
        print("\n--- Converter Settings ---")
        print(f"depth-scale: {ctx.depth_scale}")
        print(f"depth-offset: {ctx.depth_offset}")
        print(f"switch-sides {ctx.switch_sides}")
        print(f"symmetric: {ctx.symetric}")
        print(f"blur-radius: {ctx.blur_radius}")

        print("\n--- Queue stats ---")
        for name, st in ctx.q_mon.stats().items():
            print(f"- {name}: {st}")

        print("\n--- Memory usage ---")
        print(ctx.mem_mon.report())
        print("========================")

        # graphics on request
        try:
            ctx.q_mon.plot(show=True, save_path=None)
            ctx.mem_mon.plot(show=True, save_path=None)
        except Exception as e:
            print(f"[warn] Plot skipped: {e}")
