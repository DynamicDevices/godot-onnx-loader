#pragma once

#include "onnx_runtime.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
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
	void unload_model();
	PackedFloat32Array predict(const PackedFloat32Array &input);
	Array predict_array(const Array &input_data);

	int get_input_size() const;
	int get_output_size() const;
	Dictionary get_diagnostics() const;
	/** Custom ONNX metadata_props as String→String (empty if none / unload). */
	Dictionary get_model_metadata() const;
	String get_metadata_value(const String &key) const;
	Array get_input_descriptors() const;
	Array get_output_descriptors() const;
	bool set_input(const String &name, const PackedFloat32Array &data,
			const PackedInt64Array &shape);
	bool run(const PackedStringArray &output_names = PackedStringArray());
	bool has_output(const String &name) const;
	PackedFloat32Array get_output(const String &name) const;
	PackedFloat32Array get_output_slice(const String &name, int64_t offset, int64_t count) const;
	float get_output_scalar(const String &name, int64_t index = 0) const;
	PackedInt64Array get_output_shape(const String &name) const;
	int64_t get_run_generation() const;
	String get_last_error() const;
	/**
	 * Shaped predict: e.g. shape [1, T, F] for TCN. Returns flat output
	 * (T*n_visemes for [1,T,C]). Empty on failure.
	 */
	PackedFloat32Array predict_shaped(const PackedFloat32Array &input, const PackedInt32Array &shape);
};
