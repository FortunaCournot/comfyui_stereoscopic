import subprocess
import sys
import re
import shutil
import os

def get_cuda_version():
    """Detect installed CUDA version using nvidia-smi"""
    try:
        output = subprocess.check_output(["nvidia-smi"], encoding="utf-8")
        match = re.search(r"CUDA Version: (\d+\.\d+)", output)
        if match:
            return match.group(1)
    except Exception:
        return None

def try_install_torch(cuda_ver):
    cu_str = cuda_ver.replace(".", "")
    print(f"Trying to install PyTorch for cu{cu_str}...")
    try:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "-q",
            "torch", "torchvision",
            "--index-url", f"https://download.pytorch.org/whl/cu{cu_str}"
        ])
        return True
    except subprocess.CalledProcessError:
        return False

def install_torch(cuda_ver):
    """Try to install a matching PyTorch wheel for a specific CUDA version."""
    if not cuda_ver:
        print("CUDA not found, installing CPU version...")
        subprocess.check_call([
            sys.executable, "-m", "pip", "install",
            "torch", "torchvision",
            "--index-url", "https://download.pytorch.org/whl/cpu"
        ])
        return

    print(f"Detected CUDA {cuda_ver}")
    ver = float(cuda_ver)
    tried = set()

    while ver >= 10.0:
        ver_str = f"{ver:.1f}"
        if ver_str in tried:
            break
        tried.add(ver_str)
        if try_install_torch(ver_str):
            print(f"Successfully installed for CUDA {ver_str}")
            return
        ver = round(ver - 0.1, 1)

    print("No compatible CUDA wheel found, installing CPU version...")
    subprocess.check_call([
        sys.executable, "-m", "pip", "install",
        "torch", "torchvision",
        "--index-url", "https://download.pytorch.org/whl/cpu"
    ])

def test_torch():
    """Verify that PyTorch is installed and CUDA works."""
    try:
        import torch
        print("\nPyTorch installed!")
        print(f"Version PyTorch: {torch.__version__}")
        if torch.cuda.is_available():
            print(f"CUDA is available: {torch.version.cuda}")
            print(f"GPU: {torch.cuda.get_device_name(0)}")
        else:
            print("CUDA is not available, in use CPU.")
    except ImportError:
        print("\nError: PyTorch is not installed or imported!")
        

def test_ffmpeg():
    """Check if FFmpeg is installed and functional."""
    ffmpeg_path = shutil.which("ffmpeg")
    if ffmpeg_path:
        try:
            result = subprocess.run([ffmpeg_path, "-version"], capture_output=True, text=True)
            if result.returncode == 0:
                print("FFmpeg is installed and working!")
                print(result.stdout.splitlines()[0])
            else:
                print("FFmpeg exists but failed to run.")
                print(result.stderr)
        except Exception as e:
            print(f"Error running FFmpeg: {e}")
    else:
        print(
            "FFmpeg not found.\n\n"
            "On Windows, you can install it via Chocolatey:\n"
            "  choco install ffmpeg\n"
            "More info: https://chocolatey.org/install\n\n"
            "On Ubuntu/Debian:\n"
            "  sudo apt install ffmpeg\n\n"
            "There is also a guide by this user:\n"
            "  https://github.com/aaatipamula/ffmpeg-install"
        )
        
def install_requirements():
    """
    Install packages from requirements.txt located in the same folder as this script.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    req_file = os.path.join(script_dir, "requirements.txt")

    if not os.path.exists(req_file):
        print(f"requirements.txt not found in {script_dir}")
        return

    print(f"Installing packages from {req_file} ...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", req_file])
        print("All packages from requirements.txt installed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Error installing requirements: {e}")

if __name__ == "__main__":
    install_requirements()
    cuda_ver = get_cuda_version()
    install_torch(cuda_ver)
    test_torch()
    test_ffmpeg()

    print("\nSetup complete! You're ready to run the pipeline.")
