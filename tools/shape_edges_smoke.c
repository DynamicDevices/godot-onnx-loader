#include "onnx_runtime.h"

#include <limits.h>
#include <stdio.h>

static int scalar_test(const char *path)
{
	OnnxRuntime *rt = onnx_runtime_create(path);
	OnnxTensorDescriptor input;
	float value = 3.5f;
	float result = 0.0f;
	int written = 0;
	int rank = -1;
	if (!rt || onnx_runtime_input_descriptor(rt, 0, &input) || input.rank != 0 ||
	    input.flat_size != 1 || onnx_runtime_set_input_f32(rt, "scalar", &value, 1, NULL, 0) ||
	    onnx_runtime_run(rt, NULL, 0) ||
	    onnx_runtime_output_shape(rt, "result", NULL, 0, &rank) || rank != 0 ||
	    onnx_runtime_output_data_f32(rt, "result", &result, 1, &written) || written != 1 ||
	    result != value) {
		fprintf(stderr, "scalar contract failed: %s\n", onnx_runtime_last_error(rt));
		onnx_runtime_destroy(rt);
		return -1;
	}
	onnx_runtime_destroy(rt);
	return 0;
}

static int dynamic_test(const char *path)
{
	OnnxRuntime *rt = onnx_runtime_create(path);
	float values[24] = {0};
	const int64_t shape[] = {2, 3, 4};
	const int64_t zero_shape[] = {2, 0, 4};
	const int64_t overflow_shape[] = {INT32_MAX, 2, 4};
	int64_t output_shape[3] = {0};
	int rank = 0;
	if (!rt || onnx_runtime_input_size(rt) != -1 ||
	    onnx_runtime_set_input_f32(rt, "dynamic", values, 24, shape, 3) ||
	    onnx_runtime_run(rt, NULL, 0) ||
	    onnx_runtime_output_shape(rt, "result", output_shape, 3, &rank) || rank != 3 ||
	    output_shape[0] != 2 || output_shape[1] != 3 || output_shape[2] != 4 ||
	    onnx_runtime_set_input_f32(rt, "dynamic", values, 24, zero_shape, 3) == 0 ||
	    onnx_runtime_set_input_f32(rt, "dynamic", values, 24, overflow_shape, 3) == 0) {
		fprintf(stderr, "dynamic/invalid/overflow contract failed: %s\n",
			onnx_runtime_last_error(rt));
		onnx_runtime_destroy(rt);
		return -1;
	}
	onnx_runtime_destroy(rt);
	return 0;
}

static int selected_output_test(const char *path)
{
	OnnxRuntime *rt = onnx_runtime_create(path);
	float values[4] = {1, 2, 3, 4};
	const int64_t shape[] = {1, 4};
	const char *negative[] = {"negative"};
	const char *missing[] = {"missing"};
	if (!rt || onnx_runtime_set_input_f32(rt, "input", values, 4, shape, 2) ||
	    onnx_runtime_run(rt, negative, 1) || !onnx_runtime_has_output(rt, "negative") ||
	    onnx_runtime_has_output(rt, "identity") || onnx_runtime_run(rt, NULL, 0) ||
	    !onnx_runtime_has_output(rt, "identity") || !onnx_runtime_has_output(rt, "negative") ||
	    onnx_runtime_run(rt, missing, 1) == 0 || onnx_runtime_has_output(rt, "identity") ||
	    onnx_runtime_has_output(rt, "negative")) {
		fprintf(stderr, "selected/stale output contract failed: %s\n",
			onnx_runtime_last_error(rt));
		onnx_runtime_destroy(rt);
		return -1;
	}
	onnx_runtime_destroy(rt);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 4) return 2;
	if (scalar_test(argv[1]) || dynamic_test(argv[2]) || selected_output_test(argv[3])) return 1;
	onnx_runtime_shutdown();
	printf("ONNX_SHAPE_EDGES_OK scalar=1 dynamic_dims=2 selected_outputs=2 stale_invalidated=1\n");
	return 0;
}
