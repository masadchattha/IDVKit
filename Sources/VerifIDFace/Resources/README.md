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

`VIDFaceEmbedding.mlpackage` — a MobileFaceNet (128-D embedding) reused from the
Votari app. **Requires iOS 18+** (the compiled ML Program targets iOS 18); on
older systems `VIDFaceMatcher` throws `modelLoadFailed` and face matching is
skipped, while document + NFC verification continue to work.

## ⚠️ Licensing — resolve before public release

This SDK is MIT-licensed. The bundled model's **weights/training-data provenance
is not documented** — this must be verified (or the model replaced with one whose
weights + training data permit commercial redistribution) before publishing.
Research summary of clean options: OpenCV-Zoo **SFace** (Apache-2.0 on the weights
file) or a MobileFaceNet trained on self-rendered synthetic data. Record the final
model's name, source, and license here before shipping.
