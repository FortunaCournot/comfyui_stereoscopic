from threading import Thread
from queue import Queue
from natsort import natsorted
from dataclasses import fields
import numpy as np
import threading
import os , time , cv2 , signal 
from depthestimator import DepthEstimator 
from converter import ImageSBSConverter
from pipeline_core import PipelineContext
from utils import force_exit , debug_report , load_preset , merge_with_preset , validate_config , detect_nvenc_support


def init_pipeline(
    version: str,
    video_path: str,
    estimator: DepthEstimator,
    SBSConverter: ImageSBSConverter,
    output_path: str,
    *,
    batch_size: int = 20,
    in_queue: int = 32,
    r_queue: int = 32,
    s_queue: int = 32,
    p_queue: int = 32,
    n_preprocess: int = 2,
    n_processors: int = 6,
    n_savers: int = 1,
    n_feeders: int = 1,
    model_name: str = "depth-anything/Depth-Anything-V2-Small-hf",
    codec: str = "libx264",
    input_type: str = "video",
    debug: bool = False,
    depth_scale: float = 1.0,
    depth_offset: float = 0.0,
    switch_sides: bool = False,
    symetric: bool = False,
    blur_radius: int = 19
    ) -> PipelineContext:
        
    """
    Initialize the multistage conversion pipeline.

    Args:
        video_path (str): Path to video file, folder, or single image.
        estimator (DepthEstimator): Depth prediction module.
        SBSConverter (ImageSBSConverter): Stereo SBS converter.
        output_path (str): Where to save output results.
        batch_size (int): Number of frames/images processed per batch.
        *_queue (int): Queue capacities for each stage (raw, input, process, save).
        n_preprocess (int): Number of CPU threads for preprocessing.
        n_processors (int): Number of CPU threads for SBS conversion.
        n_savers (int): Number of disk writer threads.
        n_feeders (int): Number of threads feeding input frames.
        model_name (str): Depth model name from HuggingFace.
        codec (str): Output video codec (for video mode only).
        input_type (str): One of ['video', 'folder', 'i2i'].
        debug (bool): Enable memory/queue monitoring.
        depth_scale, depth_offset (float): Depth parameters.
        switch_sides (bool): Swap left/right views in the final SBS frame.
        symetric (bool): Enable symmetric stereo rendering.
        blur_radius (int): Radius for blurring depth maps before conversion.

    Returns:
        PipelineContext: fully configured context object with worker threads ready to start.
    """
        
    # --- Detect and prepare input source ---
    # Depending on input_type, determine dimensions, FPS, and I/O codec
    if input_type == "video":
        cap = cv2.VideoCapture(video_path)
        ok, frame = cap.read()
        fps = cap.get(cv2.CAP_PROP_FPS)
        if not fps or np.isnan(fps):
            fps = 30.0
            print("[warn] FPS autodetect failed - defaulting to 30")
        cap.release()
        if not ok:
            raise RuntimeError("Failed to read first frame")
        H, W = frame.shape[:2]
        cudnn_benchmark = True
    elif input_type == "folder":
        files = natsorted([f for f in os.listdir(video_path) if f.lower().endswith((".png", ".jpg", ".jpeg"))])
        if not files:
            raise RuntimeError("No images found in folder")

        # test reading for sizes
        first = cv2.imread(os.path.join(video_path, files[0]), cv2.IMREAD_COLOR)
        if first is None:
            raise RuntimeError("Failed to read first image")
        fps = 0
        codec = "png"
        H, W = first.shape[:2]
        cudnn_benchmark = True
    else:
        cudnn_benchmark = False
        first = cv2.imread(video_path, cv2.IMREAD_COLOR)
        if first is None:
            raise RuntimeError(f"Failed to read image {video_path}")
        fps = 0
        H, W = first.shape[:2]   
    
    estimator.load_model(model_name,cudnn_benchmark)
    processor = estimator.processor
    device = estimator.device

    # Create thread-safe queues to connect pipeline stages
    raw_q = Queue(maxsize=r_queue)  # feeders → preprocessors
    inp_q = Queue(maxsize=in_queue) # preprocessors → GPU inference
    proc_q = Queue(maxsize=p_queue) # GPU inference → SBS processors
    save_q = Queue(maxsize=s_queue) # processors → savers
    

    ctx = PipelineContext(
        version=version,
        video_path=video_path,
        estimator=estimator,
        SBSConverter=SBSConverter,
        output_path=output_path,
        batch_size=batch_size,
        in_queue=in_queue,
        r_queue=r_queue,
        s_queue=s_queue,
        p_queue=p_queue,
        n_preprocess=n_preprocess,
        n_processors=n_processors,
        n_savers=n_savers,
        model_name=model_name,
        codec=codec, debug=debug,
        H=H, W=W, fps=fps,
        raw_queue=raw_q,
        input_queue=inp_q,
        save_queue=save_q,
        process_queue=proc_q,
        depth_scale=depth_scale,
        depth_offset=depth_offset,
        switch_sides=switch_sides,
        symetric=symetric,
        blur_radius=blur_radius,
        input_type=input_type,
        n_feeders=n_feeders
    )
    
    if debug:
        print("\n[Pipeline Configuration]")
        for f in fields(ctx):
            name = f.name
            value = getattr(ctx, name)
            if isinstance(value, (list, dict)) or "queue" in name or "worker" in name:
                continue
            print(f"{name:>15}: {value}")
    
    max_frames = None
        
    # --- Build and assign pipeline worker threads ---
    # Feeders -> Preprocessors -> GPU inference -> Processors -> Savers

    if input_type == "video":
        ctx.result_dict = {"frames": 0}
        ctx.feeders = [Thread(target=PipelineContext.video_feeder, args=(video_path, raw_q, W, H, ctx.result_dict, max_frames))]
    elif input_type == "folder":
        ctx.result_dict = {"frames": 0} 
        chunks = np.array_split(files, n_feeders)
        for chunk in chunks:
            ctx.feeders.append(Thread(
                target=PipelineContext.image_folder_feeder,
                args=(video_path, raw_q, list(chunk),ctx.result_dict)))
    else:
        ctx.result_dict = {"frames": 1}
        ctx.feeders = [Thread(
            target=PipelineContext.image_folder_feeder,
            args=(os.path.dirname(video_path), raw_q, [os.path.basename(video_path)])
        )]
    
    for _ in range(n_preprocess):
        ctx.pre_workers.append(Thread(target=PipelineContext.preprocess_worker,args=(raw_q, batch_size, estimator.processor, estimator.device, inp_q)))
        
    ctx.gpu_worker = Thread(target=PipelineContext.gpu_worker_loop,args=(estimator, inp_q, proc_q, model_name, n_preprocess, H, W, n_processors,cudnn_benchmark,input_type))
                            
    for _ in range(n_processors):
        ctx.processors.append(Thread(target=PipelineContext.process_worker, args=(proc_q, SBSConverter, save_q,input_type,depth_scale,depth_offset,switch_sides,symetric,blur_radius)))
    
    if input_type == "video":
        for _ in range(n_savers):
            ctx.savers.append(Thread(target=PipelineContext.video_worker_thread, args=(save_q, video_path, output_path, W*2, H, fps, codec)))
    elif input_type == "folder":
        for _ in range(n_savers):
            ctx.savers.append(Thread(target=PipelineContext.save_worker_thread, args=(save_q, output_path,input_type)))
    else:
        ctx.savers.append(Thread(
            target=PipelineContext.save_worker_thread,
            args=(save_q, output_path, input_type)))
        

    # --- Optional monitoring tools for debugging ---
    if debug:
        from monitor import MemoryMonitor, QueueMonitor
        ctx.mem_mon = MemoryMonitor(interval=0.5, include_children=True)
        ctx.q_mon = QueueMonitor(
            queues={"raw": raw_q, "input": inp_q, "process": proc_q, "save": save_q},
            interval=0.25
        )

    return ctx
    
    
def run_pipeline(ctx: PipelineContext):
    """
    Launch all pipeline threads and manage their lifecycle.
    """
    
    # monitors
    if ctx.debug:
        ctx.mem_mon.start()
        ctx.q_mon.start()

    ctx.t_start = time.perf_counter()

    # start
    for t in ctx.feeders: t.start()
    for t in ctx.pre_workers: t.start()
    ctx.gpu_worker.start()
    for t in ctx.processors: t.start()
    for t in ctx.savers: t.start()

    # join and the distribution of "poison pills"
    
    # Wait for feeders to finish producing frames
    for t in ctx.feeders:
        t.join()
        
    # Signal preprocess workers to stop (send poison pills)
    for _ in range(ctx.n_preprocess):
        ctx.raw_queue.put(None)
    for t in ctx.pre_workers:
        t.join()
    
    # Wait for GPU inference and CPU processing to complete
    ctx.gpu_worker.join()
    for t in ctx.processors:
        t.join()
    
    # Signal saver threads to stop
    for _ in range(ctx.n_savers):
        ctx.save_queue.put(None)
    for t in ctx.savers:
        t.join()

    ctx.t_end = time.perf_counter()
    print(f"Process time: {ctx.t_end - ctx.t_start:.4f} sec")


        
# --- Command-line interface ---
if __name__ == "__main__":
    import argparse
    version = "1.0.0"
    parser = argparse.ArgumentParser(
        description="VR we are! CLI pipeline (video → 3D SBS video, "
                    "folder → batch of images, i2i → single/multiple images one-by-one)."
    )
    parser.add_argument("--version","-v", action="version", version=f"VR We Are {version} (CLI)")
    parser.add_argument("--input", "-i", type=str, required=True,
                        help=("Path to input.\n"
                              "  video: path to video file\n"
                              "  folder: path to folder with images (same resolution)\n"
                              "  i2i: single image file OR folder with mixed-resolution images"))
    parser.add_argument("--output", "-o", type=str, required=True,
                        help=("Path to output.\n"
                              "  video: output video file (e.g. out.mp4)\n"
                              "  folder: output directory for processed images\n"
                              "  i2i: if input is a single image → output file; "
                              "if input is a folder → output directory"))
    parser.add_argument("--batch-size", "-b", type=int, default=None,
                        help="Batch size for processing (video/folder modes only)")
    parser.add_argument("--model", "-m", type=str, default=None,
                    choices=DepthEstimator.AVAILABLE_MODELS,
                    help="Which depth model to use")
    parser.add_argument("--codec", "-c", type=str,
                    choices=["libx264", "libx265", "h264_nvenc", "hevc_nvenc"],
                    default=None,
                    help="Codec for output video (CPU: libx264/libx265, GPU: h264_nvenc/hevc_nvenc)")
    parser.add_argument("--input-type", type=str,
                        choices=["video", "folder", "i2i"], default="video",
                        help=("Processing mode:\n"
                              "  video = single video\n"
                              "  folder = batch same-resolution images\n"
                              "  i2i = images one-by-one (single or mixed-resolution folder)"))
    parser.add_argument("--debug", "-d", action="store_true",
                    help="Enable debug mode with memory/queue monitoring")
    parser.add_argument("--preset","-p", type=str, choices=["minimum", "balance", "max_quality"],
                        help="Use a predefined configuration preset")

    # Queues
    parser.add_argument("--in-queue", type=int, default=None,
                        help="Max size of input queue (CPU → GPU)")
    parser.add_argument("--r-queue", type=int, default=None,
                        help="Max size of raw queue (disk → preprocess)")
    parser.add_argument("--s-queue", type=int, default=None,
                        help="Max size of save queue (process → disk)")
    parser.add_argument("--p-queue", type=int, default=None,
                        help="Max size of process queue (GPU → CPU)")

    # Streams 
    parser.add_argument("--feeders", type=int, default=None,
                        help="Number of feeder threads (video: must be 1)")
    parser.add_argument("--preprocess", "-pre", type=int, default=None,
                        help="Number of CPU preprocess threads")
    parser.add_argument("--processors", type=int, default=None,
                        help="Number of processing threads (depth→SBS)")
    parser.add_argument("--savers", type=int, default=None,
                        help="Number of saver threads "
                             "(video/i2i: must be 1; folder: can be >1)")
                        
    # converter settings
    parser.add_argument("--depth-scale", type=float, default=None,
                        help="Scale factor for depth map (default=1.0)")
    parser.add_argument("--depth-offset", type=float, default=None,
                        help="Offset for depth map (default=0.0)")
    parser.add_argument("--switch-sides", action="store_true",default=None,
                        help="Swap left/right images in output (default=False)")
    parser.add_argument("--symmetric", dest="symetric", action="store_true",default=None,
                        help="Enable symmetric rendering (default=False)")
    parser.add_argument("--blur-radius", type=int, default=None,
                        help="Blur radius applied to depth map before shifting (default=19)")
    
    args = parser.parse_args()
    
    # Force shutdown (Ctrl+C or SIGTERM)
    signal.signal(signal.SIGINT, force_exit)
    signal.signal(signal.SIGTERM, force_exit)
    
    estimator = DepthEstimator()
    SBSConverter = ImageSBSConverter()
    preset_data = {}

    # --- i2i (image-to-image) mode ---
    # Processes a single image or folder of images individually (no batching).
    if args.input_type == "i2i":
        validate_config(args, parser)

        if os.path.isfile(args.input):
            # single image
            images = [args.input]
            if os.path.isdir(args.output):
                parser.error("For single image input (--input=file) you must provide --output as a file, not a folder.")
        else:
            # folder with pictures
            images = natsorted([os.path.join(args.input, f)
                                for f in os.listdir(args.input)
                                if f.lower().endswith((".png", ".jpg", ".jpeg"))])
            if not images:
                parser.error(f"No images found in input folder: {args.input}")
            os.makedirs(args.output, exist_ok=True)

        for img_path in images:
            if os.path.isfile(args.input):
                # input one image → output = file
                out_path = args.output
            else:
                # input folder → output = folder + filename
                out_name = os.path.splitext(os.path.basename(img_path))[0] + ".png"
                out_path = os.path.join(args.output, out_name)

            ctx = init_pipeline(
                version,
                video_path=img_path,
                estimator=estimator,
                SBSConverter=SBSConverter,
                output_path=out_path,
                batch_size=1,
                in_queue=1, r_queue=1, s_queue=1, p_queue=1,
                n_preprocess=1, n_processors=1, n_savers=1, n_feeders=1,
                model_name=args.model or "depth-anything/Depth-Anything-V2-Base-hf",
                codec="png",
                input_type=args.input_type,
                debug=args.debug,
                depth_scale=args.depth_scale or 1.0,
                depth_offset=args.depth_offset or 0.0,
                switch_sides=args.switch_sides or False,
                symetric=args.symetric or False,
                blur_radius=args.blur_radius or 19
            )
            run_pipeline(ctx)
        debug_report(ctx)
        print(f"Conversion complete. Output saved to: {ctx.output_path}")
    # ---  video and folder mods ---
    else:
        if args.preset:
            preset_data = load_preset(args.input_type, args.preset)
            print(f"Loaded preset '{args.preset}' for mode '{args.input_type}'")
            
            merged_params = merge_with_preset(args, preset_data, PipelineContext)
            
            #for k, v in merged_params.items():
            #    print(f"{k:>15}: {v}")

            validate_config(merged_params, parser)
            ctx = init_pipeline(
                version,
                estimator=estimator,
                SBSConverter=SBSConverter,
                **merged_params
            )

            run_pipeline(ctx)
            debug_report(ctx)
        else:
            if args.input_type == "video":
                if detect_nvenc_support():
                    codec = "h264_nvenc"
                    print("NVENC available — using GPU encoder (h264_nvenc).")
                else:
                    codec = "libx264"
                    print("Using CPU encoder: libx264")
            else:
                codec = None
                
            validate_config(args, parser)
            ctx = init_pipeline(
                version,
                video_path=args.input,
                estimator=estimator,
                SBSConverter=SBSConverter,
                output_path=args.output,
                batch_size=args.batch_size or 5,
                in_queue=args.in_queue or 16,
                r_queue=args.r_queue or 16,
                s_queue=args.s_queue or 16,
                p_queue=args.p_queue or 16,
                n_preprocess=args.preprocess or 2,
                n_processors=args.processors or 8,
                n_savers=args.savers or 1,
                n_feeders=args.feeders or 1,
                model_name=args.model or "depth-anything/Depth-Anything-V2-Base-hf",
                codec=args.codec or codec,
                input_type=args.input_type,
                debug=args.debug,
                depth_scale=args.depth_scale or 1.0,
                depth_offset=args.depth_offset or 0.0,
                switch_sides=args.switch_sides or False,
                symetric=args.symetric or False,
                blur_radius=args.blur_radius or 19
            )
            run_pipeline(ctx)
            debug_report(ctx)
            print(f"Conversion complete. Output saved to: {ctx.output_path}")
        

