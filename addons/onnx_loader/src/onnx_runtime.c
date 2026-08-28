#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#else
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#endif

#include "onnx_runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "onnxruntime_c_api.h"

#define ONNX_NAME_MAX 128

#ifdef _WIN32
#define ORT_PATH_SEP '\\'
static int ort_readable(const char *path)
{
	return path && path[0] && _access(path, 0) == 0;
}
#else
#define ORT_PATH_SEP '/'
static int ort_readable(const char *path)
{
	return path && path[0] && access(path, R_OK) == 0;
}
#endif

struct OnnxRuntime {
	const OrtApi *ort;
	OrtSession *session;
	int session_live;
	char input_name[ONNX_NAME_MAX];
	char output_name[ONNX_NAME_MAX];
	int input_size;
	int output_size;
};

static const OrtApi *g_ort;
static void *g_ort_dlhandle;
static char g_ort_libpath[4096];
static OrtEnv *g_env;
static int g_env_users;

static void teardown_log(const char *stage)
{
	fprintf(stderr, "ONNX_LOADER_TEARDOWN %s\n", stage);
}

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

static int resolve_bundled_ort_path(char *out, size_t out_cap)
{
	/* Guard before any snprintf — GCC fortify -O2 (template_release) treats a
	 * possibly-null out as -Werror=format-truncation / null destination. */
	if (!out || out_cap < 2) {
		return -1;
	}
	out[0] = '\0';

#ifdef _WIN32
	static const char *ort_names[] = {"onnxruntime.dll", NULL};
#else
#ifdef __APPLE__
	static const char *ort_names[] = {
		"libonnxruntime.1.20.1.dylib",
		"libonnxruntime.dylib",
		"libonnxruntime.so.1",
		NULL,
	};
#else
	static const char *ort_names[] = {"libonnxruntime.so.1", "libonnxruntime.so", NULL};
#endif
#endif
	const char *env = getenv("ONNX_ORT_BIN");
	if (env && env[0]) {
		for (size_t i = 0; ort_names[i]; i++) {
			snprintf(out, out_cap, "%s%c%s", env, ORT_PATH_SEP, ort_names[i]);
			if (ort_readable(out)) {
				return 0;
			}
		}
		snprintf(out, out_cap, "%s", env);
		if (ort_readable(out)) {
			return 0;
		}
	}

#ifdef _WIN32
	HMODULE self = NULL;
	if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
				   GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
			       (LPCSTR)&resolve_bundled_ort_path, &self) &&
	    self) {
		char addon_path[4096];
		DWORD n = GetModuleFileNameA(self, addon_path, sizeof(addon_path));
		if (n > 0 && n < sizeof(addon_path)) {
			char *slash = strrchr(addon_path, '\\');
			if (!slash) {
				slash = strrchr(addon_path, '/');
			}
			if (slash) {
				*slash = '\0';
				for (size_t i = 0; ort_names[i]; i++) {
					snprintf(out, out_cap, "%s\\%s", addon_path, ort_names[i]);
					if (ort_readable(out)) {
						return 0;
					}
				}
			}
		}
	}
#else
	/* Prefer ORT beside this DSO (GDExtension / host smoke linked with runtime). */
	Dl_info info;
	if (dladdr((void *)&resolve_bundled_ort_path, &info) && info.dli_fname && info.dli_fname[0]) {
		char addon_path[4096];
		snprintf(addon_path, sizeof(addon_path), "%s", info.dli_fname);
		char *slash = strrchr(addon_path, '/');
		if (slash) {
			for (size_t i = 0; ort_names[i]; i++) {
				int n = snprintf(out, out_cap, "%.*s/%s",
						 (int)(slash - addon_path), addon_path, ort_names[i]);
				if (n > 0 && (size_t)n < out_cap && ort_readable(out)) {
					return 0;
				}
			}
			for (size_t i = 0; ort_names[i]; i++) {
				int n = snprintf(out, out_cap,
						 "%.*s/../addons/onnx_loader/bin/%s",
						 (int)(slash - addon_path), addon_path, ort_names[i]);
				if (n > 0 && (size_t)n < out_cap && ort_readable(out)) {
					return 0;
				}
			}
		}
	}
#endif

	static const char *candidates[] = {
#ifdef _WIN32
		"addons/onnx_loader/bin/onnxruntime.dll",
		"demo/addons/onnx_loader/bin/onnxruntime.dll",
#else
#ifdef __APPLE__
		"addons/onnx_loader/bin/libonnxruntime.dylib",
		"addons/onnx_loader/bin/libonnxruntime.1.20.1.dylib",
		"demo/addons/onnx_loader/bin/libonnxruntime.dylib",
#endif
		"addons/onnx_loader/bin/libonnxruntime.so.1",
		"demo/addons/onnx_loader/bin/libonnxruntime.so.1",
#endif
		NULL,
	};
	for (size_t i = 0; candidates[i]; i++) {
		if (ort_readable(candidates[i])) {
			snprintf(out, out_cap, "%s", candidates[i]);
			return 0;
		}
	}
	fprintf(stderr,
		"resolve_bundled_ort_path: need ORT shared lib beside the addon "
		"(addons/onnx_loader/bin) or ONNX_ORT_BIN; see .gdextension [dependencies]\n");
	return -1;
}

static void *ort_dlsym(void *handle, const char *name)
{
#ifdef _WIN32
	return (void *)GetProcAddress((HMODULE)handle, name);
#else
	return dlsym(handle, name);
#endif
}

static void ort_dlclose(void *handle)
{
	if (!handle) {
		return;
	}
#ifdef _WIN32
	FreeLibrary((HMODULE)handle);
#else
	dlclose(handle);
#endif
}

static const OrtApi *ort_api(void)
{
	if (g_ort) {
		return g_ort;
	}

	typedef const OrtApiBase *(*OrtGetApiBaseFn)(void);
	OrtGetApiBaseFn get_base = NULL;

	if (!g_ort_dlhandle) {
		if (resolve_bundled_ort_path(g_ort_libpath, sizeof(g_ort_libpath)) != 0) {
			return NULL;
		}
#ifdef _WIN32
		g_ort_dlhandle = (void *)LoadLibraryA(g_ort_libpath);
		if (!g_ort_dlhandle) {
			fprintf(stderr, "LoadLibrary ORT %s: error %lu\n", g_ort_libpath,
				(unsigned long)GetLastError());
			g_ort_libpath[0] = '\0';
			return NULL;
		}
#else
#ifndef RTLD_DEEPBIND
#define RTLD_DEEPBIND 0
#endif
		g_ort_dlhandle = dlopen(g_ort_libpath, RTLD_NOW | RTLD_LOCAL | RTLD_DEEPBIND);
		if (!g_ort_dlhandle) {
			/* dlerror() is single-shot — capture once (double-call always printed "(null)"). */
			const char *dlerr = dlerror();
			fprintf(stderr, "dlopen ORT %s: %s\n", g_ort_libpath,
				dlerr && dlerr[0] ? dlerr : "(null)");
			g_ort_libpath[0] = '\0';
			return NULL;
		}
#endif
		get_base = (OrtGetApiBaseFn)ort_dlsym(g_ort_dlhandle, "OrtGetApiBase");
		if (!get_base) {
			fprintf(stderr, "ort_dlsym OrtGetApiBase failed\n");
			ort_dlclose(g_ort_dlhandle);
			g_ort_dlhandle = NULL;
			g_ort_libpath[0] = '\0';
			return NULL;
		}
	} else {
		get_base = (OrtGetApiBaseFn)ort_dlsym(g_ort_dlhandle, "OrtGetApiBase");
	}

	const OrtApiBase *base = get_base ? get_base() : NULL;
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

static int skip_session_release(void)
{
	/* Default ON: Godot 4.6 + MS ORT often hits free(): invalid size in
	 * ReleaseSession during editor/quit. Opt out with =0 for leak checks. */
	const char *e = getenv("ONNX_LOADER_SKIP_SESSION_RELEASE");
	if (!e || e[0] == '\0') {
		return 1;
	}
	if (e[0] == '0' && e[1] == '\0') {
		return 0;
	}
	return e[0] == '1' && e[1] == '\0';
}

static void ort_env_unuse(void)
{
	if (g_env_users <= 0) {
		return;
	}
	g_env_users--;
	if (g_env_users == 0 && g_ort && g_env) {
		/* Never ReleaseEnv while sessions may still be leaked (skip path):
		 * freeing the env out from under a live session corrupts the heap and
		 * surfaces later as free(): invalid size (Julian editor log). */
		if (skip_session_release()) {
			teardown_log("ReleaseEnv-skipped");
			return;
		}
		teardown_log("ReleaseEnv");
		g_ort->ReleaseEnv(g_env);
		g_env = NULL;
		teardown_log("ReleaseEnv-done");
	}
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
	if (!model_onnx_path || model_onnx_path[0] == '\0') {
		fprintf(stderr, "onnx_runtime_create: empty model path\n");
		return NULL;
	}
	if (!ort_readable(model_onnx_path)) {
		fprintf(stderr, "onnx_runtime_create: model not found: %s\n", model_onnx_path);
		return NULL;
	}

	const OrtApi *ort = ort_api();
	if (!ort) {
		return NULL;
	}

	OnnxRuntime *rt = (OnnxRuntime *)calloc(1, sizeof(*rt));
	if (!rt) {
		return NULL;
	}
	rt->ort = ort;

	OrtSessionOptions *opts = NULL;
	OrtAllocator *allocator = NULL;
	char *tmp_in = NULL;
	char *tmp_out = NULL;

	if (ort_env_use() != 0) {
		free(rt);
		return NULL;
	}

	rt->session = NULL;
	rt->session_live = 0;

	if (ort_fail(ort, ort->CreateSessionOptions(&opts), "CreateSessionOptions") ||
	    ort_fail(ort, ort->DisableCpuMemArena(opts), "DisableCpuMemArena") ||
	    ort_fail(ort, ort->DisableMemPattern(opts), "DisableMemPattern")) {
		if (opts) {
			ort->ReleaseSessionOptions(opts);
		}
		onnx_runtime_destroy(rt);
		return NULL;
	}

	/* Windows ORT CreateSession takes ORTCHAR_T (wchar_t); Unix takes UTF-8 char*. */
#ifdef _WIN32
	{
		wchar_t wpath[4096];
		int n = MultiByteToWideChar(CP_UTF8, 0, model_onnx_path, -1, wpath,
					   (int)(sizeof(wpath) / sizeof(wpath[0])));
		if (n <= 0) {
			fprintf(stderr, "onnx_runtime_create: UTF-8→wchar path failed (%lu)\n",
				(unsigned long)GetLastError());
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		if (ort_fail(ort, ort->CreateSession(g_env, wpath, opts, &rt->session),
			     "CreateSession")) {
			ort->ReleaseSessionOptions(opts);
			rt->session = NULL;
			onnx_runtime_destroy(rt);
			return NULL;
		}
	}
#else
	if (ort_fail(ort, ort->CreateSession(g_env, model_onnx_path, opts, &rt->session),
		     "CreateSession")) {
		ort->ReleaseSessionOptions(opts);
		rt->session = NULL;
		onnx_runtime_destroy(rt);
		return NULL;
	}
#endif
	ort->ReleaseSessionOptions(opts);
	opts = NULL;
	rt->session_live = 1;

	if (
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
	teardown_log("destroy-enter");
	if (ort && rt->session_live && rt->session) {
		if (skip_session_release()) {
			teardown_log("ReleaseSession-skipped");
			rt->session = NULL;
			rt->session_live = 0;
		} else {
			teardown_log("ReleaseSession");
			ort->ReleaseSession(rt->session);
			rt->session = NULL;
			rt->session_live = 0;
			teardown_log("ReleaseSession-done");
		}
	}
	ort_env_unuse();
	rt->ort = NULL;
	teardown_log("free-rt");
	free(rt);
	teardown_log("destroy-exit");
}

void onnx_runtime_drop(OnnxRuntime *rt)
{
	onnx_runtime_destroy(rt);
}

void onnx_runtime_shutdown(void)
{
	teardown_log("shutdown-enter");
	if (g_env_users != 0) {
		fprintf(stderr, "onnx_runtime_shutdown: %d live session(s)\n", g_env_users);
	}
	if (g_ort && g_env) {
		if (skip_session_release()) {
			teardown_log("ReleaseEnv-skipped");
			/* Abandon pointers; process exit reclaims. */
			g_env = NULL;
		} else {
			teardown_log("ReleaseEnv");
			g_ort->ReleaseEnv(g_env);
			g_env = NULL;
			teardown_log("ReleaseEnv-done");
		}
	}
	g_env_users = 0;
	g_ort = NULL;
	if (g_ort_dlhandle) {
		/* Leak dl handle at process exit — dlclose after ORT teardown can abort on Nix. */
		g_ort_dlhandle = NULL;
	}
	g_ort_libpath[0] = '\0';
	teardown_log("shutdown-exit");
}

const char *onnx_runtime_ort_version(void)
{
	const OrtApi *ort = ort_api();
	if (!ort) {
		return "unknown";
	}
	typedef const OrtApiBase *(*OrtGetApiBaseFn)(void);
	OrtGetApiBaseFn get_base = (OrtGetApiBaseFn)ort_dlsym(g_ort_dlhandle, "OrtGetApiBase");
	if (!get_base) {
		return "unknown";
	}
	const OrtApiBase *base = get_base();
	if (!base || !base->GetVersionString) {
		return "unknown";
	}
	return base->GetVersionString();
}

const char *onnx_runtime_ort_library_path(void)
{
	if (g_ort_libpath[0]) {
		return g_ort_libpath;
	}
	const OrtApi *ort = g_ort ? g_ort : ort_api();
	if (!ort) {
		return "unknown";
	}
	if (g_ort_libpath[0]) {
		return g_ort_libpath;
	}
#ifdef _WIN32
	/* Path was recorded at LoadLibrary; no dladdr on MSVC. */
	return "unknown";
#else
	Dl_info info;
	if (dladdr((void *)ort->ReleaseSession, &info) && info.dli_fname && info.dli_fname[0]) {
		return info.dli_fname;
	}
	return "unknown";
#endif
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
	if (!rt || !rt->session_live || !input || !output || input_len != rt->input_size ||
	    output_cap < rt->output_size) {
		return -1;
	}

	const OrtApi *ort = rt->ort;
	OrtAllocator *allocator = NULL;
	OrtValue *in_tensor = NULL;
	OrtValue *out_tensor = NULL;
	int rc = -1;

	if (ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator")) {
		goto done;
	}

	int64_t shape[2] = {1, (int64_t)rt->input_size};
	if (ort_fail(ort,
		     ort->CreateTensorAsOrtValue(allocator, shape, 2,
						 ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
						 &in_tensor),
		     "CreateTensorAsOrtValue")) {
		goto done;
	}

	float *in_data = NULL;
	if (ort_fail(ort, ort->GetTensorMutableData(in_tensor, (void **)&in_data),
		     "GetTensorData")) {
		goto done;
	}
	memcpy(in_data, input, (size_t)input_len * sizeof(float));

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
	return rc;
}
