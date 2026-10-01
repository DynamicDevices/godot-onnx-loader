#!/usr/bin/env python3
"""Generate tiny models proving the loader rejects unsupported tensor types clearly."""

from pathlib import Path

import onnx
from onnx import TensorProto, helper


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "fixtures" / "hardening" / "types"
TYPES = {
    "float16": TensorProto.FLOAT16,
    "float64": TensorProto.DOUBLE,
    "int32": TensorProto.INT32,
    "int64": TensorProto.INT64,
    "bool": TensorProto.BOOL,
}


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, element_type in TYPES.items():
        value_in = helper.make_tensor_value_info("input", element_type, [1, 4])
        value_out = helper.make_tensor_value_info("output", element_type, [1, 4])
        graph = helper.make_graph(
            [helper.make_node("Identity", ["input"], ["output"])],
            f"unsupported_{name}_contract",
            [value_in],
            [value_out],
        )
        model = helper.make_model(
            graph,
            producer_name="godot-onnx-loader",
            opset_imports=[helper.make_opsetid("", 13)],
        )
        model.ir_version = 8
        onnx.checker.check_model(model)
        path = OUTPUT / f"{name}.onnx"
        onnx.save(model, path)
        print(f"TYPE_FIXTURE_OK type={name} path={path} bytes={path.stat().st_size}")

    # A syntactically valid model whose custom operator has no registered kernel.
    value_in = helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, 4])
    value_out = helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 4])
    graph = helper.make_graph(
        [
            helper.make_node(
                "DefinitelyUnsupported", ["input"], ["output"], domain="com.dynamicdevices.test"
            )
        ],
        "unsupported_operator_contract",
        [value_in],
        [value_out],
    )
    model = helper.make_model(
        graph,
        producer_name="godot-onnx-loader",
        opset_imports=[
            helper.make_opsetid("", 13),
            helper.make_opsetid("com.dynamicdevices.test", 1),
        ],
    )
    model.ir_version = 8
    onnx.checker.check_model(model)
    path = OUTPUT.parent / "unsupported_operator.onnx"
    onnx.save(model, path)
    print(f"OPERATOR_FIXTURE_OK path={path} bytes={path.stat().st_size}")


if __name__ == "__main__":
    main()
