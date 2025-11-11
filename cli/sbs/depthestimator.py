import argparse
import os
import glob
import numpy as np
import cv2
import torch
from transformers import AutoImageProcessor, AutoModelForDepthEstimation
import time


class DepthEstimator:
    """
    Depth estimation using the Depth-Anything-V2-Small model from Hugging Face.
    Supports batch processing.
    """
    
    AVAILABLE_MODELS = [
    "depth-anything/Depth-Anything-V2-Small-hf",
    "depth-anything/Depth-Anything-V2-Base-hf",
    "depth-anything/Depth-Anything-V2-Large-hf",
    ]
    
    def __init__(self):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.model_id = None
        self.processor = None
        self.model = None


        
    def load_model(self, model_id: str,cudnn_benchmark: bool):
        """
        Load model only if it's not already loaded or if different model requested.
        """
        if self.model_id != model_id:
            print(f"Loading model: {model_id}")
            self.model_id = model_id
            try:
                self.processor = AutoImageProcessor.from_pretrained(self.model_id, use_fast=True)
            except TypeError:
                self.processor = AutoImageProcessor.from_pretrained(self.model_id)
            self.model = AutoModelForDepthEstimation.from_pretrained(self.model_id)
            
            torch.backends.cudnn.benchmark = cudnn_benchmark
            #torch.backends.cuda.matmul.allow_tf32 = True
            #torch.set_float32_matmul_precision("high")
            
            if self.device.type == "cuda":
                self.model = (self.model.to(self.device).eval())
            else:
                self.model.eval()

        else:
            #print(f"Model '{model_id}' already loaded.")
            pass


    def predict_batch_tensor(self, pixel_values: torch.Tensor,cudnn_benchmark: bool, target_size: tuple[int, int] = None, model_name: str = None) -> list[np.ndarray]:
        """
        Generate normalized depth maps for a batch.
        """
        # Make sure the model is loaded
        if model_name is not None:
            self.load_model(model_name,cudnn_benchmark)
        elif self.model is None:
            self.load_model(self.AVAILABLE_MODELS[0],cudnn_benchmark)

        B, _, H_in, W_in = pixel_values.shape

        # Inference
        with torch.no_grad():
            outputs = self.model(pixel_values=pixel_values)
            preds = outputs.predicted_depth  # [B, H_out, W_out]


        preds = preds.unsqueeze(1)  # [B, 1, H_out, W_out]

        # Size for interpolation
        if target_size is None:
            target_size = (H_in, W_in)
            
        #print(f"target_size: {target_size}")
        # Interpolate to original size
        preds_resized = torch.nn.functional.interpolate(
            preds,
            size=target_size,
            mode="bicubic",
            align_corners=False
        ).squeeze(1)  # [B, H, W] float32 normalized

        # Normalization for each batch element
        mins = preds_resized.amin(dim=(1,2), keepdim=True)  # [B, 1, 1]
        maxs = preds_resized.amax(dim=(1,2), keepdim=True)  # [B, 1, 1]
        ranges = (maxs - mins).clamp(min=1e-6)
        normalized = (preds_resized - mins) / ranges  # [B, H, W]

        # Convert to numpy and return
        depth_maps = [normalized[i].cpu().numpy().astype(np.float32) for i in range(B)]
        return depth_maps
    
    def predict_batch(self, images: list[np.ndarray],model_name,cudnn_benchmark) -> list[np.ndarray]:
        self.load_model(model_name,cudnn_benchmark)
        inputs = self.processor(images=images, return_tensors="pt")
        pixel_values = inputs.pixel_values.to(self.device)
        return self.predict_batch_tensor(pixel_values,cudnn_benchmark)

    def predict_depth(self, image: np.ndarray) -> np.ndarray:
        """
        Legacy single-image API, wraps predict_batch for convenience.
        """
        return self.predict_batch([image], model_name=self.model_id or self.AVAILABLE_MODELS[0], cudnn_benchmark=True)[0]

         
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=50, help="Number of images per batch")
    parser.add_argument("-i", type=str, default=".", help="Directory with input PNGs")
    parser.add_argument("-o", type=str, default="output", help="Directory to save depth maps")
    parser.add_argument("--model", "-m", type=str, default="depth-anything/Depth-Anything-V2-Small-hf", choices=DepthEstimator.AVAILABLE_MODELS, help="Which depth model to use")
    args = parser.parse_args()

    os.makedirs(args.o, exist_ok=True)
    start = time.perf_counter()

    image_paths = sorted(glob.glob(os.path.join(args.i, "*.png")))
    if not image_paths:
        print("[error] No PNG images found in input directory.")
        exit(1)

    estimator = DepthEstimator()

    for i in range(0, len(image_paths), args.batch_size):
        batch_paths = image_paths[i:i + args.batch_size]
        batch_images = [cv2.cvtColor(cv2.imread(p), cv2.COLOR_BGR2RGB) for p in batch_paths]

        depth_maps = estimator.predict_batch(batch_images, args.model, True)

        for path, depth in zip(batch_paths, depth_maps):
            filename = os.path.splitext(os.path.basename(path))[0]
            output_path = os.path.join(args.o, f"{filename}_depth.png")

            # Convert to 8-bit 
            depth_uint8 = (depth * 255).astype(np.uint8)

            cv2.imwrite(output_path, depth_uint8)

    end = time.perf_counter()
    print(f"Process time: {end - start:.4f} sec")
               
            
