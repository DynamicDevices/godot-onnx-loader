#include "onnx_runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#ifndef _WIN32
#include <unistd.h>
static long rss_kib(void)
{
	FILE *f = fopen("/proc/self/statm", "r");
	long pages = 0;
	long resident = 0;
	if (!f) return -1;
	if (fscanf(f, "%ld %ld", &pages, &resident) != 2) resident = -1;
	fclose(f);
	return resident < 0 ? -1 : resident * sysconf(_SC_PAGESIZE) / 1024;
}
#else
static long rss_kib(void) { return -1; }
#endif

static int exercise(OnnxRuntime *rt, int runs)
{
	int ni = onnx_runtime_input_size(rt);
	int no = onnx_runtime_output_size(rt);
	float *input = ni > 0 ? (float *)calloc((size_t)ni, sizeof(float)) : NULL;
	float *output = no > 0 ? (float *)calloc((size_t)no, sizeof(float)) : NULL;
	if (!input || !output) {
		free(input);
		free(output);
		return -1;
	}
	for (int r = 0; r < runs; r++) {
		int written = 0;
		input[r % ni] = (float)r;
		if (onnx_runtime_predict(rt, input, ni, output, no, &written) || written != no) {
			fprintf(stderr, "inference failed: %s\n", onnx_runtime_last_error(rt));
			free(input);
			free(output);
			return -1;
		}
	}
	free(input);
	free(output);
	if (onnx_runtime_input_tensor_allocations(rt) != 1 ||
	    onnx_runtime_input_tensor_reuses(rt) != (uint64_t)(runs - 1)) {
		fprintf(stderr, "input reuse counters failed\n");
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: session_stress model.onnx\n");
		return 2;
	}
	const int pairs = 25;
	const int runs_per_session = 100;
	const long steady_growth_limit_kib = 64 * 1024;
	long rss_start = rss_kib();
	long rss_warm = -1;
	long rss_peak = rss_start;
	clock_t start = clock();
	for (int pair = 0; pair < pairs; pair++) {
		OnnxRuntime *first = onnx_runtime_create(argv[1]);
		OnnxRuntime *second = onnx_runtime_create(argv[1]);
		if (!first || !second) {
			fprintf(stderr, "create pair[%d] failed: %s\n", pair,
				onnx_runtime_last_error(NULL));
			onnx_runtime_destroy(second);
			onnx_runtime_destroy(first);
			return 1;
		}
		if (exercise(first, runs_per_session) || exercise(second, runs_per_session)) {
			onnx_runtime_destroy(second);
			onnx_runtime_destroy(first);
			return 1;
		}
		/* Destroy in alternating order while both sessions share one OrtEnv. */
		if (pair % 2) {
			onnx_runtime_destroy(first);
			onnx_runtime_destroy(second);
		} else {
			onnx_runtime_destroy(second);
			onnx_runtime_destroy(first);
		}
		long current = rss_kib();
		if (pair == 4) rss_warm = current;
		if (current > rss_peak) rss_peak = current;
	}
	onnx_runtime_shutdown();
	long rss_end = rss_kib();
	long steady_growth = rss_warm < 0 || rss_end < 0 ? -1 : rss_end - rss_warm;
	long cold_growth = rss_start < 0 || rss_end < 0 ? -1 : rss_end - rss_start;
	double elapsed_ms = 1000.0 * (double)(clock() - start) / CLOCKS_PER_SEC;
	int sessions = pairs * 2;
	int runs = sessions * runs_per_session;
	printf("ONNX_SESSION_STRESS_OK pairs=%d sessions=%d runs=%d "
	       "rss_start_kib=%ld rss_warm_kib=%ld rss_peak_kib=%ld rss_end_kib=%ld "
	       "cold_growth_kib=%ld steady_growth_kib=%ld elapsed_ms=%.3f us_per_run=%.3f\n",
	       pairs, sessions, runs, rss_start, rss_warm, rss_peak, rss_end,
	       cold_growth, steady_growth, elapsed_ms, elapsed_ms * 1000.0 / runs);
	if (steady_growth >= 0 && steady_growth > steady_growth_limit_kib) {
		fprintf(stderr, "steady-state RSS growth exceeded %ld KiB limit: %ld KiB\n",
			steady_growth_limit_kib, steady_growth);
		return 1;
	}
	return 0;
}
