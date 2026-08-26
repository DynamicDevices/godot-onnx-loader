/**
 * Generic ONNX Runtime C wrapper — float tensor in/out, single input/output.
 * No model-specific preprocessing (softmax, mel, etc.) — callers own that.
 */
#ifndef ONNX_LOADER_RUNTIME_H
#define ONNX_LOADER_RUNTIME_H

/** Bump when Julian needs to confirm a rebuilt .so is loaded. */
#define ONNX_LOADER_BUILD "opts-eager-20260826b"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OnnxRuntime OnnxRuntime;

/** Load model.onnx; introspects I/O float tensor element counts (batch=1). */
OnnxRuntime *onnx_runtime_create(const char *model_onnx_path);

void onnx_runtime_destroy(OnnxRuntime *rt);

/** Release shared ORT env (GDExtension module terminator / process exit). */
void onnx_runtime_shutdown(void);

const char *onnx_runtime_ort_version(void);
uint32_t onnx_runtime_ort_api_version(void);
const char *onnx_runtime_input_name(const OnnxRuntime *rt);
const char *onnx_runtime_output_name(const OnnxRuntime *rt);

/** Flat input length must match onnx_runtime_input_size(). */
int onnx_runtime_predict(const OnnxRuntime *rt, const float *input, int input_len,
			 float *output, int output_cap, int *output_len_out);

int onnx_runtime_input_size(const OnnxRuntime *rt);
int onnx_runtime_output_size(const OnnxRuntime *rt);

#ifdef __cplusplus
}
#endif

#endif /* ONNX_LOADER_RUNTIME_H */
