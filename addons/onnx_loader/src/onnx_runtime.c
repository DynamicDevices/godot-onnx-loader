#include "onnx_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "onnxruntime_c_api.h"

struct OnnxRuntime {
	const OrtApi *ort;
	OrtEnv *env;
	OrtSessionOptions *opts;
	OrtSession *session;
	OrtAllocator *allocator;
	char *input_name;
	char *output_name;
	int input_size;
	int output_size;
};

static int ort_fail(const OrtApi *ort, OrtStatus *st, const char *what)
{
	if (!st) {
		return 0;
	}
	const char *msg = ort->GetErrorMessage(st);
	fprintf(stderr, "ORT %s: %s\n", what, msg ? msg : "(null)");
	ort->ReleaseStatus(st);
	return -1;
}

/** ORT-allocated I/O names must not outlive the session; keep our own copies. */
static char *copy_ort_name(const OrtApi *ort, OrtAllocator *alloc, char *ort_name)
{
	if (!ort_name) {
		return NULL;
	}
	size_t n = strlen(ort_name) + 1;
	char *copy = (char *)malloc(n);
	if (!copy) {
		OrtStatus *st = ort->AllocatorFree(alloc, ort_name);
		if (st) {
			ort->ReleaseStatus(st);
		}
		return NULL;
	}
	memcpy(copy, ort_name, n);
	OrtStatus *st = ort->AllocatorFree(alloc, ort_name);
	if (st) {
		ort->ReleaseStatus(st);
	}
	return copy;
}

static int64_t shape_elements(const int64_t *shape, size_t rank, int64_t batch)
{
	int64_t n = batch;
	for (size_t i = 0; i < rank; i++) {
		int64_t d = shape[i];
		if (d <= 0) {
			if (i == 0) {
				d = batch;
			} else {
				fprintf(stderr, "unsupported dynamic dim at axis %zu\n", i);
				return -1;
			}
		}
		n *= d;
	}
	return n;
}

static int tensor_float_elements(const OrtApi *ort, OrtSession *session,
				 int is_input, int index, int *out_count)
{
	OrtTypeInfo *type_info = NULL;
	const OrtTensorTypeAndShapeInfo *tensor_info = NULL;
	size_t rank = 0;
	int64_t *shape = NULL;
	int rc = -1;

	if (is_input) {
		if (ort_fail(ort, ort->SessionGetInputTypeInfo(session, (size_t)index, &type_info),
			     "SessionGetInputTypeInfo")) {
			goto done;
		}
	} else {
		if (ort_fail(ort, ort->SessionGetOutputTypeInfo(session, (size_t)index, &type_info),
			     "SessionGetOutputTypeInfo")) {
			goto done;
		}
	}

	if (ort_fail(ort, ort->CastTypeInfoToTensorInfo(type_info, &tensor_info),
		     "CastTypeInfoToTensorInfo") ||
	    ort_fail(ort, ort->GetDimensionsCount(tensor_info, &rank), "GetDimensionsCount") ||
	    rank == 0) {
		goto done;
	}

	shape = (int64_t *)calloc(rank, sizeof(int64_t));
	if (!shape) {
		goto done;
	}
	if (ort_fail(ort, ort->GetDimensions(tensor_info, shape, rank), "GetDimensions")) {
		goto done;
	}

	ONNXTensorElementDataType elem_type;
	if (ort_fail(ort, ort->GetTensorElementType(tensor_info, &elem_type),
		     "GetTensorElementType") ||
	    elem_type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
		fprintf(stderr, "only float32 tensors supported (got type %d)\n", (int)elem_type);
		goto done;
	}

	int64_t n = shape_elements(shape, rank, 1);
	if (n <= 0 || n > INT32_MAX) {
		fprintf(stderr, "invalid tensor element count\n");
		goto done;
	}
	*out_count = (int)n;
	rc = 0;

done:
	free(shape);
	if (type_info) {
		ort->ReleaseTypeInfo(type_info);
	}
	return rc;
}

OnnxRuntime *onnx_runtime_create(const char *model_onnx_path)
{
	if (!model_onnx_path) {
		return NULL;
	}

	const OrtApiBase *base = OrtGetApiBase();
	if (!base) {
		fprintf(stderr, "OrtGetApiBase failed\n");
		return NULL;
	}
	const OrtApi *ort = base->GetApi(ORT_API_VERSION);
	if (!ort) {
		fprintf(stderr, "ORT GetApi failed\n");
		return NULL;
	}

	OnnxRuntime *rt = (OnnxRuntime *)calloc(1, sizeof(*rt));
	if (!rt) {
		return NULL;
	}
	rt->ort = ort;

	if (ort_fail(ort, ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "onnx_loader", &rt->env),
		     "CreateEnv") ||
	    ort_fail(ort, ort->CreateSessionOptions(&rt->opts), "CreateSessionOptions") ||
	    ort_fail(ort, ort->CreateSession(rt->env, model_onnx_path, rt->opts, &rt->session),
		     "CreateSession") ||
	    ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&rt->allocator), "GetAllocator")) {
		onnx_runtime_destroy(rt);
		return NULL;
	}

	if (ort_fail(ort,
		     ort->SessionGetInputName(rt->session, 0, rt->allocator, &rt->input_name),
		     "GetInputName") ||
	    ort_fail(ort,
		     ort->SessionGetOutputName(rt->session, 0, rt->allocator, &rt->output_name),
		     "GetOutputName")) {
		onnx_runtime_destroy(rt);
		return NULL;
	}
	rt->input_name = copy_ort_name(ort, rt->allocator, rt->input_name);
	rt->output_name = copy_ort_name(ort, rt->allocator, rt->output_name);
	if (!rt->input_name || !rt->output_name ||
	    tensor_float_elements(ort, rt->session, 1, 0, &rt->input_size) != 0 ||
	    tensor_float_elements(ort, rt->session, 0, 0, &rt->output_size) != 0) {
		onnx_runtime_destroy(rt);
		return NULL;
	}

	return rt;
}

void onnx_runtime_destroy(OnnxRuntime *rt)
{
	if (!rt) {
		return;
	}
	const OrtApi *ort = rt->ort;
	free(rt->input_name);
	free(rt->output_name);
	rt->input_name = rt->output_name = NULL;
	if (ort) {
		if (rt->session) {
			ort->ReleaseSession(rt->session);
			rt->session = NULL;
		}
		if (rt->opts) {
			ort->ReleaseSessionOptions(rt->opts);
			rt->opts = NULL;
		}
		if (rt->env) {
			ort->ReleaseEnv(rt->env);
			rt->env = NULL;
		}
	}
	rt->ort = NULL;
	free(rt);
}

int onnx_runtime_input_size(const OnnxRuntime *rt)
{
	return rt ? rt->input_size : 0;
}

int onnx_runtime_output_size(const OnnxRuntime *rt)
{
	return rt ? rt->output_size : 0;
}

int onnx_runtime_predict(const OnnxRuntime *rt, const float *input, int input_len,
			 float *output, int output_cap, int *output_len_out)
{
	if (!rt || !input || !output || input_len != rt->input_size ||
	    output_cap < rt->output_size) {
		return -1;
	}

	const OrtApi *ort = rt->ort;
	OrtMemoryInfo *mem = NULL;
	OrtValue *in_tensor = NULL;
	OrtValue *out_tensor = NULL;
	int rc = -1;

	int64_t shape[2] = {1, (int64_t)rt->input_size};
	if (ort_fail(ort,
		     ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem),
		     "CreateCpuMemoryInfo") ||
	    ort_fail(ort,
		     ort->CreateTensorWithDataAsOrtValue(
			 mem, (void *)input, (size_t)input_len * sizeof(float), shape, 2,
			 ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &in_tensor),
		     "CreateTensor")) {
		goto done;
	}

	const char *in_names[] = {rt->input_name};
	const char *out_names[] = {rt->output_name};
	if (ort_fail(ort,
		     ort->Run(rt->session, NULL, in_names, (const OrtValue *const *)&in_tensor, 1,
			      out_names, 1, &out_tensor),
		     "Run")) {
		goto done;
	}

	float *out_data = NULL;
	if (ort_fail(ort, ort->GetTensorMutableData(out_tensor, (void **)&out_data),
		     "GetTensorData")) {
		goto done;
	}
	memcpy(output, out_data, (size_t)rt->output_size * sizeof(float));
	if (output_len_out) {
		*output_len_out = rt->output_size;
	}
	rc = 0;

done:
	if (out_tensor) {
		ort->ReleaseValue(out_tensor);
	}
	if (in_tensor) {
		ort->ReleaseValue(in_tensor);
	}
	if (mem) {
		ort->ReleaseMemoryInfo(mem);
	}
	return rc;
}
