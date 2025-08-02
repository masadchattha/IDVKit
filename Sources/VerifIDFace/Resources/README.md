# VerifIDFace model resources

The face-matching step loads `VIDFaceEmbedding.mlpackage` from this directory via
`Bundle.module` (SPM compiles it to `VIDFaceEmbedding.mlmodelc` at build time).

## Model contract (see `VIDFaceMatcher.ModelSpec`)

- Input feature `input_image`: `[1, 3, 112, 112]` NCHW Float32.
- Output feature `embedding`: a 128-D face-embedding vector.
- Pixel normalization: pixels scaled to [0, 1], then per-channel
  `mean = [0.485, 0.456, 0.406]`, `std = [0.229, 0.224, 0.225]` (ImageNet).

If a different model is bundled, update `ModelSpec` in `VIDFaceMatcher.swift` to
match its feature names, input size, embedding size, and normalization.

## Current model

`VIDFaceEmbedding.mlpackage` — a MobileFaceNet (128-D embedding). **Requires
iOS 18+** (the compiled ML Program targets iOS 18); on older systems
`VIDFaceMatcher` throws `modelLoadFailed` and face matching is skipped, while
document + NFC verification continue to work.
