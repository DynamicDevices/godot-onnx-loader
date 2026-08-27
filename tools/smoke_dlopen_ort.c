#define _GNU_SOURCE
/*
 * dlopen bundled libonnxruntime.so.1, then exercise ORT via the real C API.
 * Proves ReleaseSession works without Godot in the loader process.
 *
 * Usage: smoke_dlopen_ort <bin_dir> <model.onnx>
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "onnxruntime_c_api.h"

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

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: %s <bin_dir> <model.onnx>\n", argv[0]);
		return 2;
	}

	char libpath[4096];
	snprintf(libpath, sizeof(libpath), "%s/libonnxruntime.so.1", argv[1]);
	void *h = dlopen(libpath, RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND);
	if (!h) {
		fprintf(stderr, "dlopen %s: %s\n", libpath, dlerror());
		return 1;
	}

	typedef const OrtApiBase *(*OrtGetApiBaseFn)(void);
	OrtGetApiBaseFn get_base = (OrtGetApiBaseFn)dlsym(h, "OrtGetApiBase");
	if (!get_base) {
		fprintf(stderr, "dlsym OrtGetApiBase: %s\n", dlerror());
		return 1;
	}
	const OrtApi *api = get_base()->GetApi(ORT_API_VERSION);
	if (!api) {
		fprintf(stderr, "GetApi failed\n");
		return 1;
	}

	Dl_info info;
	if (dladdr((void *)api->ReleaseSession, &info) && info.dli_fname) {
		printf("ORT dlopen path: %s\n", info.dli_fname);
	}

	OrtEnv *env = NULL;
	OrtSessionOptions *opts = NULL;
	OrtSession *session = NULL;

	if (ort_fail(api, api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "smoke_dlopen", &env),
		     "CreateEnv")) {
		return 1;
	}
	if (ort_fail(api, api->CreateSessionOptions(&opts), "CreateSessionOptions")) {
		api->ReleaseEnv(env);
		return 1;
	}
	if (ort_fail(api, api->CreateSession(env, argv[2], opts, &session), "CreateSession")) {
		api->ReleaseSessionOptions(opts);
		api->ReleaseEnv(env);
		return 1;
	}

	printf("ONNX_DLOPEN_SMOKE_OK session=%p\n", (void *)session);
	api->ReleaseSessionOptions(opts);
	api->ReleaseSession(session);
	api->ReleaseEnv(env);
	dlclose(h);
	printf("ONNX_DLOPEN_TEARDOWN_OK\n");
	return 0;
}
