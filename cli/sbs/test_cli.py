import importlib
import os
import pkgutil
import shutil
import subprocess
import random
import string
import sys

def check_environment(project_dir: str):

    required_files = [
        "converter.py",
        "depthestimator.py",
        "main.py",
        "monitor.py",
        "pipeline_core.py",
        "presets.json",
        "requirements.txt",
        "sbsutils.py",
    ]

    try:
        # --- check files ---
        for filename in required_files:
            path = os.path.join(project_dir, filename)
            if not os.path.isfile(path):
                return False, f"Файл отсутствует: {filename}"

        # --- check requirements  ---
        req_path = os.path.join(project_dir, "requirements.txt")
        with open(req_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        requirements = []
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            # clear versions
            pkg = line.split("==")[0].split(">=")[0].split("<=")[0].strip()
            if pkg:
                requirements.append(pkg)

        IMPORT_MAP = {
            "opencv-python": "cv2",
            "py-cpuinfo" : "cpuinfo",
            "nvidia-ml-py":"pynvml"
        }

        for pkg in requirements:
            import_name = IMPORT_MAP.get(pkg, pkg)  
            if importlib.util.find_spec(import_name) is None:
                return False, f"Missing dependency: {pkg}"

        return True, None

    except Exception as e:
        return False, f"Environment check error: {e}"


def test_ffmpeg():
    """Check if FFmpeg is installed and functional."""
    ffmpeg_path = shutil.which("ffmpeg")
    if ffmpeg_path:
        try:
            result = subprocess.run([ffmpeg_path, "-version"], capture_output=True, text=True)
            if result.returncode == 0:
                return True, None
            else:
                return False, f"FFmpeg check error: {result.stderr}"
        except Exception as e:
            return False, f"Error running FFmpeg: {e}"
    else:
        message = """FFmpeg not found.

                    On Windows, you can install it via Chocolatey:
                      choco install ffmpeg
                    More info: https://chocolatey.org/install

                    On Ubuntu/Debian:
                      sudo apt install ffmpeg

                    There is also a guide by this user:
                      https://github.com/aaatipamula/ffmpeg-install
                  """
        return False, message


def test_pytorch():

    # --- Try import torch ---
    try:
        import torch
    except Exception as e:
        return False, f"PyTorch import failed: {e}"

    # --- Test CUDA ---
    try:
        if torch.cuda.is_available():
            a = torch.tensor([1.0, 2.0, 3.0], device="cuda")
            b = torch.tensor([4.0, 5.0, 6.0], device="cuda")
            c = a + b 
            _ = c.cpu()  
            return True, None
    except Exception as e:
        cuda_error = str(e)
    else:
        cuda_error = "CUDA not available"

    # --- Test CPU ---
    try:
        a = torch.tensor([1.0, 2.0, 3.0])
        b = torch.tensor([4.0, 5.0, 6.0])
        c = a + b  # simple CPU op
        _ = c.numpy()
        return True, None
    except Exception as e:
        return False, f"CPU test failed: {e} — CUDA error was: {cuda_error}"
        
        
        

def run_cmd(cmd):
    """Run command and return exit code."""
    return subprocess.call(cmd, shell=True)


def gen_random_frame(path, w=256, h=144):
    """Generate random image."""
    frame = (np.random.rand(h, w, 3) * 255).astype('uint8')
    cv2.imwrite(path, frame)


def gen_random_video(path, frames=15, w=256, h=144):
    """Generate test video."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(path, fourcc, 24, (w, h))
    for _ in range(frames):
        frame = (np.random.rand(h, w, 3) * 255).astype('uint8')
        out.write(frame)
    out.release()


def safe_size(path):
    """Return file size or 0."""
    try:
        return os.path.getsize(path)
    except:
        return 0


def test_converter(main_py="main.py"):
    """Full test for all 3 modes."""
   
    # --- prepare temp root ---
    tmp_root = "_tmp_test_" + "".join(random.choice(string.ascii_letters) for _ in range(8))
    os.makedirs(tmp_root)

    try:
        print("Creating test data...")

        # --- test 1: video mode ---
        video_in = os.path.join(tmp_root, "input.mp4")
        video_out = os.path.join(tmp_root, "output_sbs.mp4")
        gen_random_video(video_in)

        # --- test 2: i2i mode ---
        img_in = os.path.join(tmp_root, "image.png")
        img_out = os.path.join(tmp_root, "image_sbs.png")
        gen_random_frame(img_in)

        print("Running converter...")

        # ===== VIDEO MODE =====
        cmd1 = f'''"{sys.executable}" "{main_py}" -i "{video_in}" -o "{video_out}" --preset minimum'''
        if run_cmd(cmd1) != 0:
            return False, "video mode failed"

        if not os.path.isfile(video_out) or safe_size(video_out) < 1000:
            return False, "video output invalid"

        # ===== I2I MODE =====
        cmd3 = f'''"{sys.executable}" "{main_py}" -i "{img_in}" -o "{img_out}" --input-type i2i -m depth-anything/Depth-Anything-V2-Small-hf'''
        if run_cmd(cmd3) != 0:
            return False, "i2i mode failed"

        if not os.path.isfile(img_out) or safe_size(img_out) < 200:
            return False, "i2i output invalid"

        return True, None

    except Exception as e:
        return False, str(e)

    finally:
        # remove temp files
        shutil.rmtree(tmp_root, ignore_errors=True)

if __name__ == "__main__":    
    ok, error = check_environment(os.path.dirname(os.path.abspath(__file__)))
    if not ok:
        print("Environment test FAILED")
        print(error)
        sys.exit(1)  
    print("Environment OK\n")

    ok, error = test_ffmpeg()
    if not ok:
        print("FFmpeg test FAILED")
        print(error)
        sys.exit(1)
    print("FFmpeg OK\n")

    ok, error = test_pytorch()
    if not ok:
        print("PyTorch test FAILED")
        print(error)
        sys.exit(1)
    print("PyTorch OK\n")
    
    import cv2
    import numpy as np

    ok, error = test_converter(os.path.join(os.path.dirname(os.path.abspath(__file__)),"main.py"))
    if not ok:
        print("Converter test FAILED")
        print(error)
        sys.exit(1)
    print("Converter OK\n")

    sys.exit(0)

