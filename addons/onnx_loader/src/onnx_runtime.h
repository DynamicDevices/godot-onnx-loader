/**
 * Generic ONNX Runtime C wrapper — float tensor in/out, single input/output.
 * No model-specific preprocessing (softmax, mel, etc.) — callers own that.
 */
#ifndef ONNX_LOADER_RUNTIME_H
#define ONNX_LOADER_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OnnxRuntime OnnxRuntime;

/** Load model.onnx; introspects I/O float tensor element counts (batch=1). */
OnnxRuntime *onnx_runtime_create(const char *model_onnx_path);

void onnx_runtime_destroy(OnnxRuntime *rt);

/** Flat input length must match onnx_runtime_input_size(). */
int onnx_runtime_predict(const OnnxRuntime *rt, const float *input, int input_len,
			 float *output, int output_cap, int *output_len_out);

int onnx_runtime_input_size(const OnnxRuntime *rt);
int onnx_runtime_output_size(const OnnxRuntime *rt);

#ifdef __cplusplus
}
#endif

#endif /* ONNX_LOADER_RUNTIME_H */
