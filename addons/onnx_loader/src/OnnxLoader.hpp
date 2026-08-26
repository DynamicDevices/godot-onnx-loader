#pragma once

#include "onnx_runtime.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

/** mat490-style generic ONNX loader: load_model(path) + predict(float[]). */
class OnnxLoader : public RefCounted {
	GDCLASS(OnnxLoader, RefCounted)

	OnnxRuntime *rt = nullptr;

protected:
	static void _bind_methods();

public:
	OnnxLoader();
	~OnnxLoader() override;

	bool load_model(const String &model_onnx_path);
	PackedFloat32Array predict(const PackedFloat32Array &input);
	Array predict_array(const Array &input_data);

	int get_input_size() const;
	int get_output_size() const;
};
