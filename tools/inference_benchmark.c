#include "onnx_runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: inference_benchmark model.onnx\n");
		return 2;
	}
	const int warmup_runs = 100;
	const int measured_runs = 10000;
	OnnxRuntime *rt = onnx_runtime_create(argv[1]);
	if (!rt) {
		fprintf(stderr, "benchmark load failed: %s\n", onnx_runtime_last_error(NULL));
		return 1;
	}
	int ni = onnx_runtime_input_size(rt);
	int no = onnx_runtime_output_size(rt);
	float *input = (float *)calloc((size_t)ni, sizeof(float));
	float *output = (float *)calloc((size_t)no, sizeof(float));
	if (!input || !output) return 1;
	for (int run = 0; run < warmup_runs; run++) {
		int written = 0;
		if (onnx_runtime_predict(rt, input, ni, output, no, &written) || written != no)
			return 1;
	}
	clock_t start = clock();
	for (int run = 0; run < measured_runs; run++) {
		int written = 0;
		input[run % ni] = (float)run;
		if (onnx_runtime_predict(rt, input, ni, output, no, &written) || written != no)
			return 1;
	}
	double elapsed_ms = 1000.0 * (double)(clock() - start) / CLOCKS_PER_SEC;
#ifdef ONNX_LOADER_HAS_REUSE_DIAGNOSTICS
	uint64_t allocations = onnx_runtime_input_tensor_allocations(rt);
	uint64_t reuses = onnx_runtime_input_tensor_reuses(rt);
#else
	uint64_t allocations = (uint64_t)(warmup_runs + measured_runs);
	uint64_t reuses = 0;
#endif
	printf("ONNX_INFERENCE_BENCHMARK_OK measured_runs=%d warmup_runs=%d "
	       "allocations=%llu reuses=%llu elapsed_ms=%.3f us_per_run=%.3f\n",
	       measured_runs, warmup_runs, (unsigned long long)allocations,
	       (unsigned long long)reuses, elapsed_ms, elapsed_ms * 1000.0 / measured_runs);
	free(input);
	free(output);
	onnx_runtime_destroy(rt);
	onnx_runtime_shutdown();
	return 0;
}
