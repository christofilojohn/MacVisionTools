#!/usr/bin/env python3
"""Export TensorFlow SSD MobileNet V2 COCO to Core ML.

The default source is TensorFlow's public TF2 Object Detection Model Zoo
archive for `ssd_mobilenet_v2_320x320_coco17_tpu-8`.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tarfile
import urllib.request
from pathlib import Path


MODEL_NAME = "ssd_mobilenet_v2_320x320_raw"
TF_ARCHIVE_NAME = "ssd_mobilenet_v2_320x320_coco17_tpu-8"
TF_ARCHIVE_URL = (
    "https://storage.googleapis.com/download.tensorflow.org/models/object_detection/tf2/20200711/"
    f"{TF_ARCHIVE_NAME}.tar.gz"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-url", default=TF_ARCHIVE_URL)
    parser.add_argument("--work-dir", default="build/model-export")
    parser.add_argument("--output", default=f"src/Models/{MODEL_NAME}.mlmodel")
    parser.add_argument("--compiled-output", default=f"src/Models/{MODEL_NAME}.mlmodelc")
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--skip-compile", action="store_true")
    return parser.parse_args()


def download(url: str, destination: Path) -> None:
    if destination.exists():
        print(f"Using cached archive: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    with urllib.request.urlopen(url) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def extract(archive: Path, destination: Path) -> Path:
    model_dir = destination / TF_ARCHIVE_NAME
    if model_dir.exists():
        print(f"Using extracted model: {model_dir}")
        return model_dir
    print(f"Extracting {archive}")
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        tar.extractall(destination)
    return model_dir


def convert(saved_model_dir: Path, output: Path) -> None:
    import coremltools as ct
    import numpy as np
    from coremltools.converters.mil.frontend.tensorflow.tf_op_registry import _TF_OPS_REGISTRY
    from coremltools.converters.mil.mil import Builder as mb
    from coremltools.converters.mil.mil import types
    from coremltools.converters.mil.mil.ops.defs.iOS15 import tensor_transformation

    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        shutil.rmtree(output) if output.is_dir() else output.unlink()

    def reshape_with_integral_dims(value, shape):
        normalized_shape = []
        for dim in shape:
            if isinstance(dim, (float, np.floating)) and float(dim).is_integer():
                normalized_shape.append(int(dim))
            elif types.symbolic.is_symbolic(dim):
                normalized_shape.append(dim)
            else:
                normalized_shape.append(int(dim))
        return np.array(value).reshape(normalized_shape)

    tensor_transformation.reshape_with_symbol = reshape_with_integral_dims

    def cast_with_bool(context, node):
        type_map = {
            types.fp16: "fp16",
            types.float: "fp32",
            types.double: "fp32",
            types.int32: "int32",
            types.int64: "int32",
            types.bool: "bool",
        }
        if node.attr["DstT"] not in type_map:
            raise NotImplementedError(
                f"Cast: unsupported destination type {types.get_type_info(node.attr['DstT'])}"
            )
        x = context[node.inputs[0]]
        x = mb.cast(x=x, dtype=type_map[node.attr["DstT"]], name=node.name)
        context.add(node.name, x)

    _TF_OPS_REGISTRY["Cast"] = cast_with_bool

    image_input = ct.ImageType(
        name="input_tensor",
        shape=(1, 320, 320, 3),
        scale=1.0,
        color_layout=ct.colorlayout.RGB,
    )
    outputs = [
        ct.TensorType(name="Identity_6"),
        ct.TensorType(name="Identity_7"),
    ]

    print(f"Converting SavedModel: {saved_model_dir}")
    model = ct.convert(
        str(saved_model_dir),
        source="tensorflow",
        convert_to="neuralnetwork",
        inputs=[image_input],
        outputs=outputs,
        minimum_deployment_target=ct.target.iOS14,
        compute_units=ct.ComputeUnit.ALL,
    )

    spec = model.get_spec()
    ct.models.utils.rename_feature(spec, "Identity_6", "raw_detection_boxes")
    ct.models.utils.rename_feature(spec, "Identity_7", "raw_detection_scores")
    model = ct.models.MLModel(spec, compute_units=ct.ComputeUnit.ALL)

    model.short_description = "SSD MobileNet V2 raw object detector trained on COCO 2017"
    model.author = "TensorFlow Model Garden"
    model.license = "Apache-2.0"
    model.user_defined_metadata.update(
        {
            "source": TF_ARCHIVE_URL,
            "task": "detect",
            "classes": "COCO 2017",
            "input_size": "320x320",
            "outputs": "raw_detection_boxes,raw_detection_scores",
        }
    )

    print(f"Saving Core ML model: {output}")
    model.save(str(output))


def compile_model(model_path: Path, compiled_output: Path) -> None:
    if compiled_output.exists():
        shutil.rmtree(compiled_output)

    print(f"Compiling Core ML model: {model_path}")
    subprocess.run(
        [
            "xcrun",
            "coremlcompiler",
            "compile",
            str(model_path),
            str(compiled_output.parent),
            "--add-mlprogram-if-eligible",
            "disable",
        ],
        check=True,
    )
    generated_output = compiled_output.parent / f"{model_path.stem}.mlmodelc"
    if generated_output != compiled_output:
        if compiled_output.exists():
            shutil.rmtree(compiled_output)
        shutil.move(generated_output, compiled_output)

    metadata = {
        "source_model": str(model_path),
        "source_url": TF_ARCHIVE_URL,
        "license": "Apache-2.0",
        "classes": "COCO 2017",
    }
    (compiled_output / "export_metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Wrote compiled model: {compiled_output}")


def main() -> None:
    args = parse_args()
    work_dir = Path(args.work_dir)
    archive = work_dir / f"{TF_ARCHIVE_NAME}.tar.gz"

    if not args.skip_download:
        download(args.model_url, archive)
    model_dir = extract(archive, work_dir)
    saved_model_dir = model_dir / "saved_model"
    if not saved_model_dir.exists():
        raise FileNotFoundError(f"Missing SavedModel directory: {saved_model_dir}")

    output = Path(args.output)
    convert(saved_model_dir, output)

    if not args.skip_compile:
        compile_model(output, Path(args.compiled_output))


if __name__ == "__main__":
    main()
