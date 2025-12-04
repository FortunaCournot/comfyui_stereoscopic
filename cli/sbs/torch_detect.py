import subprocess
import re
import sys

def get_cuda_driver_version():
    try:
        import pynvml
        pynvml.nvmlInit()
        raw = pynvml.nvmlSystemGetCudaDriverVersion_v2()
        pynvml.nvmlShutdown()

        major = raw // 1000
        minor = (raw % 1000) // 10
        return f"{major}.{minor}"
    except Exception:
        pass

    try:
        out = subprocess.check_output(
            ["nvidia-smi"], stderr=subprocess.STDOUT, universal_newlines=True
        )

        match = re.search(r"CUDA Version:\s*([\d.]+)", out)
        if match:
            return match.group(1)

        match = re.search(r"CUDADriverVersion\s*:\s*([\d.]+)", out)
        if match:
            return match.group(1)

    except Exception:
        pass

    return False

def get_compute_capability():
    """Returns compute capability as float (e.g. 7.5) or False."""
    # Try NVML first
    try:
        import pynvml
        pynvml.nvmlInit()
        handle = pynvml.nvmlDeviceGetHandleByIndex(0)
        major, minor = pynvml.nvmlDeviceGetCudaComputeCapability(handle)
        pynvml.nvmlShutdown()
        return float(f"{major}.{minor}")
    except Exception:
        pass

    # Try nvidia-smi
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=compute_cap", "--format=csv,noheader"],
            stderr=subprocess.STDOUT,
            universal_newlines=True
        ).strip()
        return float(out)
    except Exception:
        pass

    return False


def sm_from_cc(cc: float):
    """Convert float compute capability to sm_xx integer."""
    major = int(cc)
    minor = int((cc - major) * 10)
    return major * 10 + minor

def cuda_from_index(idx: str) -> float:
    """
    Convert index 'cu126' → 12.6, 'cu130' → 13.0
    """
    num = idx.replace("cu", "")
    if len(num) == 3:
        return float(f"{num[0]}{num[1]}.{num[2]}")
    if len(num) == 4:  # future-proof
        return float(f"{num[:2]}.{num[2]}")
    return 0.0


def choose_torch(sm: int):
    """
    Select proper PyTorch build based on SM capability.
    Returns: dict with install command or 'cpu'.
    """

    # Torch 2.9.0 + cu126
    if sm >= 50:
        best_fit = {
            "version": "2.9.0+cu126",
            "index": "cu126",
            "min_sm": 50,
            "cmd": f"{sys.executable} -m pip install torch==2.9.0 torchvision==0.24.0 --index-url https://download.pytorch.org/whl/cu126"
        }

    # Torch 2.9.0 + cu128
    if sm >= 70:
        best_fit = {
            "version": "2.9.0+cu128",
            "index": "cu128",
            "min_sm": 70,
            "cmd": f"{sys.executable} -m pip install torch==2.9.0 torchvision==0.24.0  --index-url https://download.pytorch.org/whl/cu128"
        }

    # Torch 2.9.0 + cu130
    if sm >= 75:
        best_fit = {
            "version": "2.9.0+cu130",
            "index": "cu130",
            "min_sm": 75,
            "cmd": f"{sys.executable} -m pip install torch==2.9.0 torchvision==0.24.0  --index-url https://download.pytorch.org/whl/cu130"
        }

    # If GPU too old
    if sm < 50:
        return {"cpu": True}

    return best_fit


def main():
    cc = get_compute_capability()

    if cc is False:
        print("No NVIDIA GPU detected → using CPU.")
        return False

    sm = sm_from_cc(cc)
    print(f"Detected compute capability: {cc} - SM_{sm}")

    torch_choice = choose_torch(sm)

    if "cpu" in torch_choice:
        print("GPU too old → PyTorch CUDA is not supported. Using CPU.")
        return False

    # --- CUDA driver version check ---
    driver_ver = get_cuda_driver_version()
    required_cuda = cuda_from_index(torch_choice["index"])

    print(f"Detected CUDA Runtime version : {driver_ver}")


    if driver_ver:
        drv = float(driver_ver)
        if drv < required_cuda:
            print("\nYour CUDA driver is TOO OLD for this PyTorch build!")
            print(f"  Installed CUDA Runtime: {driver_ver}")
            print(f"  Required CUDA Runtime:  {required_cuda}")
            print("\n→ Please update your NVIDIA driver to a newer version.")
            print("→ Falling back to CPU mode.\n")
            return False
    else:
        print("\nCould not determine CUDA driver version - risky, skipping check.")
        print("  To avoid issues, ensure your NVIDIA driver is up to date.\n")

    print("\nMatching PyTorch build:")
    print(f"  Torch version: {torch_choice['version']}")
    print(f"  Install command:\n    {torch_choice['cmd']}")

    return torch_choice


if __name__ == "__main__":
    main()
