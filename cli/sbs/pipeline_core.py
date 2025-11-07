from threading import Thread
from queue import Queue
from dataclasses import dataclass, field
import threading
import numpy as np
import os , time , cv2 , subprocess 
from sbsutils import force_exit , graceful_shutdown , prepare_batch 
from depthestimator import DepthEstimator
from converter import ImageSBSConverter



@dataclass
class PipelineContext:
    """
    Central configuration and state container for the conversion pipeline.

    Holds:
        - All runtime parameters (queues, thread counts, image sizes)
        - All worker thread instances
        - Monitoring and debug references
        - Timing info for profiling

    Each static method below represents one stage in the pipeline.
    """
    
    # input parameters
    video_path: str
    input_type: str
    estimator: DepthEstimator
    SBSConverter: ImageSBSConverter
    output_path: str
    batch_size: int
    in_queue: int
    r_queue: int
    s_queue: int
    p_queue: int
    n_preprocess: int
    n_processors: int
    n_savers: int
    n_feeders: int
    model_name: str
    codec: str
    version: str
    
    # calculated fields
    H: int = 0
    W: int = 0
    fps: float = 0.0

    # queues
    raw_queue: Queue = field(default=None)
    input_queue: Queue = field(default=None)
    save_queue: Queue = field(default=None)
    process_queue: Queue = field(default=None)

    # streams
    feeders: list[Thread] = field(default_factory=list)
    pre_workers: list[Thread] = field(default_factory=list)
    gpu_worker: Thread | None = None
    processors: list[Thread] = field(default_factory=list)
    savers: list[Thread] = field(default_factory=list)
    
    # converter settings
    depth_scale: float = 1.0
    depth_offset: float = 0.0
    switch_sides: bool = False
    symetric: bool = False
    blur_radius: int = 19
    

    # debugging/monitors
    debug: bool = False
    result_dict: dict = field(default_factory=dict)
    mem_mon: object | None = None
    q_mon: object | None = None

    # timings
    t_start: float = 0.0
    t_end: float = 0.0
    
    # etc
    fatal_error: bool = False
    video_quality: str = "medium"
    
    @staticmethod
    def video_worker_thread(save_queue: Queue,video_path, output_path: str, width: int, height: int, fps: float,codec: str,crf: int, cq: int,ctx):
        """
        Writes SBS frames from queue to video via FFmpeg, preserving audio if present.
        """
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        ffmpeg_cmd = [
            "ffmpeg",
            "-y",
            "-hide_banner", 
            "-loglevel", "info",  # quiet removes all logs
            # Input video raw (pictures from pipe)
            "-f", "rawvideo",
            "-pix_fmt", "rgb24", 
            "-s", f"{width}x{height}",
            "-r", str(fps),
            "-i", "-",
            "-i", video_path,
            # mapping
            "-map", "0:v:0",
            "-map", "1:a:0?",
            # video
            "-c:v", codec,
            ] + (["-crf", str(crf)] if codec in ("libx264", "libx265") else ["-rc:v", "vbr", "-cq:v", str(cq), "-b:v", "0"]) + [ 
            "-pix_fmt", "yuv420p",
            "-c:a", "copy",
            output_path
        ]

        proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE)

        buffer = {}          # dict: index -> np.ndarray (image)
        next_index = 0       # the next frame index to be written
        finished = False

        try:
            while True:
                try:
                    item = save_queue.get()
                except EOFError:
                    return
                if item is None:
                    # Note: sentinel has arrived - there will be no more new batches.
                    finished = True
                else:
                    indices, sbs_images = item

                    for idx, image in zip(indices, sbs_images):
                        buffer[idx] = image 

                # We try to write all available frames in a row, starting from next_index
                while next_index in buffer:
                    try:
                        proc.stdin.write(buffer[next_index].tobytes())
                    except Exception as e:
                        print(f"FFmpeg pipe broken - {e}")
                        ctx.fatal_error = True
                        graceful_shutdown(ctx)
                        return
                        
                    del buffer[next_index]
                    next_index += 1

                if finished and not buffer:
                    break

        finally:
            try:
                if proc.stdin:
                    proc.stdin.close()
            except Exception:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    proc.kill()
                except Exception:
                    pass
    
    @staticmethod
    def save_worker_thread(save_queue: Queue, output_dir: str,input_type: str | None = None):
        """
        Saves SBS images from queue to disk (PNG). Works for folder and i2i.
        """
        if input_type == "folder":
            os.makedirs(output_dir, exist_ok=True)

        while True:
            try:
                item = save_queue.get()
            except EOFError:
                return
            if item is None:
                break

            names, sbs_images = item
            for name, image in zip(names, sbs_images):
                image_bgr = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)

                if input_type == "folder":
                    save_path = os.path.join(output_dir, f"{name}.png")
                else:  # i2i (single image)
                    save_path = output_dir  

                cv2.imwrite(save_path, image_bgr)
    
    @staticmethod
    def process_worker(process_queue: Queue, SBSConverter, save_queue: Queue,input_type,depth_scale,depth_offset,switch_sides,symetric,blur_radius):
        """
        Converts depth maps into SBS images and sends results to saving queue.
        """

        while True:
            #start_wait = time.perf_counter()
            try:
                item = process_queue.get()
            except EOFError:
                return
            #end_wait = time.perf_counter()
            #print(f"Waited {end_wait - start_wait:.3f} s on queue.get()")
            if item is None:
                break

            if input_type == "video":
                indices, depth_maps, indexed_images = item
            else:  # folder + i2i
                names, depth_maps, indexed_images = item

            # Cooking batches
            base_image, depth_image = prepare_batch(indexed_images, depth_maps)

            #start_c = time.perf_counter()
            # Call for processing
            sbs_images = SBSConverter.process(
                base_image,
                depth_image,
                depth_scale,           # can be moved to the config
                depth_offset,
                switch_sides,
                blur_radius,
                symetric
            )
            #end_c = time.perf_counter()
            #print(f"Waited {end_c - start_c:.3f} s on converting")
            #print(f"Save queue size: {save_queue.qsize()}/{save_queue.maxsize}")
            
            # Convert here → uint8 RGB
            sbs_uint8 = [(img * 255).clip(0, 255).astype(np.uint8) for img in sbs_images]

            if input_type == "video":
                try:
                    save_queue.put((indices, sbs_uint8))
                except EOFError:
                    return
            else:
                try:
                    save_queue.put((names, sbs_uint8))
                except EOFError:
                    return
                
    @staticmethod   
    def gpu_worker_loop(estimator, queue: Queue, process_queue: Queue ,model_name, n_preprocess: int,H_orig, W_orig,n_processors: int,cudnn_benchmark: bool,input_type: str):
        """
        Runs depth inference on GPU for batches and sends results to processing queue.
        """
        
        done_count = 0
        while True:
            #start_wait = time.perf_counter()
            try:
                item = queue.get()
            except EOFError:
                return
            #end_wait = time.perf_counter()
            #print(f"Waited {end_wait - start_wait:.3f} s on queue.get()")
            if item is None:
                done_count += 1 # tracks how many preprocess workers finished 
                if done_count == n_preprocess:
                    break
                continue
                
            #start_gpu = time.perf_counter()
            
            indices, names, pixel_values, indexed_images = item
            depth_maps = estimator.predict_batch_tensor(pixel_values,cudnn_benchmark, target_size=(H_orig, W_orig),model_name=model_name)
            
            #end_gpu = time.perf_counter()
            #print(f"Waited {end_gpu - start_gpu:.3f} s on predict_batch_tensor")
            
            if input_type== "video":  # video
                try:
                    process_queue.put((indices, depth_maps, indexed_images))
                except EOFError:
                    return
            else:  # folder and i2i
                try:
                    process_queue.put((names, depth_maps, indexed_images))
                except EOFError:
                    return
            
        for _ in range(n_processors):
            try:
                process_queue.put(None)
            except EOFError:
                return
            
    @staticmethod
    def preprocess_worker(raw_queue: Queue, batch_size: int, processor, device, input_queue: Queue):
        """
        Loads and preprocesses frames into GPU-ready tensors (batched).
        """

        batch_idx, batch_imgs, batch_names = [], [], []
        while True:
            #start_wait = time.perf_counter()
            try:
                item = raw_queue.get()
            except EOFError:
                return
            #end_wait = time.perf_counter()
            #print(f"Waited {end_wait - start_wait:.3f} s on queue.get()")
            if item is None:
                if batch_imgs:
                    inputs = processor(images=batch_imgs, return_tensors="pt")
                    
                    try:
                        input_queue.put((
                            list(batch_idx),
                            list(batch_names),
                            inputs.pixel_values.to(device, non_blocking=True),
                            list(zip(batch_idx, batch_imgs))
                        ))
                    except EOFError:
                        return
                        
                # forward single sentinel to input_queue and exit
                try:
                    input_queue.put(None)
                except EOFError:
                    return
                break
                
            if len(item) == 2:  # (idx, img) - for video
                idx, img = item
                name = None
            elif len(item) == 3:  # (None, img, name) - for folder
                idx, img, name = item
            else:
                raise ValueError("Unknown item format")

            batch_idx.append(idx)
            batch_imgs.append(img)
            batch_names.append(name)
            
            if len(batch_imgs) >= batch_size:
                inputs = processor(images=batch_imgs, return_tensors="pt")
                try:
                    input_queue.put((
                        list(batch_idx),
                        list(batch_names),
                        inputs.pixel_values.to(device, non_blocking=True),
                        list(zip(batch_idx, batch_imgs))
                    ))
                except EOFError:
                    return
                    
                batch_idx.clear(); batch_imgs.clear(); batch_names.clear()

    @staticmethod
    def video_feeder(video_path, raw_queue,W_orig,H_orig,result_dict,max_frames: int | None = None):
        """
        Streams raw RGB frames from video via FFmpeg into queue.
        """
        cmd = [
            "ffmpeg",
            "-i", video_path,
            #"-vsync", "0",
            "-f", "rawvideo",
            "-pix_fmt", "rgb24",
            "-"
        ]
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        frame_size = W_orig * H_orig * 3
        idx = 0
        try:
            while True:
                raw = p.stdout.read(frame_size)
                if len(raw) < frame_size:
                    break
                img = np.frombuffer(raw, dtype=np.uint8).reshape((H_orig, W_orig, 3)).copy()
                try:
                    raw_queue.put((idx, img))
                except EOFError:
                    return
                idx += 1
                if max_frames is not None and idx >= max_frames:
                    break
        finally:
            try:
                p.stdout.close()
            except:
                pass
            p.wait()
            
        result_dict["frames"] = idx
        #print("images put in  (ffmpeg pipe):", idx)
        
    @staticmethod
    def image_folder_feeder(folder_path, raw_queue, file_list,result_dict=None):
        """
        Reads images from assigned folder and pushes them into queue.
        """
        idx = 0
        for fname in file_list:
            path = os.path.join(folder_path, fname)
            img = cv2.imread(path, cv2.IMREAD_COLOR)
            if img is None:
                continue
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            name_stem, _ = os.path.splitext(fname)
            try:
                raw_queue.put((None, img, name_stem))
            except EOFError:
                return                
            idx += 1
            
        if result_dict:
            result_dict["frames"] = result_dict.get("frames", 0) + idx
        



    
