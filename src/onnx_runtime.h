/**
 * Generic ONNX Runtime C wrapper — float tensor in/out, single input/output.
 * No model-specific preprocessing (softmax, mel, etc.) — callers own that.
 */
#ifndef ONNX_LOADER_RUNTIME_H
#define ONNX_LOADER_RUNTIME_H

/** Bump when Julian needs to confirm a rebuilt .so is loaded. */
#define ONNX_LOADER_BUILD "named-tensor-profiler-20260901b"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OnnxRuntime OnnxRuntime;

#define ONNX_LOADER_MAX_RANK 8

typedef struct OnnxTensorDescriptor {
	const char *name;
	int element_type;
	int rank;
	int64_t dimensions[ONNX_LOADER_MAX_RANK];
	int flat_size;
} OnnxTensorDescriptor;

/** Load model.onnx; introspects I/O float tensor element counts (batch=1). */
OnnxRuntime *onnx_runtime_create(const char *model_onnx_path);
/** Create a session with ONNX Runtime JSON profiling enabled. */
OnnxRuntime *onnx_runtime_create_profiled(const char *model_onnx_path,
					  const char *profile_file_prefix);
/** Flush profiling and copy its generated JSON path into out_path. May be called once. */
int onnx_runtime_end_profiling(OnnxRuntime *rt, char *out_path, int out_path_cap);

void onnx_runtime_destroy(OnnxRuntime *rt);

/** Same as destroy — RefCounted drop must release the session, not leak it. */
void onnx_runtime_drop(OnnxRuntime *rt);

/** Release shared ORT env (GDExtension module terminator / process exit). */
void onnx_runtime_shutdown(void);

const char *onnx_runtime_ort_version(void);
/** Resolved filesystem path of the libonnxruntime loaded for this process. */
const char *onnx_runtime_ort_library_path(void);
uint32_t onnx_runtime_ort_api_version(void);
const char *onnx_runtime_input_name(const OnnxRuntime *rt);
const char *onnx_runtime_output_name(const OnnxRuntime *rt);
int onnx_runtime_input_count(const OnnxRuntime *rt);
int onnx_runtime_output_count(const OnnxRuntime *rt);
int onnx_runtime_input_descriptor(const OnnxRuntime *rt, int index, OnnxTensorDescriptor *out);
int onnx_runtime_output_descriptor(const OnnxRuntime *rt, int index, OnnxTensorDescriptor *out);
int onnx_runtime_set_input_f32(OnnxRuntime *rt, const char *name, const float *data, int data_len,
			       const int64_t *shape, int shape_len);
int onnx_runtime_run(OnnxRuntime *rt, const char *const *output_names, int output_count);
int onnx_runtime_has_output(const OnnxRuntime *rt, const char *name);
int onnx_runtime_output_data_f32(const OnnxRuntime *rt, const char *name, float *output,
				 int output_cap, int *output_len_out);
int onnx_runtime_output_slice_f32(const OnnxRuntime *rt, const char *name, int offset, int count,
				  float *output);
int onnx_runtime_output_shape(const OnnxRuntime *rt, const char *name, int64_t *shape,
			      int shape_cap, int *shape_len_out);
uint64_t onnx_runtime_run_generation(const OnnxRuntime *rt);
const char *onnx_runtime_last_error(const OnnxRuntime *rt);

/** Flat input length must match onnx_runtime_input_size(). */
int onnx_runtime_predict(const OnnxRuntime *rt, const float *input, int input_len,
			 float *output, int output_cap, int *output_len_out);

int onnx_runtime_input_size(const OnnxRuntime *rt);
int onnx_runtime_output_size(const OnnxRuntime *rt);

/**
 * Shaped predict for dynamic-time models (e.g. TCN [1,T,F] → [1,T,C]).
 * shape_len dims in shape[]; input_len must match product(shape).
 * Writes up to output_cap floats; sets *output_len_out.
 */
int onnx_runtime_predict_shaped(const OnnxRuntime *rt, const float *input, int input_len,
				const int64_t *shape, int shape_len, float *output, int output_cap,
				int *output_len_out);

/**
 * Copy custom model metadata value for key into buf (NUL-terminated).
 * Returns 0 on success, 1 if missing/error. Truncates if longer than buf_len-1.
 */
int onnx_runtime_metadata_get(const OnnxRuntime *rt, const char *key, char *buf, int buf_len);

/**
 * Fill keys_out[0..*count_out) with custom metadata key names (each <= key_buf_len-1).
 * keys_storage must hold count_cap * key_buf_len bytes (row-major).
 * Returns 0 on success.
 */
int onnx_runtime_metadata_keys(const OnnxRuntime *rt, char *keys_storage, int count_cap,
			       int key_buf_len, int *count_out);

#ifdef __cplusplus
}
#endif

#endif /* ONNX_LOADER_RUNTIME_H */
