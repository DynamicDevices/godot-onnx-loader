#include "onnx_runtime.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: %s model.onnx profile-prefix\n", argv[0]);
		return 2;
	}
	OnnxRuntime *rt = onnx_runtime_create_profiled(argv[1], argv[2]);
	if (!rt) return 3;
	float matrix[] = {1, 2, 3, 4, 5, 6, 7, 8};
	float vector[] = {10, 20, 30};
	int64_t matrix_shape[] = {4, 2};
	int64_t vector_shape[] = {3};
	if (onnx_runtime_set_input_f32(rt, "matrix", matrix, 8, matrix_shape, 2) ||
	    onnx_runtime_set_input_f32(rt, "vector", vector, 3, vector_shape, 1)) return 4;
	for (int i = 0; i < 3; i++)
		if (onnx_runtime_run(rt, NULL, 0)) return 5;
	char path[4096];
	if (onnx_runtime_end_profiling(rt, path, sizeof(path))) return 6;
	FILE *profile = fopen(path, "rb");
	if (!profile) return 7;
	char sample[4096];
	size_t got = fread(sample, 1, sizeof(sample) - 1, profile);
	fclose(profile);
	sample[got] = '\0';
	if (!strstr(sample, "model_run") && !strstr(sample, "session")) return 8;
	printf("ONNX_PROFILE_SMOKE_OK path=%s bytes_sampled=%zu generation=%llu\n", path, got,
	       (unsigned long long)onnx_runtime_run_generation(rt));
	onnx_runtime_destroy(rt);
	return 0;
}
