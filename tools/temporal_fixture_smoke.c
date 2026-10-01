#include "onnx_runtime.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: temporal_fixture_smoke temporal_pose.onnx\n");
		return 2;
	}
	OnnxRuntime *rt = onnx_runtime_create(argv[1]);
	if (!rt) {
		fprintf(stderr, "temporal fixture load failed: %s\n", onnx_runtime_last_error(NULL));
		return 1;
	}
	OnnxTensorDescriptor input;
	OnnxTensorDescriptor output;
	if (onnx_runtime_input_descriptor(rt, 0, &input) ||
	    onnx_runtime_output_descriptor(rt, 0, &output) || input.rank != 3 ||
	    input.dimensions[0] != 1 || input.dimensions[1] >= 0 || input.dimensions[2] != 36 ||
	    output.rank != 2 || output.dimensions[0] != 1 || output.dimensions[1] != 135) {
		fprintf(stderr, "temporal fixture descriptor contract failed\n");
		onnx_runtime_destroy(rt);
		return 1;
	}
	const int64_t shape[] = {1, 40, 36};
	float *values = (float *)calloc(1440, sizeof(float));
	float result[135];
	if (!values) return 1;
	for (int i = 0; i < 1440; i++) values[i] = (float)i / 1000.0f;
	for (int run = 0; run < 2; run++) {
		int written = 0;
		if (onnx_runtime_predict_shaped(rt, values, 1440, shape, 3, result, 135, &written) ||
		    written != 135) {
			fprintf(stderr, "temporal fixture inference failed: %s\n",
				onnx_runtime_last_error(rt));
			free(values);
			onnx_runtime_destroy(rt);
			return 1;
		}
	}
	for (int i = 0; i < 135; i++) {
		if (fabsf(result[i] - values[i]) > 1e-6f) {
			fprintf(stderr, "temporal output mismatch at %d\n", i);
			free(values);
			onnx_runtime_destroy(rt);
			return 1;
		}
	}
	char contract[32];
	if (onnx_runtime_metadata_get(rt, "onnx_loader.contract_version", contract,
		    (int)sizeof(contract)) || strcmp(contract, "1") != 0 ||
	    onnx_runtime_input_tensor_allocations(rt) != 1 ||
	    onnx_runtime_input_tensor_reuses(rt) != 1) {
		fprintf(stderr, "temporal metadata/reuse contract failed\n");
		free(values);
		onnx_runtime_destroy(rt);
		return 1;
	}
	free(values);
	onnx_runtime_destroy(rt);
	onnx_runtime_shutdown();
	printf("ONNX_TEMPORAL_FIXTURE_OK shape=1x40x36 output=1x135 allocations=1 reuses=1\n");
	return 0;
}
