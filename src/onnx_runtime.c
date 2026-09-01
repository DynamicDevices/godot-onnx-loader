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
#define ONNX_IO_MAX 32

typedef struct TensorInfo {
	char name[ONNX_NAME_MAX];
	int element_type;
	int rank;
	int64_t dims[ONNX_LOADER_MAX_RANK];
	int flat_size;
} TensorInfo;

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
	int input_count;
	int output_count;
	TensorInfo inputs[ONNX_IO_MAX];
	TensorInfo outputs[ONNX_IO_MAX];
	OrtValue *bound_inputs[ONNX_IO_MAX];
	OrtValue *run_outputs[ONNX_IO_MAX];
	int run_output_indices[ONNX_IO_MAX];
	int run_output_count;
	uint64_t generation;
	int profiling_active;
	char last_error[512];
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

static int runtime_error(OnnxRuntime *rt, const char *message)
{
	if (rt) {
		snprintf(rt->last_error, sizeof(rt->last_error), "%s", message ? message : "unknown error");
	}
	fprintf(stderr, "onnx_loader: %s\n", message ? message : "unknown error");
	return -1;
}

static int find_tensor(const TensorInfo *items, int count, const char *name)
{
	if (!name) return -1;
	for (int i = 0; i < count; i++) {
		if (strcmp(items[i].name, name) == 0) return i;
	}
	return -1;
}

static void release_values(OnnxRuntime *rt, OrtValue **values, int count)
{
	if (!rt || !rt->ort) return;
	for (int i = 0; i < count; i++) {
		if (values[i]) {
			rt->ort->ReleaseValue(values[i]);
			values[i] = NULL;
		}
	}
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
	/* Prefer ORT beside the GDExtension (AssetLib / just-works). ONNX_ORT_BIN is
	 * a last-resort override — nix develop often sets it to a store ORT that
	 * fails execstack under Godot 4.6. */
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

static int tensor_float_info(const OrtApi *ort, OrtSession *session, int is_input, int index,
			     int *out_rank, int64_t *out_dims, int dims_cap, int *out_flat_or_neg1,
			     int *out_element_type)
{
	OrtTypeInfo *type_info = NULL;
	const OrtTensorTypeAndShapeInfo *tensor_info = NULL;
	size_t rank = 0;
	int64_t *shape = NULL;
	int rc = -1;
	*out_rank = 0;
	*out_flat_or_neg1 = -1;

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
	    rank > (size_t)dims_cap) {
		goto done;
	}

	shape = rank ? (int64_t *)calloc(rank, sizeof(int64_t)) : NULL;
	if (rank && !shape) {
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
	*out_element_type = (int)elem_type;

	*out_rank = (int)rank;
	for (size_t i = 0; i < rank; i++) {
		out_dims[i] = shape[i];
	}

	/* Flat size with batch=1; -1 if any non-batch dim is dynamic */
	int64_t n = 1;
	int dynamic = 0;
	for (size_t i = 0; i < rank; i++) {
		int64_t d = shape[i];
		if (d <= 0) {
			if (i == 0) {
				d = 1;
			} else {
				dynamic = 1;
				break;
			}
		}
		n *= d;
	}
	if (dynamic || n <= 0 || n > INT32_MAX) {
		*out_flat_or_neg1 = -1;
	} else {
		*out_flat_or_neg1 = (int)n;
	}
	rc = 0;

done:
	free(shape);
	if (type_info) {
		ort->ReleaseTypeInfo(type_info);
	}
	return rc;
}

static OnnxRuntime *onnx_runtime_create_impl(const char *model_onnx_path,
					      const char *profile_file_prefix)
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
	if (profile_file_prefix && profile_file_prefix[0]) {
#ifdef _WIN32
		int wide_len = MultiByteToWideChar(CP_UTF8, 0, profile_file_prefix, -1, NULL, 0);
		wchar_t *wide_prefix = wide_len > 0 ? (wchar_t *)calloc((size_t)wide_len, sizeof(wchar_t)) : NULL;
		if (!wide_prefix || !MultiByteToWideChar(CP_UTF8, 0, profile_file_prefix, -1,
				wide_prefix, wide_len) || ort_fail(ort, ort->EnableProfiling(opts, wide_prefix),
				"EnableProfiling")) {
			free(wide_prefix);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		free(wide_prefix);
#else
		if (ort_fail(ort, ort->EnableProfiling(opts, profile_file_prefix), "EnableProfiling")) {
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
#endif
		rt->profiling_active = 1;
	}

	/* Load bytes then CreateSessionFromArray — avoids path/mmap quirks under
	 * some hosts (Nix Godot free(): invalid size on TCN; host path CreateSession OK). */
	{
		FILE *f = fopen(model_onnx_path, "rb");
		if (!f) {
			fprintf(stderr, "onnx_runtime_create: fopen failed: %s\n", model_onnx_path);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		if (fseek(f, 0, SEEK_END) != 0) {
			fclose(f);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		long sz = ftell(f);
		if (sz <= 0 || sz > (long)(512 * 1024 * 1024)) {
			fclose(f);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		if (fseek(f, 0, SEEK_SET) != 0) {
			fclose(f);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		void *buf = malloc((size_t)sz);
		if (!buf) {
			fclose(f);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		size_t nread = fread(buf, 1, (size_t)sz, f);
		fclose(f);
		if (nread != (size_t)sz) {
			free(buf);
			ort->ReleaseSessionOptions(opts);
			onnx_runtime_destroy(rt);
			return NULL;
		}
		teardown_log("CreateSessionFromArray");
		if (ort_fail(ort,
			     ort->CreateSessionFromArray(g_env, buf, (size_t)sz, opts, &rt->session),
			     "CreateSessionFromArray")) {
			free(buf);
			ort->ReleaseSessionOptions(opts);
			rt->session = NULL;
			onnx_runtime_destroy(rt);
			return NULL;
		}
		free(buf);
		teardown_log("CreateSessionFromArray-done");
	}
	ort->ReleaseSessionOptions(opts);
	opts = NULL;
	rt->session_live = 1;

	size_t input_count = 0;
	size_t output_count = 0;
	if (ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(ort, ort->SessionGetInputCount(rt->session, &input_count), "GetInputCount") ||
	    ort_fail(ort, ort->SessionGetOutputCount(rt->session, &output_count), "GetOutputCount") ||
	    input_count == 0 || output_count == 0 || input_count > ONNX_IO_MAX ||
	    output_count > ONNX_IO_MAX) {
		onnx_runtime_destroy(rt);
		return NULL;
	}
	rt->input_count = (int)input_count;
	rt->output_count = (int)output_count;
	for (int kind = 0; kind < 2; kind++) {
		TensorInfo *items = kind == 0 ? rt->inputs : rt->outputs;
		int count = kind == 0 ? rt->input_count : rt->output_count;
		for (int i = 0; i < count; i++) {
			char *tmp_name = NULL;
			OrtStatus *name_status = kind == 0
				? ort->SessionGetInputName(rt->session, (size_t)i, allocator, &tmp_name)
				: ort->SessionGetOutputName(rt->session, (size_t)i, allocator, &tmp_name);
			if (ort_fail(ort, name_status, kind == 0 ? "GetInputName" : "GetOutputName") ||
			    !tmp_name) {
				onnx_runtime_destroy(rt);
				return NULL;
			}
			copy_io_name(items[i].name, sizeof(items[i].name), tmp_name);
			release_ort_string(ort, allocator, tmp_name);
			if (tensor_float_info(ort, rt->session, kind == 0, i, &items[i].rank,
					      items[i].dims, ONNX_LOADER_MAX_RANK,
					      &items[i].flat_size, &items[i].element_type) != 0) {
				onnx_runtime_destroy(rt);
				return NULL;
			}
		}
	}

	return rt;
}

OnnxRuntime *onnx_runtime_create(const char *model_onnx_path)
{
	return onnx_runtime_create_impl(model_onnx_path, NULL);
}

OnnxRuntime *onnx_runtime_create_profiled(const char *model_onnx_path,
					  const char *profile_file_prefix)
{
	if (!profile_file_prefix || !profile_file_prefix[0]) return NULL;
	return onnx_runtime_create_impl(model_onnx_path, profile_file_prefix);
}

int onnx_runtime_end_profiling(OnnxRuntime *rt, char *out_path, int out_path_cap)
{
	if (!rt || !rt->session_live || !rt->profiling_active || !out_path || out_path_cap <= 0)
		return runtime_error(rt, "profiling is not active");
	OrtAllocator *allocator = NULL;
	char *generated_path = NULL;
	if (ort_fail(rt->ort, rt->ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(rt->ort, rt->ort->SessionEndProfiling(rt->session, allocator, &generated_path),
		     "SessionEndProfiling") || !generated_path)
		return runtime_error(rt, "failed to end profiling");
	snprintf(out_path, (size_t)out_path_cap, "%s", generated_path);
	release_ort_string(rt->ort, allocator, generated_path);
	rt->profiling_active = 0;
	rt->last_error[0] = '\0';
	return 0;
}

void onnx_runtime_destroy(OnnxRuntime *rt)
{
	if (!rt) {
		return;
	}
	const OrtApi *ort = rt->ort;
	teardown_log("destroy-enter");
	release_values(rt, rt->run_outputs, rt->run_output_count);
	release_values(rt, rt->bound_inputs, rt->input_count);
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
	return rt && rt->input_count ? rt->inputs[0].name : "";
}

const char *onnx_runtime_output_name(const OnnxRuntime *rt)
{
	return rt && rt->output_count ? rt->outputs[0].name : "";
}

int onnx_runtime_input_size(const OnnxRuntime *rt)
{
	return rt && rt->input_count ? rt->inputs[0].flat_size : 0;
}

int onnx_runtime_output_size(const OnnxRuntime *rt)
{
	return rt && rt->output_count ? rt->outputs[0].flat_size : 0;
}

int onnx_runtime_input_count(const OnnxRuntime *rt) { return rt ? rt->input_count : 0; }
int onnx_runtime_output_count(const OnnxRuntime *rt) { return rt ? rt->output_count : 0; }

static int copy_descriptor(const TensorInfo *info, OnnxTensorDescriptor *out)
{
	if (!info || !out) return -1;
	out->name = info->name;
	out->element_type = info->element_type;
	out->rank = info->rank;
	memcpy(out->dimensions, info->dims, sizeof(out->dimensions));
	out->flat_size = info->flat_size;
	return 0;
}

int onnx_runtime_input_descriptor(const OnnxRuntime *rt, int index, OnnxTensorDescriptor *out)
{
	return !rt || index < 0 || index >= rt->input_count ? -1 : copy_descriptor(&rt->inputs[index], out);
}

int onnx_runtime_output_descriptor(const OnnxRuntime *rt, int index, OnnxTensorDescriptor *out)
{
	return !rt || index < 0 || index >= rt->output_count ? -1 : copy_descriptor(&rt->outputs[index], out);
}

int onnx_runtime_set_input_f32(OnnxRuntime *rt, const char *name, const float *data, int data_len,
			       const int64_t *shape, int shape_len)
{
	if (!rt || !rt->session_live || !data || data_len < 0 || shape_len < 0 ||
	    shape_len > ONNX_LOADER_MAX_RANK || (shape_len && !shape))
		return runtime_error(rt, "invalid set_input arguments");
	int index = find_tensor(rt->inputs, rt->input_count, name);
	if (index < 0) return runtime_error(rt, "unknown input name");
	TensorInfo *desc = &rt->inputs[index];
	if (shape_len != desc->rank) return runtime_error(rt, "input rank does not match model");
	int64_t need = 1;
	for (int i = 0; i < shape_len; i++) {
		if (shape[i] <= 0 || (desc->dims[i] > 0 && desc->dims[i] != shape[i]) ||
		    need > INT32_MAX / shape[i])
			return runtime_error(rt, "input shape does not match model");
		need *= shape[i];
	}
	if (need != data_len) return runtime_error(rt, "input data length does not match shape");
	OrtAllocator *allocator = NULL;
	OrtValue *value = NULL;
	if (ort_fail(rt->ort, rt->ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(rt->ort, rt->ort->CreateTensorAsOrtValue(allocator, shape, (size_t)shape_len,
			ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &value), "CreateTensorAsOrtValue"))
		return runtime_error(rt, "failed to allocate input tensor");
	float *dest = NULL;
	if (ort_fail(rt->ort, rt->ort->GetTensorMutableData(value, (void **)&dest), "GetTensorData")) {
		rt->ort->ReleaseValue(value);
		return runtime_error(rt, "failed to access input tensor");
	}
	memcpy(dest, data, (size_t)data_len * sizeof(float));
	if (rt->bound_inputs[index]) rt->ort->ReleaseValue(rt->bound_inputs[index]);
	rt->bound_inputs[index] = value;
	rt->last_error[0] = '\0';
	return 0;
}

int onnx_runtime_run(OnnxRuntime *rt, const char *const *output_names, int output_count)
{
	if (!rt || !rt->session_live || output_count < 0 || output_count > rt->output_count)
		return runtime_error(rt, "invalid run arguments");
	/* A run attempt starts a new output epoch. Invalidate the previous cache
	 * before validation so a failed run can never expose stale values. */
	release_values(rt, rt->run_outputs, rt->run_output_count);
	rt->run_output_count = 0;
	for (int i = 0; i < rt->input_count; i++)
		if (!rt->bound_inputs[i]) return runtime_error(rt, "required input is not bound");
	int count = output_count ? output_count : rt->output_count;
	const char *input_names[ONNX_IO_MAX] = {0};
	const char *selected_names[ONNX_IO_MAX] = {0};
	const OrtValue *input_values[ONNX_IO_MAX] = {0};
	int selected_indices[ONNX_IO_MAX] = {0};
	for (int i = 0; i < rt->input_count; i++) {
		input_names[i] = rt->inputs[i].name;
		input_values[i] = rt->bound_inputs[i];
	}
	for (int i = 0; i < count; i++) {
		const char *name = output_count ? output_names[i] : rt->outputs[i].name;
		int index = find_tensor(rt->outputs, rt->output_count, name);
		if (index < 0) return runtime_error(rt, "unknown output name");
		selected_names[i] = rt->outputs[index].name;
		selected_indices[i] = index;
	}
	OrtValue *fresh[ONNX_IO_MAX] = {0};
	if (ort_fail(rt->ort, rt->ort->Run(rt->session, NULL, input_names, input_values,
			(size_t)rt->input_count, selected_names, (size_t)count, fresh), "Run")) {
		release_values(rt, fresh, count);
		return runtime_error(rt, "ONNX Runtime run failed");
	}
	for (int i = 0; i < count; i++) {
		rt->run_outputs[i] = fresh[i];
		rt->run_output_indices[i] = selected_indices[i];
	}
	rt->run_output_count = count;
	rt->generation++;
	rt->last_error[0] = '\0';
	return 0;
}

static OrtValue *find_run_output(const OnnxRuntime *rt, const char *name)
{
	int index = rt ? find_tensor(rt->outputs, rt->output_count, name) : -1;
	for (int i = 0; rt && index >= 0 && i < rt->run_output_count; i++)
		if (rt->run_output_indices[i] == index) return rt->run_outputs[i];
	return NULL;
}

int onnx_runtime_has_output(const OnnxRuntime *rt, const char *name)
{
	return find_run_output(rt, name) != NULL;
}

int onnx_runtime_output_data_f32(const OnnxRuntime *rt, const char *name, float *output,
				 int output_cap, int *output_len_out)
{
	OrtValue *value = find_run_output(rt, name);
	if (!value || !output || output_cap < 0) return -1;
	OrtTensorTypeAndShapeInfo *info = NULL;
	size_t count = 0;
	float *data = NULL;
	if (ort_fail(rt->ort, rt->ort->GetTensorTypeAndShape(value, &info), "GetTensorTypeAndShape") ||
	    ort_fail(rt->ort, rt->ort->GetTensorShapeElementCount(info, &count), "GetTensorShapeElementCount") ||
	    ort_fail(rt->ort, rt->ort->GetTensorMutableData(value, (void **)&data), "GetTensorData")) {
		if (info) rt->ort->ReleaseTensorTypeAndShapeInfo(info);
		return -1;
	}
	rt->ort->ReleaseTensorTypeAndShapeInfo(info);
	if (count > (size_t)output_cap || count > INT32_MAX) return -1;
	memcpy(output, data, count * sizeof(float));
	if (output_len_out) *output_len_out = (int)count;
	return 0;
}

int onnx_runtime_output_slice_f32(const OnnxRuntime *rt, const char *name, int offset, int count,
				  float *output)
{
	OrtValue *value = find_run_output(rt, name);
	OrtTensorTypeAndShapeInfo *info = NULL;
	size_t total = 0;
	float *data = NULL;
	if (!value || !output || offset < 0 || count < 0 ||
	    ort_fail(rt->ort, rt->ort->GetTensorTypeAndShape(value, &info), "GetTensorTypeAndShape") ||
	    ort_fail(rt->ort, rt->ort->GetTensorShapeElementCount(info, &total), "GetTensorShapeElementCount") ||
	    ort_fail(rt->ort, rt->ort->GetTensorMutableData(value, (void **)&data), "GetTensorData")) {
		if (info) rt->ort->ReleaseTensorTypeAndShapeInfo(info);
		return -1;
	}
	rt->ort->ReleaseTensorTypeAndShapeInfo(info);
	if ((size_t)offset > total || (size_t)count > total - (size_t)offset) return -1;
	memcpy(output, data + offset, (size_t)count * sizeof(float));
	return 0;
}

int onnx_runtime_output_shape(const OnnxRuntime *rt, const char *name, int64_t *shape,
			      int shape_cap, int *shape_len_out)
{
	OrtValue *value = find_run_output(rt, name);
	OrtTensorTypeAndShapeInfo *info = NULL;
	size_t rank = 0;
	if (!value || shape_cap < 0 ||
	    ort_fail(rt->ort, rt->ort->GetTensorTypeAndShape(value, &info), "GetTensorTypeAndShape") ||
	    ort_fail(rt->ort, rt->ort->GetDimensionsCount(info, &rank), "GetDimensionsCount")) {
		if (info) rt->ort->ReleaseTensorTypeAndShapeInfo(info);
		return -1;
	}
	if (rank > (size_t)shape_cap || (rank && !shape) ||
	    ort_fail(rt->ort, rt->ort->GetDimensions(info, shape, rank), "GetDimensions")) {
		rt->ort->ReleaseTensorTypeAndShapeInfo(info);
		return -1;
	}
	rt->ort->ReleaseTensorTypeAndShapeInfo(info);
	if (shape_len_out) *shape_len_out = (int)rank;
	return 0;
}

uint64_t onnx_runtime_run_generation(const OnnxRuntime *rt) { return rt ? rt->generation : 0; }
const char *onnx_runtime_last_error(const OnnxRuntime *rt) { return rt ? rt->last_error : "model not loaded"; }

int onnx_runtime_predict(const OnnxRuntime *rt, const float *input, int input_len,
			 float *output, int output_cap, int *output_len_out)
{
	if (!rt || !rt->input_count || rt->inputs[0].flat_size != input_len) return -1;
	int64_t concrete_shape[ONNX_LOADER_MAX_RANK];
	for (int i = 0; i < rt->inputs[0].rank; i++)
		concrete_shape[i] = rt->inputs[0].dims[i] > 0 ? rt->inputs[0].dims[i] : 1;
	return onnx_runtime_predict_shaped(rt, input, input_len, concrete_shape,
			rt->inputs[0].rank, output, output_cap, output_len_out);
}

int onnx_runtime_predict_shaped(const OnnxRuntime *rt, const float *input, int input_len,
				const int64_t *shape, int shape_len, float *output, int output_cap,
				int *output_len_out)
{
	OnnxRuntime *mutable_rt = (OnnxRuntime *)rt;
	const char *output_name = rt ? rt->outputs[0].name : NULL;
	if (!rt || rt->input_count != 1 || rt->output_count < 1 ||
	    onnx_runtime_set_input_f32(mutable_rt, rt->inputs[0].name, input, input_len, shape, shape_len) ||
	    onnx_runtime_run(mutable_rt, &output_name, 1))
		return -1;
	return onnx_runtime_output_data_f32(rt, rt->outputs[0].name, output, output_cap, output_len_out);
}

int onnx_runtime_metadata_get(const OnnxRuntime *rt, const char *key, char *buf, int buf_len)
{
	if (!rt || !rt->ort || !rt->session || !key || !buf || buf_len < 2) {
		return 1;
	}
	const OrtApi *ort = rt->ort;
	OrtModelMetadata *meta = NULL;
	OrtAllocator *allocator = NULL;
	char *value = NULL;
	int rc = 1;
	buf[0] = '\0';
	if (ort_fail(ort, ort->SessionGetModelMetadata(rt->session, &meta), "SessionGetModelMetadata") ||
	    ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(ort,
		     ort->ModelMetadataLookupCustomMetadataMap(meta, allocator, key, &value),
		     "ModelMetadataLookup")) {
		goto done;
	}
	if (!value) {
		goto done;
	}
	snprintf(buf, (size_t)buf_len, "%s", value);
	rc = 0;
done:
	if (value && allocator) {
		allocator->Free(allocator, value);
	}
	if (meta) {
		ort->ReleaseModelMetadata(meta);
	}
	return rc;
}

int onnx_runtime_metadata_keys(const OnnxRuntime *rt, char *keys_storage, int count_cap,
			       int key_buf_len, int *count_out)
{
	if (count_out) {
		*count_out = 0;
	}
	if (!rt || !rt->ort || !rt->session || !keys_storage || count_cap <= 0 || key_buf_len < 2) {
		return 1;
	}
	const OrtApi *ort = rt->ort;
	OrtModelMetadata *meta = NULL;
	OrtAllocator *allocator = NULL;
	char **keys = NULL;
	int64_t num_keys = 0;
	int rc = 1;
	if (ort_fail(ort, ort->SessionGetModelMetadata(rt->session, &meta), "SessionGetModelMetadata") ||
	    ort_fail(ort, ort->GetAllocatorWithDefaultOptions(&allocator), "GetAllocator") ||
	    ort_fail(ort,
		     ort->ModelMetadataGetCustomMetadataMapKeys(meta, allocator, &keys, &num_keys),
		     "ModelMetadataKeys")) {
		goto done;
	}
	int n = (int)num_keys;
	if (n > count_cap) {
		n = count_cap;
	}
	for (int i = 0; i < n; i++) {
		char *dest = keys_storage + (size_t)i * (size_t)key_buf_len;
		if (keys && keys[i]) {
			snprintf(dest, (size_t)key_buf_len, "%s", keys[i]);
		} else {
			dest[0] = '\0';
		}
	}
	if (count_out) {
		*count_out = n;
	}
	rc = 0;
done:
	if (keys && allocator) {
		for (int64_t i = 0; i < num_keys; i++) {
			if (keys[i]) {
				allocator->Free(allocator, keys[i]);
			}
		}
		allocator->Free(allocator, keys);
	}
	if (meta) {
		ort->ReleaseModelMetadata(meta);
	}
	return rc;
}
