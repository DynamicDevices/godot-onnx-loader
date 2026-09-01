#!/usr/bin/env python3
"""Generate the minimal model used to explain the Godot OnnxLoader interface.

The graph deliberately performs visible elementary arithmetic rather than a
domain-specific task. It accepts `matrix: float32[4,2]` and
`vector: float32[3]`, reduces the matrix over its four rows, reduces the vector
to one scalar, broadcasts that scalar over the two column totals, and returns
`output: float32[2]`::

    output = reduce_sum(matrix, axis=0) + reduce_sum(vector)

The accompanying Godot scene exposes every input and output as editor-defined
SpinBox controls. It is intended as a small project users can modify to preview
another ONNX graph before deciding whether to adopt ONNX in a larger project.
"""
from pathlib import Path

import onnx
from onnx import TensorProto, helper


def main() -> None:
    matrix = helper.make_tensor_value_info("matrix", TensorProto.FLOAT, [4, 2])
    vector = helper.make_tensor_value_info("vector", TensorProto.FLOAT, [3])
    output = helper.make_tensor_value_info("output", TensorProto.FLOAT, [2])
    graph = helper.make_graph(
        [
            helper.make_node("ReduceSum", ["matrix"], ["column_sums"], axes=[0], keepdims=0),
            helper.make_node("ReduceSum", ["vector"], ["vector_sum"], axes=[0], keepdims=0),
            helper.make_node("Add", ["column_sums", "vector_sum"], ["output"]),
        ],
        "matrix_plus_vector_sum",
        [matrix, vector],
        [output],
    )
    model = helper.make_model(graph, producer_name="godot-onnx-loader", opset_imports=[helper.make_opsetid("", 11)])
    model.ir_version = 8
    model.metadata_props.add(key="formula", value="output = reduce_sum(matrix, axis=0) + reduce_sum(vector)")
    onnx.checker.check_model(model)
    path = Path(__file__).resolve().parents[1] / "demo" / "models" / "matrix_vector.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(model, path)
    print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
