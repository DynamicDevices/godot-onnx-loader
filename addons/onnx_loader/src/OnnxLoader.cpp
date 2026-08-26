#include "OnnxLoader.hpp"

#include <godot_cpp/core/class_db.hpp>

OnnxLoader::OnnxLoader() = default;

OnnxLoader::~OnnxLoader()
{
	if (rt) {
		onnx_runtime_destroy(rt);
		rt = nullptr;
	}
}

void OnnxLoader::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("load_model", "model_onnx_path"), &OnnxLoader::load_model);
	ClassDB::bind_method(D_METHOD("unload_model"), &OnnxLoader::unload_model);
	ClassDB::bind_method(D_METHOD("predict", "input_data"), &OnnxLoader::predict);
	ClassDB::bind_method(D_METHOD("predict_array", "input_data"), &OnnxLoader::predict_array);
	ClassDB::bind_method(D_METHOD("get_input_size"), &OnnxLoader::get_input_size);
	ClassDB::bind_method(D_METHOD("get_output_size"), &OnnxLoader::get_output_size);
	ClassDB::bind_method(D_METHOD("get_diagnostics"), &OnnxLoader::get_diagnostics);
}

bool OnnxLoader::load_model(const String &model_onnx_path)
{
	unload_model();
	CharString path = model_onnx_path.utf8();
	rt = onnx_runtime_create(path.get_data());
	return rt != nullptr;
}

void OnnxLoader::unload_model()
{
	if (rt) {
		onnx_runtime_destroy(rt);
		rt = nullptr;
	}
}

PackedFloat32Array OnnxLoader::predict(const PackedFloat32Array &input)
{
	PackedFloat32Array out;
	if (!rt) {
		return out;
	}
	int out_n = onnx_runtime_output_size(rt);
	if ((int)input.size() != onnx_runtime_input_size(rt) || out_n <= 0) {
		return out;
	}
	out.resize(out_n);
	int written = 0;
	if (onnx_runtime_predict(rt, input.ptr(), (int)input.size(), out.ptrw(), out_n,
				 &written) != 0 ||
	    written != out_n) {
		out.clear();
	}
	return out;
}

Array OnnxLoader::predict_array(const Array &input_data)
{
	PackedFloat32Array flat;
	flat.resize(input_data.size());
	for (int i = 0; i < input_data.size(); i++) {
		flat[i] = (float)input_data[i];
	}
	PackedFloat32Array logits = predict(flat);
	Array out;
	for (int i = 0; i < logits.size(); i++) {
		out.append(logits[i]);
	}
	return out;
}

int OnnxLoader::get_input_size() const
{
	return rt ? onnx_runtime_input_size(rt) : 0;
}

int OnnxLoader::get_output_size() const
{
	return rt ? onnx_runtime_output_size(rt) : 0;
}

Dictionary OnnxLoader::get_diagnostics() const
{
	Dictionary d;
	d["loader_build"] = String(ONNX_LOADER_BUILD);
	d["ort_version"] = String(onnx_runtime_ort_version());
	d["ort_api_version"] = (int64_t)onnx_runtime_ort_api_version();
	if (rt) {
		d["model_loaded"] = true;
		d["input_size"] = get_input_size();
		d["output_size"] = get_output_size();
		d["input_name"] = String(onnx_runtime_input_name(rt));
		d["output_name"] = String(onnx_runtime_output_name(rt));
	} else {
		d["model_loaded"] = false;
	}
	return d;
}
