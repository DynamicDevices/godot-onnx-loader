#include "onnx_runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "onnxruntime_c_api.h"

#define ONNX_NAME_MAX 128

struct OnnxRuntime {
	const OrtApi *ort;
	OrtSessionOptions *opts;
	OrtSession *session;
	char input_name[ONNX_NAME_MAX];
	char output_name[ONNX_NAME_MAX];
	int input_size;
	int output_size;
};

static const OrtApi *g_ort;
static OrtEnv *g_env;
static int g_env_users;

#define DEFERRED_MAX 64
static OnnxRuntime *g_deferred[DEFERRED_MAX];
static int g_deferred_n;

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

static const OrtApi *ort_api(void)
{
	if (g_ort) {
		return g_ort;
	}
	const OrtApiBase *base = OrtGetApiBase();
	if (!base) {
		fprintf(stderr, "OrtGetApiBase failed\n");
		return NULL;
	}
	g_ort = base->GetApi(ORT_API_VERSION);
	if (!g_ort) {
		fprintf(stderr, "ORT GetApi failed\n");
	}
	return g_ort;
}

static int ort_env_use(void)
{
	const OrtApi *ort = ort_api();
	if (!ort) {
		return -1;
	}
	if (g_env_users == 0) {
		if (ort_fail(ort, ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "onnx_loader", &g_env),
			     "CreateEnv")) {
			return -1;
		}
	}
	g_env_users++;
	return 0;
}

static void ort_env_unuse(void)
{
	if (g_env_users <= 0) {
		return;
	}
	g_env_users--;
}

static void copy_io_name(char *dst, size_t dst_cap, const char *src)
{
	if (!dst || dst_cap == 0) {
		return;
	}
	if (!src) {
		dst[0] = '\0';
		return;
	}
	snprintf(dst, dst_cap, "%s", src);
}

static void release_ort_string(const OrtApi *ort, OrtAllocator *alloc, char *s)
{
	if (!ort || !alloc || !s) {
		return;
	}
	OrtStatus *st = ort->AllocatorFree(alloc, s);
	if (st) {
		ort->ReleaseStatus(st);
	}
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

	const OrtApi *ort = ort_api();
	if (!ort || ort_env_use() != 0) {
		return NULL;
	}

	OnnxRuntime *rt = (OnnxRuntime *)calloc(1, sizeof(*rt));
	if (!rt) {
		ort_env_unuse();
		return NULL;
	}
	rt->ort = ort;

	OrtAllocator *allocator = NULL;
	char *tmp_in = NULL;
	char *tmp_out = NULL;

	if (ort_fail(ort, ort->CreateSessionOptions(&rt->opts), "CreateSessionOptions") ||
	    ort_fail(ort, ort->CreateSession(g_env, model_onnx_path, rt->opts, &rt->session),
		     "CreateSession") ||
	    ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(ort, ort->SessionGetInputName(rt->session, 0, allocator, &tmp_in),
		     "GetInputName") ||
	    ort_fail(ort, ort->SessionGetOutputName(rt->session, 0, allocator, &tmp_out),
		     "GetOutputName")) {
		onnx_runtime_destroy(rt);
		return NULL;
	}

	copy_io_name(rt->input_name, sizeof(rt->input_name), tmp_in);
	copy_io_name(rt->output_name, sizeof(rt->output_name), tmp_out);
	release_ort_string(ort, allocator, tmp_in);
	release_ort_string(ort, allocator, tmp_out);

	if (rt->input_name[0] == '\0' || rt->output_name[0] == '\0' ||
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
	if (ort) {
		if (rt->session) {
			ort->ReleaseSession(rt->session);
			rt->session = NULL;
		}
		if (rt->opts) {
			ort->ReleaseSessionOptions(rt->opts);
			rt->opts = NULL;
		}
	}
	ort_env_unuse();
	rt->ort = NULL;
	free(rt);
}

void onnx_runtime_destroy_deferred(OnnxRuntime *rt)
{
	if (!rt) {
		return;
	}
	if (g_deferred_n >= DEFERRED_MAX) {
		onnx_runtime_destroy(rt);
		return;
	}
	g_deferred[g_deferred_n++] = rt;
}

void onnx_runtime_shutdown(void)
{
	while (g_deferred_n > 0) {
		onnx_runtime_destroy(g_deferred[--g_deferred_n]);
	}
	const OrtApi *ort = g_ort;
	if (g_env_users != 0) {
		fprintf(stderr, "onnx_runtime_shutdown: %d live session(s)\n", g_env_users);
	}
	if (ort && g_env) {
		ort->ReleaseEnv(g_env);
		g_env = NULL;
	}
	g_env_users = 0;
	g_ort = NULL;
}

const char *onnx_runtime_ort_version(void)
{
	const OrtApiBase *base = OrtGetApiBase();
	if (!base || !base->GetVersionString) {
		return "unknown";
	}
	return base->GetVersionString();
}

uint32_t onnx_runtime_ort_api_version(void)
{
	return (uint32_t)ORT_API_VERSION;
}

const char *onnx_runtime_input_name(const OnnxRuntime *rt)
{
	return rt ? rt->input_name : "";
}

const char *onnx_runtime_output_name(const OnnxRuntime *rt)
{
	return rt ? rt->output_name : "";
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
		     ort->CreateCpuMemoryInfo(OrtDeviceAllocator, OrtMemTypeDefault, &mem),
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
