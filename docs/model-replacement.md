# Replacing YOLO With SSD MobileNet V2

The App Store-oriented detector should avoid bundling the Ultralytics YOLO model because it is licensed under AGPL-3.0 unless you obtain an Ultralytics enterprise license. The replacement path in this repo uses TensorFlow's SSD MobileNet V2 COCO detector, a small mobile object detector from the TensorFlow model family.

## Model Choice

| Model | Task | Classes | License | Why |
| --- | --- | --- | --- | --- |
| SSD MobileNet V2 320x320 raw Core ML export | Object detection | COCO 2017 | Apache-2.0 | Fast, small, permissive, includes `person` for Privacy Guard |

This preserves the two object-detection app workflows:

- Standard Detection: draws detected object boxes and labels.
- Privacy Guard: counts `person` detections and starts the macOS screen saver when the configured privacy threshold is reached.

## Export

Create an isolated Python 3.11 environment with the tested TensorFlow/CoreMLTools versions, then run:

```sh
python3.11 -m venv .venv-coreml
. .venv-coreml/bin/activate
python -m pip install -r tools/requirements-coreml-export.txt
python tools/export_ssd_mobilenet_coreml.py
```

The export writes:

- `src/Models/ssd_mobilenet_v2_320x320_raw.mlmodel`
- `src/Models/ssd_mobilenet_v2_320x320_raw.mlmodelc`

The app looks for the compiled `.mlmodelc` bundle at runtime.

## App Integration

`BundledModel.suggested(for:)` now points Standard Detection and Privacy Guard to `ssd_mobilenet_v2_320x320_raw.mlmodelc`.

The shipped Core ML model stops at SSD raw outputs and lets the app do thresholding and non-maximum suppression in Swift. This avoids bundling TensorFlow's large postprocess graph and keeps the compiled Core ML artifact small enough to ship.

`DetectionManager` supports Vision-native `VNRecognizedObjectObservation` results, TensorFlow SSD postprocessed feature outputs, and raw SSD feature outputs:

- `detection_boxes`
- `detection_scores`
- `detection_classes`
- `num_detections`
- `raw_detection_boxes`
- `raw_detection_scores`

TensorFlow SSD boxes use `[ymin, xmin, ymax, xmax]`; the app converts them to Vision-style normalized rectangles with a lower-left origin.
