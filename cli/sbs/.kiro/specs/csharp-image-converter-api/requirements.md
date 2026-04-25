# Requirements Document

## Introduction

This document defines the requirements for the **C# Image Converter API** — a pure C# Unity library that replaces the existing Python-based depth-estimation and SBS-conversion pipeline entirely. The library runs on Android as part of a Unity APK. It accepts a `Texture2D` input, estimates a depth map on-device using the `Depth-Anything-V2-Small` ONNX model via Unity Sentis, and produces a side-by-side (SBS) stereoscopic `Texture2D` output. There is no Python runtime, no `Process.Start`, and no network access at runtime.

---

## Glossary

- **SBS_Converter**: The overall Unity library described in this document, encompassing all components below.
- **IImageConverter**: The public C# interface exposing `ConvertAsync`.
- **SbsConverterApi**: The concrete implementation of `IImageConverter` that orchestrates depth estimation and SBS processing.
- **SbsConverterComponent**: The `MonoBehaviour` wrapper that hosts `SbsConverterApi` in a Unity scene.
- **DepthEstimator**: The component responsible for running the ONNX depth model via Unity Sentis and returning a normalized depth map.
- **SbsProcessor**: The component responsible for computing pixel shifts, applying blur, performing the subpixel warp, composing the SBS image, and filling crop rectangles.
- **ConversionRequest**: The input record passed to `ConvertAsync`, containing the input texture and all conversion parameters.
- **ConversionResult**: The output record returned by `ConvertAsync`, containing success status, exit code, and the output texture.
- **Sentis**: Unity's on-device neural-network inference package (`com.unity.sentis`).
- **Burst_Job**: A Unity Jobs System job compiled by the Burst Compiler for high-performance parallel CPU execution.
- **NativeArray**: A Unity Collections unmanaged array used inside Burst Jobs.
- **StreamingAssets**: The Unity folder whose contents are bundled verbatim into the APK and accessible at runtime via `Application.streamingAssetsPath`.
- **ONNX_Model**: The `depth_anything_v2_small.onnx` file (~100 MB) exported from PyTorch at build time and placed in `Assets/StreamingAssets/Models/`.
- **GPUCompute**: The Unity Sentis `BackendType.GPUCompute` inference backend (preferred).
- **CPU_Backend**: The Unity Sentis `BackendType.CPU` inference backend (fallback).
- **EditMode_Tests**: Unity Test Runner tests that execute in the Unity Editor without entering Play Mode.

---

## Requirements

### Requirement 1: Public Conversion API

**User Story:** As a Unity developer, I want a simple async API to convert a `Texture2D` to a stereoscopic SBS image, so that I can integrate depth-based 3D conversion into my Android application without managing pipeline internals.

#### Acceptance Criteria

1. THE `IImageConverter` SHALL expose a single method `ConvertAsync(ConversionRequest, CancellationToken)` returning `Task<ConversionResult>`.
2. WHEN `ConvertAsync` is called with a valid `ConversionRequest`, THE `SbsConverterApi` SHALL return a non-null `ConversionResult`.
3. WHEN `ConvertAsync` completes successfully, THE `ConversionResult` SHALL have `Success` equal to `true` and `ExitCode` equal to `0`.
4. WHEN `ConvertAsync` encounters an unrecoverable error during inference or processing, THE `SbsConverterApi` SHALL return a `ConversionResult` with `Success` equal to `false`, `ExitCode` equal to `-1`, and `OutputTexture` equal to `null`.
5. WHEN the `CancellationToken` passed to `ConvertAsync` is cancelled, THE `SbsConverterApi` SHALL propagate an `OperationCanceledException` to the caller.
6. IF `ConversionRequest.InputTexture` is `null`, THEN THE `SbsConverterApi` SHALL throw `ArgumentNullException` before any processing begins.
7. THE `SbsConverterApi` SHALL NOT write diagnostic output to stdout or stderr; all diagnostics SHALL be emitted through the injected `ILogger` instance.
8. THE `ConversionResult.OutputTexture` SHALL have a width equal to twice the width of `ConversionRequest.InputTexture` and a height equal to the height of `ConversionRequest.InputTexture`.

---

### Requirement 2: On-Device Depth Estimation

**User Story:** As a Unity developer, I want depth maps to be estimated entirely on-device using the bundled ONNX model, so that the application works offline without any Python runtime or network dependency.

#### Acceptance Criteria

1. THE `DepthEstimator` SHALL load the ONNX model from `Application.streamingAssetsPath` combined with `SbsConverterOptions.OnnxModelPath` on the first call to `EstimateDepthAsync`.
2. WHEN running on Android, THE `DepthEstimator` SHALL use `UnityWebRequest` to read the ONNX model bytes from `StreamingAssets`.
3. THE `DepthEstimator` SHALL load the model at most once per instance (lazy initialization); subsequent calls to `EstimateDepthAsync` SHALL reuse the loaded model.
4. WHEN the ONNX model file is not found at the configured path, THE `DepthEstimator` SHALL throw `FileNotFoundException` and emit a `LogError` message.
5. THE `DepthEstimator` SHALL preprocess the input texture by resizing it to `SbsConverterOptions.ModelInputSize` × `SbsConverterOptions.ModelInputSize` (default 518×518) using bilinear interpolation.
6. THE `DepthEstimator` SHALL normalize each color channel of the resized image using ImageNet statistics: mean `[0.485, 0.456, 0.406]` and standard deviation `[0.229, 0.224, 0.225]`.
7. THE `DepthEstimator` SHALL build a float32 NCHW tensor of shape `[1, 3, ModelInputSize, ModelInputSize]` and pass it to the Sentis worker under the input name `"pixel_values"`.
8. THE `DepthEstimator` SHALL read the Sentis output tensor named `"predicted_depth"` and bicubic-resize it to the original input texture resolution.
9. THE `DepthEstimator` SHALL min-max normalize the resized depth output so that all values are in the range `[0, 1]` using the formula `(depth - min) / (max - min + 1e-6)`.
10. THE `DepthEstimator` SHALL return the normalized depth map as a `Texture2D` in `RFloat` format with the same width and height as the input texture.
11. WHEN `SbsConverterOptions.InferenceBackend` is `BackendType.GPUCompute` and the GPU backend is unavailable, THE `DepthEstimator` SHALL fall back to `BackendType.CPU` and emit a `LogWarning` message.

---

### Requirement 3: SBS Image Processing

**User Story:** As a Unity developer, I want the SBS conversion to faithfully replicate the Python `converter.py` algorithm using Unity Jobs and Burst, so that the output is visually equivalent to the Python pipeline while running efficiently on Android.

#### Acceptance Criteria

1. THE `SbsProcessor` SHALL invert the depth map before computing pixel shifts by applying `depth[i] = 1.0f - depth[i]` to every pixel.
2. THE `SbsProcessor` SHALL scale the inverted depth values to the range `[-128, 127]` by computing `depth_np[i] = depth[i] * 255.0f - 128.0f`.
3. THE `SbsProcessor` SHALL compute pixel shifts as `pixelShifts[i] = depth_np[i] * depthScaleLocal + depthOffsetLocal`, where `depthScaleLocal = depthScale * width * 50.0f / 1_000_000.0f` and `depthOffsetLocal = depthOffset * -8.0f`.
4. WHEN `ConversionRequest.Symmetric` is `true`, THE `SbsProcessor` SHALL halve both `depthScaleLocal` and `depthOffsetLocal` before computing pixel shifts, and SHALL negate `depthOffsetLocal` when depth inversion is active.
5. WHEN `ConversionRequest.BlurRadius` is greater than `0`, THE `SbsProcessor` SHALL apply a separable box blur with kernel size `BlurRadius × BlurRadius` to the pixel shift map using two sequential Burst Jobs (horizontal pass then vertical pass).
6. WHEN `ConversionRequest.BlurRadius` is `0`, THE `SbsProcessor` SHALL skip the blur jobs and leave the pixel shift map unchanged.
7. THE `SbsProcessor` SHALL compute the inverse monotone map per row by: computing `u[x] = x - pixelShifts[y, x]`, enforcing monotonicity via cumulative maximum, and linearly interpolating to produce `shifted_x[x]`.
8. THE `SbsProcessor` SHALL apply a cumulative maximum to `shifted_x` along each row before bilinear sampling to guarantee monotone source coordinates.
9. THE `SbsProcessor` SHALL bilinear-sample the input texture at the computed `shifted_x` coordinates to produce the warped left-eye image.
10. THE `SbsProcessor` SHALL compose the SBS image in Parallel mode: the right half SHALL contain the original unmodified input image and the left half SHALL contain the warped image.
11. THE `SbsProcessor` SHALL compute the crop size as `cropSize = (int)(depthScale * 6) + (int)(depthOffset * 8)` and fill the corresponding rectangle at the seam with black pixels using a Burst Job.
12. WHEN `ConversionRequest.Symmetric` is `true`, THE `SbsProcessor` SHALL perform a second pass with negated `depthScaleLocal` to produce the right-eye warp and SHALL fill a second crop rectangle symmetrically.
13. WHEN `ConversionRequest.SwitchSides` is `true`, THE `SbsProcessor` SHALL swap the left and right halves of the SBS image after all other processing is complete.
14. THE `SbsProcessor` SHALL implement all per-row operations (inverse monotone map, subpixel warp, SBS composition, rectangle fill) as `IJobParallelFor` Burst Jobs.

---

### Requirement 4: Resource Management

**User Story:** As a Unity developer, I want all unmanaged resources to be deterministically released, so that the application does not leak memory or GPU resources across repeated conversions.

#### Acceptance Criteria

1. THE `SbsConverterComponent` SHALL call `SbsConverterApi.Dispose` in its `OnDestroy` method.
2. THE `SbsConverterApi.Dispose` SHALL call `DepthEstimator.Dispose`.
3. THE `DepthEstimator.Dispose` SHALL release the Sentis `IWorker` instance.
4. THE `SbsProcessor` SHALL allocate all `NativeArray` instances within `try` blocks and dispose them in the corresponding `finally` blocks, regardless of whether the conversion succeeds or fails.
5. THE `DepthEstimator` SHALL release all intermediate `RenderTexture` objects created during preprocessing and postprocessing after each call to `EstimateDepthAsync`.
6. THE `SbsProcessor` SHALL release all intermediate `RenderTexture` objects created during SBS composition after each call to `Process`.
7. WHEN `ConvertAsync` is called and an exception is thrown at any stage, THE `SbsConverterApi` SHALL ensure that all `NativeArray` instances and `RenderTexture` objects allocated during that call are released before the exception propagates.

---

### Requirement 5: ONNX Model Bundling and Build Process

**User Story:** As a build engineer, I want the ONNX model to be exported from PyTorch at build time and bundled into the APK, so that no model download or Python runtime is needed at runtime.

#### Acceptance Criteria

1. THE `native/convert_to_onnx.py` script SHALL export the `depth-anything/Depth-Anything-V2-Small-hf` model to ONNX opset 17 with input name `"pixel_values"`, output name `"predicted_depth"`, and a dynamic batch axis.
2. THE `native/convert_to_onnx.py` script SHALL place the exported file at `Assets/StreamingAssets/Models/depth_anything_v2_small.onnx`.
3. THE `native/build.ps1` script SHALL check whether `Assets/StreamingAssets/Models/depth_anything_v2_small.onnx` exists and SHALL run `convert_to_onnx.py` only if the file is absent (idempotent behavior).
4. THE `native/build.ps1` script SHALL invoke the Unity Android build after the ONNX export step completes.
5. THE `native/test.ps1` script SHALL invoke Unity in batch mode with `-runTests -testPlatform EditMode` and SHALL write results to `test-results.xml`.
6. THE `SBS_Converter` SHALL NOT call `System.Diagnostics.Process.Start` or any equivalent mechanism to launch external processes at runtime.
7. THE `SBS_Converter` SHALL NOT make any network requests at runtime.

---

### Requirement 6: Unity Package Dependencies

**User Story:** As a Unity developer, I want the library to declare its Unity package dependencies explicitly, so that the project can be set up reproducibly on any development machine.

#### Acceptance Criteria

1. THE project manifest SHALL declare a dependency on `com.unity.sentis` at version `1.4` or higher.
2. THE project manifest SHALL declare a dependency on `com.unity.burst` at version `1.8` or higher.
3. THE project manifest SHALL declare a dependency on `com.unity.collections` at version `2.x` or higher.
4. THE project manifest SHALL declare a dependency on `com.unity.jobs` at version `0.70` or higher.
5. THE project manifest SHALL declare a dependency on `com.unity.mathematics` at version `1.3` or higher.

---

### Requirement 7: Logging

**User Story:** As a developer, I want structured log output at appropriate severity levels, so that I can diagnose issues during development and in production without relying on stdout or stderr.

#### Acceptance Criteria

1. WHEN the ONNX model is successfully loaded, THE `DepthEstimator` SHALL emit a `LogInformation` message that includes the model file path.
2. WHEN a conversion completes successfully, THE `SbsConverterApi` SHALL emit a `LogInformation` message that includes the output resolution and elapsed time.
3. WHEN the GPU backend is unavailable and the CPU fallback is activated, THE `DepthEstimator` SHALL emit a `LogWarning` message.
4. WHEN a `NativeArray` disposal failure is detected, THE `SbsProcessor` SHALL emit a `LogWarning` message.
5. WHEN the ONNX model file is not found, THE `DepthEstimator` SHALL emit a `LogError` message before throwing.
6. WHEN Sentis inference fails, THE `SbsConverterApi` SHALL emit a `LogError` message before returning the failure `ConversionResult`.
7. WHEN `ConvertAsync` is called, THE `DepthEstimator` SHALL emit a `LogDebug` message containing the Sentis inference duration, and THE `SbsProcessor` SHALL emit a `LogDebug` message containing the duration of each Burst Job stage.

---

### Requirement 8: EditMode Test Coverage

**User Story:** As a developer, I want a suite of Unity EditMode tests that validate the core algorithmic components, so that regressions are caught before building the APK.

#### Acceptance Criteria

1. THE `DepthEstimatorTests` SHALL include a test that verifies `EstimateDepthAsync` returns a depth map whose every pixel value is in the range `[0, 1]`.
2. THE `DepthEstimatorTests` SHALL include a test that verifies the output depth map has the same width and height as the input texture.
3. THE `SbsProcessorTests` SHALL include a test that verifies the SBS output width equals twice the input width.
4. THE `SbsProcessorTests` SHALL include a test that verifies the SBS output height equals the input height.
5. THE `SbsProcessorTests` SHALL include a test that verifies `BlurRadius == 0` leaves the pixel shift map unchanged.
6. THE `SbsProcessorTests` SHALL include a test that verifies `Symmetric == true` produces left-half and right-half pixel shifts that are equal in magnitude and opposite in sign.
7. THE `SbsProcessorTests` SHALL include a test that verifies `SwitchSides == true` swaps the left and right halves of the SBS output.
8. THE test suite SHALL include a synthetic test image at `Assets/Tests/EditMode/SbsConverter/TestAssets/test_input.png` with dimensions 320×200.
