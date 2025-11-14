import os
import subprocess
import argparse
import random
from tqdm import tqdm


def compute_value_for_iteration(i, startvalue, endvalue, iterations):
    """Compute float value for given iteration index."""
    if iterations <= 1:
        return startvalue
    step = (endvalue - startvalue) / (iterations - 1)
    return startvalue + i * step


def create_metadata_comment(args, seed):
    """Generate formatted metadata string from CLI args."""
    meta = {
        "seed": seed,
        "iterations": args.iterations,
        "startvalue": args.startvalue,
        "endvalue": args.endvalue,
        "sampler": args.sampler,
        "input_name": args.input_name,
        "fps": args.fps,
        "codec": args.codec,
        "workflow": os.path.basename(args.workflow),
        "target_length": args.target_length,
        "tests": args.tests
    }
    return ", ".join(f"{k}={v}" for k, v in meta.items())


def run_one_test(args, test_index, seed):
    """
    Runs a full test:
    - Generate iterations number of frames
    - Pad to target_length using last frame
    - Build video
    - Cleanup
    """
    output_dir = args.output_dir
    os.makedirs(output_dir, exist_ok=True)

    # pre-calc values
    values = [
        compute_value_for_iteration(i, args.startvalue, args.endvalue, args.iterations)
        for i in range(args.iterations)
    ]

    # Prefix for files
    prefix = f"test{test_index:03d}_seed{seed}_start{args.startvalue}_end{args.endvalue}"

    # Generate frames
    for i, val in enumerate(values):
        filename = f"{prefix}_iter{i:03d}.png"
        output_path = os.path.join(output_dir, filename)

        print(f"[INFO] Test {test_index}: Running workflow for {args.input_name}={val:.4f}")

        # Placeholder ComfyUI call
        # subprocess.run([...])

        # Simulate image creation
        open(output_path, "wb").close()

    # Last generated frame
    last_frame = os.path.join(output_dir, f"{prefix}_iter{args.iterations-1:03d}.png")

    # Padding
    for p in range(args.iterations, args.target_length):
        pad_name = f"{prefix}_iter{p:03d}.png"
        pad_path = os.path.join(output_dir, pad_name)
        # Copy last frame
        with open(last_frame, "rb") as src, open(pad_path, "wb") as dst:
            dst.write(src.read())

    # Make Video
    output_video = os.path.join(output_dir, f"{prefix}.mp4")

    print(f"[INFO] Creating video: {output_video}")

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-framerate", str(args.fps),
        "-pattern_type", "glob",
        "-i", os.path.join(output_dir, f"{prefix}_iter*.png"),
        "-c:v", args.codec,
        output_video
    ]

    subprocess.run(ffmpeg_cmd, check=True)

    # Metadata via exiftool
    comment_text = create_metadata_comment(args, seed)
    try:
        subprocess.run([
            "exiftool",
            f"-comment={comment_text}",
            f"-XMP-exif:UserComment={comment_text}",
            "-overwrite_original",
            output_video
        ], check=True)
        print(f"[INFO] Metadata embedded using exiftool.")
    except FileNotFoundError:
        print("[WARN] exiftool not found in PATH, skipping metadata embedding.")

    # Cleanup all frames
    for f in os.listdir(output_dir):
        if f.startswith(prefix) and f.endswith(".png"):
            os.remove(os.path.join(output_dir, f))


def main():
    parser = argparse.ArgumentParser(description="Run ComfyUI workflows over float ranges and assemble video output.")
    parser.add_argument("--workflow", required=True, help="Path to ComfyUI workflow JSON")
    parser.add_argument("--iterations", type=int, default=5, help="Number of iteration steps")
    parser.add_argument("--startvalue", type=float, default=0.0, help="Start value for range")
    parser.add_argument("--endvalue", type=float, default=1.0, help="End value for range")
    parser.add_argument("--sampler", default="KSampler", help="Sampler node name")
    parser.add_argument("--input_name", default="strength", help="Workflow input name to modify each iteration")
    parser.add_argument("--fps", type=int, default=10, help="Frames per second for video")
    parser.add_argument("--codec", default="libx264", help="Video codec for ffmpeg")
    parser.add_argument("--output_dir", default="output_frames", help="Directory for output frames and video")
    parser.add_argument("--target_length", type=int, default=16, help="Total frames of final video (padded)")
    parser.add_argument("--tests", type=int, default=1, help="How many test videos to generate")
    args = parser.parse_args()

    print(f"[INFO] Running {args.tests} test(s)")

    for t in tqdm(range(args.tests), desc="Generating tests"):
        seed = random.randint(0, 999999)
        run_one_test(args, t, seed)

    print("[INFO] All tests completed.")


if __name__ == "__main__":
    main()
