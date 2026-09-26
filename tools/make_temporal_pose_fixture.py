#!/usr/bin/env python3
"""Generate a redistributable dynamic temporal fixture; no third-party weights."""

from pathlib import Path

import onnx
from onnx import TensorProto, helper


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "fixtures" / "hardening" / "temporal_pose.onnx"


def i64(name: str, values: list[int]):
    return helper.make_tensor(name, TensorProto.INT64, [len(values)], values)


def main() -> None:
    input_info = helper.make_tensor_value_info(
        "motion_history", TensorProto.FLOAT, [1, "frames", 36]
    )
    output_info = helper.make_tensor_value_info(
        "pose_features", TensorProto.FLOAT, [1, 135]
    )
    graph = helper.make_graph(
        [
            helper.make_node("Flatten", ["motion_history"], ["flat"], axis=1),
            helper.make_node(
                "Slice",
                ["flat", "starts", "ends", "axes", "steps"],
                ["pose_features"],
            ),
        ],
        "redistributable_temporal_pose_contract",
        [input_info],
        [output_info],
        initializer=[
            i64("starts", [0]),
            i64("ends", [135]),
            i64("axes", [1]),
            i64("steps", [1]),
        ],
    )
    model = helper.make_model(
        graph,
        producer_name="godot-onnx-loader",
        opset_imports=[helper.make_opsetid("", 13)],
    )
    model.ir_version = 8
    metadata = {
        "onnx_loader.contract_version": "1",
        "onnx_loader.input.motion_history.axes": "batch,time,feature",
        "onnx_loader.input.motion_history.units": "unitless_rotation_like_features",
        "onnx_loader.input.motion_history.normalization": "fixture values are unnormalized",
        "onnx_loader.input.motion_history.feature_order": "36 synthetic rotation-like channels",
        "onnx_loader.input.motion_history.frame_rate_hz": "30",
        "onnx_loader.output.pose_features.axes": "batch,feature",
        "onnx_loader.output.pose_features.units": "unitless_pose_features",
        "onnx_loader.output.pose_features.feature_order": "135 synthetic pose channels",
    }
    for key, value in metadata.items():
        entry = model.metadata_props.add()
        entry.key = key
        entry.value = value
    onnx.checker.check_model(model)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(model, OUTPUT)
    print(f"TEMPORAL_POSE_FIXTURE_OK path={OUTPUT} bytes={OUTPUT.stat().st_size}")


if __name__ == "__main__":
    main()
