#include "OnnxLoader.hpp"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

OnnxLoader::OnnxLoader() = default;

OnnxLoader::~OnnxLoader()
{
	unload_model();
}

void OnnxLoader::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("load_model", "model_onnx_path"), &OnnxLoader::load_model);
	ClassDB::bind_method(D_METHOD("load_model_profiled", "model_onnx_path", "profile_file_prefix"),
			&OnnxLoader::load_model_profiled);
	ClassDB::bind_method(D_METHOD("end_profiling"), &OnnxLoader::end_profiling);
	ClassDB::bind_method(D_METHOD("unload_model"), &OnnxLoader::unload_model);
	ClassDB::bind_method(D_METHOD("predict", "input_data"), &OnnxLoader::predict);
	ClassDB::bind_method(D_METHOD("predict_array", "input_data"), &OnnxLoader::predict_array);
	ClassDB::bind_method(D_METHOD("get_input_size"), &OnnxLoader::get_input_size);
	ClassDB::bind_method(D_METHOD("get_output_size"), &OnnxLoader::get_output_size);
	ClassDB::bind_method(D_METHOD("get_diagnostics"), &OnnxLoader::get_diagnostics);
	ClassDB::bind_method(D_METHOD("get_model_metadata"), &OnnxLoader::get_model_metadata);
	ClassDB::bind_method(D_METHOD("get_metadata_value", "key"), &OnnxLoader::get_metadata_value);
	ClassDB::bind_method(D_METHOD("get_input_descriptors"), &OnnxLoader::get_input_descriptors);
	ClassDB::bind_method(D_METHOD("get_output_descriptors"), &OnnxLoader::get_output_descriptors);
	ClassDB::bind_method(D_METHOD("set_input", "name", "data", "shape"), &OnnxLoader::set_input);
	ClassDB::bind_method(D_METHOD("run", "output_names"), &OnnxLoader::run,
			DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("has_output", "name"), &OnnxLoader::has_output);
	ClassDB::bind_method(D_METHOD("get_output", "name"), &OnnxLoader::get_output);
	ClassDB::bind_method(D_METHOD("get_output_slice", "name", "offset", "count"),
			&OnnxLoader::get_output_slice);
	ClassDB::bind_method(D_METHOD("get_output_scalar", "name", "index"),
			&OnnxLoader::get_output_scalar, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_output_shape", "name"), &OnnxLoader::get_output_shape);
	ClassDB::bind_method(D_METHOD("get_run_generation"), &OnnxLoader::get_run_generation);
	ClassDB::bind_method(D_METHOD("get_last_error"), &OnnxLoader::get_last_error);
	ClassDB::bind_method(D_METHOD("predict_shaped", "input_data", "shape"),
			&OnnxLoader::predict_shaped);
}

bool OnnxLoader::load_model(const String &model_onnx_path)
{
	unload_model();
	String resolved_path = model_onnx_path;
	if (model_onnx_path.begins_with("res://") || model_onnx_path.begins_with("user://")) {
		resolved_path = ProjectSettings::get_singleton()->globalize_path(model_onnx_path);
	}
	CharString path = resolved_path.utf8();
	rt = onnx_runtime_create(path.get_data());
	return rt != nullptr;
}

bool OnnxLoader::load_model_profiled(const String &model_onnx_path,
		const String &profile_file_prefix)
{
	unload_model();
	String resolved_model = model_onnx_path;
	String resolved_prefix = profile_file_prefix;
	if (model_onnx_path.begins_with("res://") || model_onnx_path.begins_with("user://"))
		resolved_model = ProjectSettings::get_singleton()->globalize_path(model_onnx_path);
	if (profile_file_prefix.begins_with("res://") || profile_file_prefix.begins_with("user://"))
		resolved_prefix = ProjectSettings::get_singleton()->globalize_path(profile_file_prefix);
	CharString model_path = resolved_model.utf8();
	CharString prefix = resolved_prefix.utf8();
	rt = onnx_runtime_create_profiled(model_path.get_data(), prefix.get_data());
	return rt != nullptr;
}

String OnnxLoader::end_profiling()
{
	if (!rt) return String();
	char path[4096];
	if (onnx_runtime_end_profiling(rt, path, sizeof(path))) return String();
	return String::utf8(path);
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
	d["ort_library_path"] = String(onnx_runtime_ort_library_path());
	d["ort_api_version"] = (int64_t)onnx_runtime_ort_api_version();
	if (rt) {
		d["model_loaded"] = true;
		d["input_size"] = get_input_size();
		d["output_size"] = get_output_size();
		d["input_name"] = String(onnx_runtime_input_name(rt));
		d["output_name"] = String(onnx_runtime_output_name(rt));
		d["input_count"] = onnx_runtime_input_count(rt);
		d["output_count"] = onnx_runtime_output_count(rt);
		d["run_generation"] = get_run_generation();
		d["last_error"] = get_last_error();
	} else {
		d["model_loaded"] = false;
	}
	return d;
}

static Dictionary descriptor_dictionary(const OnnxTensorDescriptor &desc)
{
	Dictionary d;
	d["name"] = String(desc.name);
	d["element_type"] = desc.element_type;
	d["data_type"] = String("float32");
	d["rank"] = desc.rank;
	d["flat_size"] = desc.flat_size;
	PackedInt64Array shape;
	shape.resize(desc.rank);
	for (int i = 0; i < desc.rank; i++) shape[i] = desc.dimensions[i];
	d["shape"] = shape;
	return d;
}

Array OnnxLoader::get_input_descriptors() const
{
	Array result;
	for (int i = 0; rt && i < onnx_runtime_input_count(rt); i++) {
		OnnxTensorDescriptor desc;
		if (onnx_runtime_input_descriptor(rt, i, &desc) == 0)
			result.append(descriptor_dictionary(desc));
	}
	return result;
}

Array OnnxLoader::get_output_descriptors() const
{
	Array result;
	for (int i = 0; rt && i < onnx_runtime_output_count(rt); i++) {
		OnnxTensorDescriptor desc;
		if (onnx_runtime_output_descriptor(rt, i, &desc) == 0)
			result.append(descriptor_dictionary(desc));
	}
	return result;
}

bool OnnxLoader::set_input(const String &name, const PackedFloat32Array &data,
		const PackedInt64Array &shape)
{
	if (!rt || shape.size() > ONNX_LOADER_MAX_RANK) return false;
	CharString input_name = name.utf8();
	return onnx_runtime_set_input_f32(rt, input_name.get_data(), data.ptr(), data.size(),
			shape.ptr(), shape.size()) == 0;
}

bool OnnxLoader::run(const PackedStringArray &output_names)
{
	if (!rt || output_names.size() > 32) return false;
	const char *names[32];
	CharString encoded[32];
	for (int i = 0; i < output_names.size(); i++) {
		encoded[i] = output_names[i].utf8();
		names[i] = encoded[i].get_data();
	}
	return onnx_runtime_run(rt, output_names.is_empty() ? nullptr : names,
			output_names.size()) == 0;
}

bool OnnxLoader::has_output(const String &name) const
{
	if (!rt) return false;
	CharString n = name.utf8();
	return onnx_runtime_has_output(rt, n.get_data()) != 0;
}

PackedInt64Array OnnxLoader::get_output_shape(const String &name) const
{
	PackedInt64Array shape;
	if (!rt) return shape;
	CharString n = name.utf8();
	int64_t dims[ONNX_LOADER_MAX_RANK];
	int rank = 0;
	if (onnx_runtime_output_shape(rt, n.get_data(), dims, ONNX_LOADER_MAX_RANK, &rank)) return shape;
	shape.resize(rank);
	for (int i = 0; i < rank; i++) shape[i] = dims[i];
	return shape;
}

PackedFloat32Array OnnxLoader::get_output(const String &name) const
{
	PackedFloat32Array result;
	PackedInt64Array shape = get_output_shape(name);
	int64_t count = 1;
	for (int i = 0; i < shape.size(); i++) count *= shape[i];
	if (!rt || count < 0 || count > INT32_MAX) return result;
	result.resize((int)count);
	CharString n = name.utf8();
	int written = 0;
	if (onnx_runtime_output_data_f32(rt, n.get_data(), result.ptrw(), result.size(), &written)) {
		result.clear();
	} else {
		result.resize(written);
	}
	return result;
}

PackedFloat32Array OnnxLoader::get_output_slice(const String &name, int64_t offset,
		int64_t count) const
{
	PackedFloat32Array result;
	if (!rt || offset < 0 || count < 0 || offset > INT32_MAX || count > INT32_MAX) return result;
	result.resize((int)count);
	CharString n = name.utf8();
	if (onnx_runtime_output_slice_f32(rt, n.get_data(), (int)offset, (int)count, result.ptrw()))
		result.clear();
	return result;
}

float OnnxLoader::get_output_scalar(const String &name, int64_t index) const
{
	PackedFloat32Array value = get_output_slice(name, index, 1);
	return value.is_empty() ? 0.0f : value[0];
}

int64_t OnnxLoader::get_run_generation() const
{
	return rt ? (int64_t)onnx_runtime_run_generation(rt) : 0;
}

String OnnxLoader::get_last_error() const
{
	return String(onnx_runtime_last_error(rt));
}

Dictionary OnnxLoader::get_model_metadata() const
{
	Dictionary d;
	if (!rt) {
		return d;
	}
	constexpr int k_cap = 128;
	constexpr int k_len = 128;
	char keys[k_cap * k_len];
	int count = 0;
	if (onnx_runtime_metadata_keys(rt, keys, k_cap, k_len, &count) != 0) {
		return d;
	}
	for (int i = 0; i < count; i++) {
		const char *key = keys + i * k_len;
		if (!key[0]) {
			continue;
		}
		/* vizemes_meta_json can be multi-KB; 64KiB headroom */
		char val[65536];
		if (onnx_runtime_metadata_get(rt, key, val, (int)sizeof(val)) == 0) {
			d[String(key)] = String(val);
		}
	}
	return d;
}

String OnnxLoader::get_metadata_value(const String &key) const
{
	if (!rt) {
		return String();
	}
	CharString k = key.utf8();
	char val[65536];
	if (onnx_runtime_metadata_get(rt, k.get_data(), val, (int)sizeof(val)) != 0) {
		return String();
	}
	return String(val);
}

PackedFloat32Array OnnxLoader::predict_shaped(const PackedFloat32Array &input,
		const PackedInt32Array &shape)
{
	PackedFloat32Array out;
	if (!rt || shape.is_empty()) {
		return out;
	}
	int64_t dims[8];
	if (shape.size() > 8) {
		return out;
	}
	int64_t need = 1;
	for (int i = 0; i < shape.size(); i++) {
		dims[i] = shape[i];
		if (dims[i] <= 0) {
			return out;
		}
		need *= dims[i];
	}
	if ((int64_t)input.size() != need) {
		return out;
	}
	int cap = (int)(need > 4096 ? need * 16 : 4096);
	if (cap < 4096) {
		cap = 4096;
	}
	out.resize(cap);
	int written = 0;
	if (onnx_runtime_predict_shaped(rt, input.ptr(), (int)input.size(), dims, shape.size(),
					out.ptrw(), cap, &written) != 0 ||
	    written <= 0) {
		out.clear();
		return out;
	}
	out.resize(written);
	return out;
}
