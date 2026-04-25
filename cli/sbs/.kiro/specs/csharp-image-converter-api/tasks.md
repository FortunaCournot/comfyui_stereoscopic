# Implementation Plan: C# Image Converter API (Unity/Android)

## Overview

Implement a pure C# Unity library that replaces the Python depth-estimation and SBS-conversion pipeline. The library runs on Android, uses Unity Sentis for on-device ONNX inference, and Unity Jobs + Burst for parallel SBS processing. All code and comments must be in English.

## Tasks

- [ ] 1. Set up Unity project structure and package manifest
  - Create the folder layout under `Assets/Scripts/SbsConverter/`, `Assets/Tests/EditMode/SbsConverter/TestAssets/`, and `Assets/StreamingAssets/Models/`
  - Create `Packages/manifest.json` declaring all five required dependencies:
    - `com.unity.sentis` ≥ 1.4
    - `com.unity.burst` ≥ 1.8
    - `com.unity.collections` ≥ 2.x
    - `com.unity.jobs` ≥ 0.70
    - `com.unity.mathematics` ≥ 1.3
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [ ] 2. Define core public types in `IImageConverter.cs`
  - [ ] 2.1 Create `Assets/Scripts/SbsConverter/IImageConverter.cs`
    - Define `ConversionRequest` sealed record with fields: `InputTexture`, `Model`, `DepthScale`, `DepthOffset`, `BlurRadius`, `Symmetric`, `SwitchSides`
    - Define `ConversionResult` sealed record with fields: `Success`, `ExitCode`, `OutputTexture`
    - Define `IImageConverter` interface with `ConvertAsync(ConversionRequest, CancellationToken)` returning `Task<ConversionResult>`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [ ] 2.2 Create `Assets/Scripts/SbsConverter/SbsConverterOptions.cs`
    - Define `SbsConverterOptions` sealed record with fields: `OnnxModelPath` (default `"Models/depth_anything_v2_small.onnx"`), `InferenceBackend` (default `BackendType.GPUCompute`), `ModelInputSize` (default `518`)
    - _Requirements: 2.1, 2.5, 2.11_

- [ ] 3. Implement the ONNX export script
  - [ ] 3.1 Create `native/convert_to_onnx.py`
    - Export `depth-anything/Depth-Anything-V2-Small-hf` to ONNX opset 17
    - Input name `"pixel_values"`, shape `[1, 3, 518, 518]`; output name `"predicted_depth"`; dynamic batch axis on `pixel_values`
    - Write output to `Assets/StreamingAssets/Models/depth_anything_v2_small.onnx`
    - _Requirements: 5.1, 5.2_

- [ ] 4. Implement `DepthEstimator`
  - [ ] 4.1 Create `Assets/Scripts/SbsConverter/DepthEstimator/DepthEstimator.cs` — skeleton and `LoadModelAsync`
    - Constructor accepts `SbsConverterOptions` and `ILogger<DepthEstimator>`
    - `LoadModelAsync`: build full path from `Application.streamingAssetsPath + OnnxModelPath`; use `UnityWebRequest` on Android to read bytes; call `ModelLoader.Load` then `WorkerFactory.CreateWorker`; emit `LogInformation` on success; throw `FileNotFoundException` and emit `LogError` when file is absent; lazy-init guard so model loads at most once
    - Implement `IDisposable`: dispose `IWorker` in `Dispose()`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.11, 4.3, 7.1, 7.5_

  - [ ] 4.2 Implement `EstimateDepthAsync` in `DepthEstimator.cs`
    - Resize input to `ModelInputSize × ModelInputSize` via `Graphics.Blit` into a temporary `RenderTexture`
    - Apply ImageNet normalization (mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]`) and build float32 NCHW tensor `[1, 3, 518, 518]` named `"pixel_values"`
    - Run Sentis inference; read output tensor `"predicted_depth"`
    - Bicubic-resize output back to original input resolution
    - Min-max normalize to `[0, 1]` using `(depth - min) / (max - min + 1e-6)`
    - Return `Texture2D` in `RFloat` format at original resolution
    - Release all intermediate `RenderTexture` objects after each call
    - GPU→CPU fallback: catch unavailable GPU backend, emit `LogWarning`, retry with `BackendType.CPU`
    - Emit `LogDebug` with Sentis inference duration
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 4.5, 7.3, 7.7_

  - [ ]* 4.3 Write property test for depth map normalization (Property 3)
    - **Property 3: Depth map is normalized**
    - For any input `Texture2D`, every pixel value in the `EstimateDepthAsync` output SHALL be in `[0, 1]`
    - **Validates: Requirements 2.9, 2.10, 8.1**

  - [ ]* 4.4 Write property test for depth map resolution (Property 4)
    - **Property 4: Depth map resolution matches input**
    - For any input `Texture2D` of size `W × H`, the output of `EstimateDepthAsync` SHALL have width `W` and height `H`
    - **Validates: Requirements 2.10, 8.2**

  - [ ]* 4.5 Write EditMode unit tests in `Assets/Tests/EditMode/SbsConverter/DepthEstimatorTests.cs`
    - Test: `EstimateDepthAsync` returns depth map where every pixel is in `[0, 1]` (Req 8.1)
    - Test: output depth map has same width and height as input texture (Req 8.2)
    - Use a synthetic 320×200 color-gradient `Texture2D` generated programmatically
    - _Requirements: 8.1, 8.2_

- [ ] 5. Checkpoint — Ensure DepthEstimator tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement Burst Jobs for SBS processing
  - [ ] 6.1 Create `Assets/Scripts/SbsConverter/SbsProcessor/ComputeShiftsJob.cs`
    - `[BurstCompile] struct ComputeShiftsJob : IJobParallelFor`
    - Fields: `[ReadOnly] NativeArray<float> DepthMap`, `[WriteOnly] NativeArray<float> PixelShifts`, `float DepthScaleLocal`, `float DepthOffsetLocal`, `int Width`
    - `Execute(int i)`: invert depth (`1.0f - depth[i]`), scale to `[0,255]` and center (`* 255f - 128f`), compute `pixelShifts[i] = depth_np * depthScaleLocal + depthOffsetLocal`
    - _Requirements: 3.1, 3.2, 3.3_

  - [ ] 6.2 Create `Assets/Scripts/SbsConverter/SbsProcessor/BoxBlurJob.cs`
    - `[BurstCompile] struct BoxBlurHorizontalJob : IJobParallelFor` — horizontal separable box blur pass
    - `[BurstCompile] struct BoxBlurVerticalJob : IJobParallelFor` — vertical separable box blur pass
    - Both jobs operate on `NativeArray<float>` shift maps; kernel size = `BlurRadius`
    - _Requirements: 3.5, 3.6_

  - [ ] 6.3 Create `Assets/Scripts/SbsConverter/SbsProcessor/ApplySubpixelShiftJob.cs`
    - `[BurstCompile] struct ApplySubpixelShiftJob : IJobParallelFor` — one row per job index
    - Per row: compute `u[x] = x - pixelShifts[y, x]`; enforce monotonicity via cumulative max; linear-interpolate to produce `shifted_x[x]`; apply second cumulative max to `shifted_x`; bilinear-sample `BaseImage` at `(shifted_x[x], y)` and write to `SbsImage`
    - Fields: `[ReadOnly] NativeArray<Color32> BaseImage`, `[ReadOnly] NativeArray<float> PixelShifts`, `[WriteOnly] NativeArray<Color32> SbsImage`, `int Width`, `int Height`, `int FlipOffset`
    - _Requirements: 3.7, 3.8, 3.9, 3.10_

  - [ ] 6.4 Create `Assets/Scripts/SbsConverter/SbsProcessor/FillRectJob.cs`
    - `[BurstCompile] struct FillRectJob : IJobParallelFor` — fill black crop rectangle at seam
    - Compute `cropSize = (int)(depthScale * 6) + (int)(depthOffset * 8)`; fill corresponding rectangle with black pixels
    - _Requirements: 3.11_

- [ ] 7. Implement `SbsProcessor`
  - [ ] 7.1 Create `Assets/Scripts/SbsConverter/SbsProcessor/SbsProcessor.cs`
    - `Process(Texture2D baseImage, Texture2D depthMap, float depthScale, float depthOffset, int blurRadius, bool symmetric, bool switchSides)` returns `Texture2D`
    - Allocate all `NativeArray` instances inside `try` blocks; dispose in `finally` blocks
    - Compute `depthScaleLocal` and `depthOffsetLocal`; apply symmetric halving and `invertDepth` negation when `Symmetric == true`
    - Schedule `ComputeShiftsJob`; conditionally schedule `BoxBlurHorizontalJob` + `BoxBlurVerticalJob` only when `blurRadius > 0`; schedule `ApplySubpixelShiftJob`; schedule `FillRectJob`
    - Compose SBS image: right half = original, left half = warped (Parallel mode)
    - When `Symmetric == true`: perform second pass with negated `depthScaleLocal`, fill second crop rectangle symmetrically
    - When `SwitchSides == true`: swap left and right halves after all other processing
    - Emit `LogDebug` with duration of each Burst Job stage
    - Release all intermediate `RenderTexture` objects after each call
    - _Requirements: 3.1–3.14, 4.4, 4.6, 7.4, 7.7_

  - [ ]* 7.2 Write property test for SBS output dimensions (Property 2)
    - **Property 2: SBS output dimensions**
    - For any successful conversion, `OutputTexture.width` SHALL equal `InputTexture.width * 2` and `OutputTexture.height` SHALL equal `InputTexture.height`
    - **Validates: Requirements 1.8, 3.1 (height), 8.3, 8.4**

  - [ ]* 7.3 Write property test for symmetric shifts (Property 5)
    - **Property 5: Symmetric flag produces mirrored shifts**
    - For any depth map with `Symmetric == true`, left-eye and right-eye pixel shifts SHALL be equal in magnitude and opposite in sign at every pixel position
    - **Validates: Requirements 3.4, 3.12, 8.6**

  - [ ]* 7.4 Write property test for blur invariant (Property 6)
    - **Property 6: Blur invariant**
    - For any pixel shift map, when `BlurRadius == 0`, blur jobs SHALL NOT execute and shift values SHALL be identical before and after the blur step
    - **Validates: Requirements 3.6, 8.5**

  - [ ]* 7.5 Write property test for SwitchSides (Property 7)
    - **Property 7: SwitchSides swaps halves**
    - For any SBS image produced with `SwitchSides == false`, applying `SwitchSides == true` to the same input SHALL produce an image where left half equals original right half and right half equals original left half
    - **Validates: Requirements 3.13, 8.7**

  - [ ]* 7.6 Write EditMode unit tests in `Assets/Tests/EditMode/SbsConverter/SbsProcessorTests.cs`
    - Test: SBS output width equals twice the input width (Req 8.3)
    - Test: SBS output height equals the input height (Req 8.4)
    - Test: `BlurRadius == 0` leaves pixel shift map unchanged (Req 8.5)
    - Test: `Symmetric == true` produces left-half and right-half shifts equal in magnitude and opposite in sign (Req 8.6)
    - Test: `SwitchSides == true` swaps left and right halves (Req 8.7)
    - Test: all `NativeArray` instances are disposed after `Process` returns
    - Use a synthetic 320×200 color-gradient `Texture2D` generated programmatically
    - _Requirements: 8.3, 8.4, 8.5, 8.6, 8.7_

- [ ] 8. Checkpoint — Ensure SbsProcessor tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Implement `SbsConverterApi`
  - [ ] 9.1 Create `Assets/Scripts/SbsConverter/SbsConverterApi.cs`
    - Constructor accepts `SbsConverterOptions` and `ILogger<SbsConverterApi>`; instantiates `DepthEstimator` and `SbsProcessor`
    - `ValidateRequest`: throw `ArgumentNullException` when `InputTexture` is null; throw `ArgumentOutOfRangeException` when `BlurRadius < 0`
    - `ConvertAsync`: lazy `LoadModelAsync` on first call; call `EstimateDepthAsync`; call `SbsProcessor.Process`; return `ConversionResult { Success=true, ExitCode=0 }`; emit `LogInformation` with output resolution and elapsed time
    - Catch all exceptions from inference/processing: emit `LogError`; return `ConversionResult { Success=false, ExitCode=-1, OutputTexture=null }`; ensure all `NativeArray` and `RenderTexture` resources are released
    - Propagate `OperationCanceledException` when `CancellationToken` is cancelled
    - Implement `IDisposable`: call `DepthEstimator.Dispose()`
    - _Requirements: 1.1–1.8, 4.2, 4.7, 7.2, 7.6_

  - [ ]* 9.2 Write property test for ConvertAsync always returns a result (Property 1)
    - **Property 1: ConvertAsync always returns a result**
    - For any valid `ConversionRequest` (non-null `InputTexture`), `ConvertAsync` SHALL return a non-null `ConversionResult` and SHALL NOT throw an unhandled exception
    - **Validates: Requirements 1.2, 1.4**

  - [ ]* 9.3 Write property test for native resource cleanup (Property 8)
    - **Property 8: Native resources are always released**
    - For any `ConvertAsync` call — success, exception, or cancellation — all `NativeArray` and `RenderTexture` objects allocated during that call SHALL be disposed before the call returns or the exception propagates
    - **Validates: Requirements 4.4, 4.5, 4.6, 4.7**

- [ ] 10. Implement `SbsConverterComponent`
  - Create `Assets/Scripts/SbsConverter/SbsConverterComponent.cs`
  - `MonoBehaviour` with `[SerializeField] SbsConverterOptions _options`
  - `Awake`: instantiate `SbsConverterApi` with `_options` and a Unity logger
  - `OnDestroy`: call `(_converter as IDisposable)?.Dispose()`
  - Public `ConvertAsync(Texture2D, float, float, int, bool)` wrapper that constructs a `ConversionRequest` and delegates to `SbsConverterApi.ConvertAsync`
  - _Requirements: 1.1, 4.1_

- [ ] 11. Create build and test scripts
  - [ ] 11.1 Create `native/build.ps1`
    - Check whether `Assets/StreamingAssets/Models/depth_anything_v2_small.onnx` exists; run `convert_to_onnx.py` only if absent (idempotent)
    - After ONNX export, invoke Unity Android build via `-batchmode -buildTarget Android -executeMethod BuildScript.BuildAndroid`
    - _Requirements: 5.3, 5.4_

  - [ ] 11.2 Create `native/test.ps1`
    - Invoke Unity in batch mode with `-runTests -testPlatform EditMode -testResults test-results.xml`
    - _Requirements: 5.5_

- [ ] 12. Add synthetic test asset
  - Generate `Assets/Tests/EditMode/SbsConverter/TestAssets/test_input.png` — a 320×200 color-gradient image created programmatically in a Unity Editor script or test setup
  - _Requirements: 8.8_

- [ ] 13. Final checkpoint — Ensure all tests pass
  - Run `native/test.ps1` (or Unity Test Runner `-runTests -testPlatform EditMode`)
  - Ensure all EditMode tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at logical boundaries
- Property tests (Properties 1–8) validate universal correctness guarantees; unit tests validate specific examples and edge cases
- All `NativeArray` allocations must be in `try/finally` blocks — this is enforced by the compiler in Burst Jobs but must be manually ensured in orchestration code
- The ONNX model (~100 MB) is not committed to source control; `build.ps1` generates it on first build
