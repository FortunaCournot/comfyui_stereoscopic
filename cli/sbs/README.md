# VR we are! (CLI)

Fast, cross-platform **video → stereoscopic SBS** converter powered by **Depth Anything V2**.
Built for batch work, tuned for GPUs, and designed with a **multi-threaded** pipeline that keeps your CPU, GPU and I/O busy.



## ✨ Features

* **Video → SBS video**, **Folder with frames → SBS images**, **Image → Image (i2i)**
* **Presets** (minimum / balance / max_quality) for speed/quality/VRAM/RAM targets
* **CUDA + NVENC** support (auto-detects and switches when possible)
* **Pipeline parallelism** with queues: feeder → preprocess → GPU → convert → save
* Depth via **Depth Anything V2 (Small/Base/Large)**
* **Debugging**: Queue/Memory Monitor and Summary Report
* Single-file **installer** (`setup_env.py`) to pull PyTorch/FFmpeg deps



## 🔗 Related project (direct "relative")

This CLI grew out of the ComfyUI project:

* **VR we are! (ComfyUI nodes)** – stereoscopic nodes & docs
  GitHub: [https://github.com/FortunaCournot/comfyui_stereoscopic](https://github.com/FortunaCournot/comfyui_stereoscopic)

Huge thanks to **Fortuna** (author of nodes/docs) and the ComfyUI community.

## Installation

> Tested with **Python 3.12**.

1. **Install Python 3.12**
   [https://www.python.org/downloads/](https://www.python.org/downloads/)

2. **Get the sources**

   * Clone the repo: `git clone https://github.com/Iablunoshka/VR-we-are-CLI`
     or unzip a release to a folder.

3. **Create & activate venv**

Creation venv
```bash
python -m venv venv
```
Activating venv *Windows*
```bash
venv\Scripts\activate
```
or *Linux*
```bash
source venv/bin/activate
```

4. **Run the bootstrapper**

```bash
python setup_env.py
```

This will:

* install packages from `requirements.txt`,
* detect **CUDA** and install a matching **PyTorch** wheel (falls back to CPU build),
* check **FFmpeg** availability (prints tips if missing).

> FFmpeg must be in `PATH`.
> Windows (Chocolatey): `choco install ffmpeg`
> Ubuntu/Debian: `sudo apt install ffmpeg`



## 🚀 Quick start

### Video → SBS video

```bash
python main.py -i input.mp4 -o output_sbs.mp4 --preset balance
```

### Folder of frames → SBS PNGs

```bash
python main.py -i ./frames -o ./out --input-type folder --preset balance
```

### Single image (i2i)

One image
```bash
python main.py -i image.png -o image_sbs.png --input-type i2i
```
Several images
```bash
python main.py -i ./Images -o ./out --input-type i2i
```

### Debug mode

To see detailed performance stats and system info, add `--debug`:
```bash
python main.py -i input.mp4 -o output_sbs.mp4 --preset balance --debug
```



## ⚡ Performance Presets (Full HD, Depth-Anything-V2)
Benchmarks measured on **AMD Ryzen 7 7700X + NVIDIA GeForce RTX 5090 + 32 GB DDR5**  
*(Windows 10, CUDA 12, Python 3.12)*  

> **Note:**
> 
> Presets are designed for convenience and to provide stable performance baselines.
> This pipeline does not impose strict limits on RAM, VRAM, or other system resources - if something crashes due to lack of resources, it will usually not be prevented automatically.
>
> Therefore, it is highly recommended to use presets as a starting point (for fine-tuning via `--debug`), but do not assume you will get identical performance results, as many variables affect it - most importantly, the balance of your hardware and operating system.



###  Presets - Folder Mode (Full HD)

| Preset | Target VRAM | Model | Batch | Feeders | Preprocess | Processors | Savers | Queues (r/in/p/s) | RAM Usage (avg/max GB) | FPS | Notes |
|:-------|:-------------|:-------|:-------|:---------|:------------|:------------|:--------|:------------------|:------------------------|:------|:------|
| **Minimum** | 4 GB | Depth-Anything-V2-Small-hf | 4 | 1 | 1 | 4 | 3 | 8 | 4,3 / 4,8 | **21.9 FPS** | Optimized for low-VRAM/RAM system |
| **Balance** | 8 GB | Depth-Anything-V2-Base-hf | 5 | 1 | 2 | 8 | 4 | 16 | 7,0 / 7,7 | **22.2 FPS** | Best overall performance |
| **Max Quality** | 12 GB | Depth-Anything-V2-Large-hf | 6 | 1 | 2 | 4 | 2 | 16 | 5,0/ 5,8 | **16.7 FPS** | Highest depth accuracy, GPU-bound |

###  Presets - Video Mode (Full HD)
| Preset | Target VRAM | Model | Batch | Feeders | Preprocess | Processors | Savers | Queues (r/in/p/s) | RAM Usage (avg/max GB) | FPS | Notes |
|:-------|:-------------|:-------|:-------|:---------|:------------|:------------|:--------|:------------------|:------------------------|:------|:------|
| **Minimum** | 4 GB | Depth-Anything-V2-Small-hf | 3 | 1 | 1 | 4 | 1 | 6 | 4,4 / 5,0 | **19.8 FPS** | Optimized for low-VRAM/RAM system |
| **Balance** | 8 GB | Depth-Anything-V2-Base-hf | 5 | 1 | 2 | 8 | 1 | 16 | 8,4 / 9,8 | **21.8 FPS** | Best overall performance |
| **Max Quality** | 12 GB | Depth-Anything-V2-Large-hf | 6 | 1 | 1 | 3 | 1 | 16 | 5,2/ 5,7 | **16.5 FPS** | Highest depth accuracy, GPU-bound |

---

#### Linux Performance

- On **Linux** (tested on *Ubuntu 24.04 + CUDA 12*), performance is **significantly higher** compared to Windows.  
- In some cases, the save queue may fill faster - if RAM usage increases over time, raise the number of savers (`--savers +1…2`).  
- For best stability and throughput, **Linux is the recommended platform**.

#### Windows Performance

- After several hours of system uptime, performance may drop by **≈25 %**, likely due to Windows scheduler or GPU driver throttling (not related to the script).  
- To ensure consistent results, **reboot before long renders or benchmarking**.  
- The presets above were benchmarked on **Windows 10**, so FPS values reflect typical Windows performance.


## Project structure

```
├─ main.py               # CLI entrypoint (initialization, CLI-interface, launch)
├─ pipeline_core.py      # Worker threads (feeder → preprocess → GPU → process → save)
├─ depthestimator.py     # Depth Anything V2 (HF Transformers + PyTorch)
├─ converter.py          # SBS image conversion (Numba + OpenCV)
├─ sbsutils.py           # NVENC detect, presets merge, system info, debug report
├─ monitor.py            # Queue/Memory monitors + plots
├─ presets.json          # Ready presets (video/folder)
├─ test_cli.py           # Testing operational
├─ setup_env.py          # Bootstrap PyTorch/FFmpeg and requirements
├─ torch_detect.py       # Torch check (setup_env.py component)
├─ requirements.txt
└─ README.md
```

## Credits

* **Fortuna** - original ComfyUI nodes, docs, and project leadership
* Community testers and artists who shared feedback and examples

## Acknowledgements

This project uses the following open-source Python libraries:
`numpy`, `numba`, `opencv-python`, `natsort`, `psutil`, `py-cpuinfo`,
`matplotlib`, and `transformers`.

It also uses models from the project:
[Depth-Anything-V2](https://github.com/DepthAnything/Depth-Anything-V2).

## 💬 Contact

* GitHub Issues: [https://github.com/Iablunoshka/VR-we-are-CLI/issues](https://github.com/Iablunoshka/VR-we-are-CLI/issues)
* Discord: [Activation Link](https://discord.gg/ZegT6Cc8FG)
