#include "onnx_runtime.h"

#include <stdio.h>
#include <string.h>

static int expect_failure(const char *path, const char *needle)
{
	OnnxRuntime *rt = onnx_runtime_create(path);
	if (rt) {
		fprintf(stderr, "invalid model unexpectedly loaded: %s\n", path);
		onnx_runtime_destroy(rt);
		return -1;
	}
	const char *error = onnx_runtime_last_error(NULL);
	if (!error || !strstr(error, needle)) {
		fprintf(stderr, "load error for %s did not contain %s: %s\n", path, needle,
			error ? error : "(null)");
		return -1;
	}
	printf("ONNX_LOAD_FAILURE_OK model=%s error=%s\n", path, error);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: load_failure_smoke malformed.onnx unsupported_operator.onnx\n");
		return 2;
	}
	if (expect_failure("/definitely/missing/model.onnx", "model not found") ||
	    expect_failure(argv[1], "CreateSessionFromArray") ||
	    expect_failure(argv[2], "CreateSessionFromArray")) {
		return 1;
	}
	onnx_runtime_shutdown();
	return 0;
}
