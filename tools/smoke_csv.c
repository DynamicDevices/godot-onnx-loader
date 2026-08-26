/**
 * Host CSV smoke through generic onnx_runtime (no Godot required).
 * Applies softmax for classification models; table matches sanity_check_onnx.py.
 */
#include "onnx_runtime.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE (1600 * 24 + 256)
#define MAX_LABELS 32

typedef struct {
	char names[MAX_LABELS][32];
	int n;
} NameTable;

static int load_names_from_json(const char *json_path, NameTable *nt)
{
	FILE *f = fopen(json_path, "r");
	if (!f) {
		perror(json_path);
		return -1;
	}
	char *buf = NULL;
	size_t cap = 0;
	size_t n = 0;
	int c;
	while ((c = fgetc(f)) != EOF) {
		if (n + 1 >= cap) {
			cap = cap ? cap * 2 : 4096;
			char *nb = (char *)realloc(buf, cap);
			if (!nb) {
				free(buf);
				fclose(f);
				return -1;
			}
			buf = nb;
		}
		buf[n++] = (char)c;
	}
	fclose(f);
	if (!buf) {
		return -1;
	}
	buf[n] = '\0';

	nt->n = 0;
	const char *vis = strstr(buf, "\"visemes\"");
	if (!vis) {
		free(buf);
		return -1;
	}
	const char *brace = strchr(vis, '{');
	if (!brace) {
		free(buf);
		return -1;
	}
	const char *p = brace + 1;
	while (*p && *p != '}' && nt->n < MAX_LABELS) {
		while (*p && (isspace((unsigned char)*p) || *p == ',')) {
			p++;
		}
		if (*p == '}') {
			break;
		}
		if (*p != '"') {
			free(buf);
			return -1;
		}
		p++;
		const char *name_start = p;
		while (*p && *p != '"') {
			p++;
		}
		if (!*p) {
			free(buf);
			return -1;
		}
		size_t namelen = (size_t)(p - name_start);
		if (namelen >= sizeof(nt->names[0])) {
			namelen = sizeof(nt->names[0]) - 1;
		}
		p++;
		while (*p && (isspace((unsigned char)*p) || *p == ':')) {
			p++;
		}
		int id = (int)strtol(p, (char **)&p, 10);
		if (id < 0 || id >= MAX_LABELS) {
			free(buf);
			return -1;
		}
		char tmp[32];
		memcpy(tmp, name_start, namelen);
		tmp[namelen] = '\0';
		memcpy(nt->names[id], tmp, sizeof(tmp));
		if (id + 1 > nt->n) {
			nt->n = id + 1;
		}
		while (*p && *p != ',' && *p != '}') {
			p++;
		}
	}
	free(buf);
	return nt->n > 0 ? 0 : -1;
}

static void softmax(const float *logits, float *out, int n)
{
	float m = logits[0];
	for (int i = 1; i < n; i++) {
		if (logits[i] > m) {
			m = logits[i];
		}
	}
	float sum = 0.f;
	for (int i = 0; i < n; i++) {
		out[i] = expf(logits[i] - m);
		sum += out[i];
	}
	if (sum <= 0.f) {
		sum = 1.f;
	}
	for (int i = 0; i < n; i++) {
		out[i] /= sum;
	}
}

static int split_csv_line(char *line, char **fields, int max_fields)
{
	int n = 0;
	char *p = line;
	while (n < max_fields) {
		fields[n++] = p;
		char *comma = strchr(p, ',');
		if (!comma) {
			break;
		}
		*comma = '\0';
		p = comma + 1;
	}
	if (n > 0) {
		char *last = fields[n - 1];
		size_t L = strlen(last);
		while (L > 0 && (last[L - 1] == '\n' || last[L - 1] == '\r')) {
			last[--L] = '\0';
		}
	}
	return n;
}

int main(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "usage: %s labels.json model.onnx demo_inputs.csv\n", argv[0]);
		return 2;
	}
	const char *json_path = argv[1];
	const char *onnx_path = argv[2];
	const char *csv_path = argv[3];

	NameTable names;
	if (load_names_from_json(json_path, &names) != 0) {
		fprintf(stderr, "failed to parse visemes from %s\n", json_path);
		return 1;
	}

	OnnxRuntime *rt = onnx_runtime_create(onnx_path);
	if (!rt) {
		fprintf(stderr, "onnx_runtime_create failed\n");
		return 1;
	}

	int nfeat = onnx_runtime_input_size(rt);
	int nv = onnx_runtime_output_size(rt);
	if (nv > names.n) {
		fprintf(stderr, "runtime output=%d > json names=%d\n", nv, names.n);
		onnx_runtime_destroy(rt);
		return 1;
	}

	FILE *csv = fopen(csv_path, "r");
	if (!csv) {
		perror(csv_path);
		onnx_runtime_destroy(rt);
		return 1;
	}

	char *line = (char *)malloc(MAX_LINE);
	float *ctx = (float *)malloc((size_t)nfeat * sizeof(float));
	float *logits = (float *)malloc((size_t)nv * sizeof(float));
	float *w = (float *)calloc((size_t)nv, sizeof(float));
	if (!line || !ctx || !logits || !w) {
		fprintf(stderr, "oom\n");
		free(line);
		free(ctx);
		free(logits);
		free(w);
		fclose(csv);
		onnx_runtime_destroy(rt);
		return 1;
	}

	if (!fgets(line, MAX_LINE, csv)) {
		fprintf(stderr, "empty csv\n");
		free(line);
		free(ctx);
		free(logits);
		free(w);
		fclose(csv);
		onnx_runtime_destroy(rt);
		return 1;
	}

	char *hdr_fields[2048];
	int nh = split_csv_line(line, hdr_fields, 2048);
	if (nh < 3 + nfeat) {
		fprintf(stderr, "csv header fields=%d need >= %d\n", nh, 3 + nfeat);
		free(line);
		free(ctx);
		free(logits);
		free(w);
		fclose(csv);
		onnx_runtime_destroy(rt);
		return 1;
	}

	printf("%5s  %-8s  %-8s  %7s  hit\n", "probe", "expect", "predict", "P(exp)");
	int hits = 0;
	int n = 0;

	while (fgets(line, MAX_LINE, csv)) {
		if (line[0] == '\0' || line[0] == '\n') {
			continue;
		}
		char *fields[2048];
		int nf = split_csv_line(line, fields, 2048);
		if (nf < 3 + nfeat) {
			continue;
		}
		int probe_id = atoi(fields[0]);
		int expect_id = atoi(fields[1]);
		const char *expect_name = fields[2];
		for (int i = 0; i < nfeat; i++) {
			ctx[i] = strtof(fields[3 + i], NULL);
		}
		int out_len = 0;
		if (onnx_runtime_predict(rt, ctx, nfeat, logits, nv, &out_len) != 0) {
			fprintf(stderr, "predict failed probe=%d\n", probe_id);
			free(line);
			free(ctx);
			free(logits);
			free(w);
			fclose(csv);
			onnx_runtime_destroy(rt);
			return 1;
		}
		softmax(logits, w, nv);
		int pred = 0;
		for (int i = 1; i < nv; i++) {
			if (w[i] > w[pred]) {
				pred = i;
			}
		}
		int hit = (pred == expect_id);
		hits += hit;
		n++;
		const char *pred_name = (pred >= 0 && pred < names.n) ? names.names[pred] : "?";
		float p_exp = (expect_id >= 0 && expect_id < nv) ? w[expect_id] : 0.f;
		printf("%5d  %-8s  %-8s  %7.3f  %s\n", probe_id, expect_name, pred_name, p_exp,
		       hit ? "Y" : ".");
	}

	printf("hit_rate=%d/%d\n", hits, n);
	printf("ONNX_LOADER_CSV_SMOKE_OK rows=%d\n", n);

	free(line);
	free(ctx);
	free(logits);
	free(w);
	fclose(csv);
	onnx_runtime_destroy(rt);
	onnx_runtime_shutdown();
	return n > 0 ? 0 : 1;
}
