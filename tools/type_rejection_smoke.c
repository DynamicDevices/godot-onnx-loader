#include "onnx_runtime.h"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: type_rejection_smoke model.onnx [...]\n");
		return 2;
	}
	for (int i = 1; i < argc; i++) {
		OnnxRuntime *rt = onnx_runtime_create(argv[i]);
		if (rt) {
			fprintf(stderr, "unsupported tensor model unexpectedly loaded: %s\n", argv[i]);
			onnx_runtime_destroy(rt);
			return 1;
		}
		const char *error = onnx_runtime_last_error(NULL);
		if (!strstr(error, "unsupported tensor element type") || !strstr(error, "float32")) {
			fprintf(stderr, "unclear type rejection for %s: %s\n", argv[i], error);
			return 1;
		}
		printf("ONNX_TYPE_REJECTION_OK model=%s error=%s\n", argv[i], error);
	}
	onnx_runtime_shutdown();
	return 0;
}
