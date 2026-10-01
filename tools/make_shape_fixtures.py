#!/usr/bin/env python3
"""Generate scalar, multiple-dynamic-dimension, and selected-output fixtures."""

from pathlib import Path

import onnx
from onnx import TensorProto, helper


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "fixtures" / "hardening"


def save(name: str, graph) -> None:
    model = helper.make_model(
        graph,
        producer_name="godot-onnx-loader",
        opset_imports=[helper.make_opsetid("", 13)],
    )
    model.ir_version = 8
    onnx.checker.check_model(model)
    path = OUTPUT / name
    onnx.save(model, path)
    print(f"SHAPE_FIXTURE_OK path={path} bytes={path.stat().st_size}")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    scalar_in = helper.make_tensor_value_info("scalar", TensorProto.FLOAT, [])
    scalar_out = helper.make_tensor_value_info("result", TensorProto.FLOAT, [])
    save(
        "scalar.onnx",
        helper.make_graph(
            [helper.make_node("Identity", ["scalar"], ["result"])],
            "scalar_contract",
            [scalar_in],
            [scalar_out],
        ),
    )

    dynamic_in = helper.make_tensor_value_info(
        "dynamic", TensorProto.FLOAT, ["batch", "frames", 4]
    )
    dynamic_out = helper.make_tensor_value_info(
        "result", TensorProto.FLOAT, ["batch", "frames", 4]
    )
    save(
        "multi_dynamic.onnx",
        helper.make_graph(
            [helper.make_node("Identity", ["dynamic"], ["result"])],
            "multiple_dynamic_dimensions_contract",
            [dynamic_in],
            [dynamic_out],
        ),
    )

    selected_in = helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, 4])
    first_out = helper.make_tensor_value_info("identity", TensorProto.FLOAT, [1, 4])
    second_out = helper.make_tensor_value_info("negative", TensorProto.FLOAT, [1, 4])
    save(
        "multi_output.onnx",
        helper.make_graph(
            [
                helper.make_node("Identity", ["input"], ["identity"]),
                helper.make_node("Neg", ["input"], ["negative"]),
            ],
            "selected_outputs_contract",
            [selected_in],
            [first_out, second_out],
        ),
    )


if __name__ == "__main__":
    main()
