#include "target.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

const char *s_target_backend_name(s_target_backend backend) {
	switch (backend) {
		case S_TARGET_NATIVE: return "native";
		case S_TARGET_C_ABI: return "c-abi";
		case S_TARGET_CUDA: return "cuda";
		case S_TARGET_CANN: return "cann";
		default: return "unknown";
	}
}

static int find_on_path(const char *binary, char *out, size_t out_size) {
	const char *path = getenv("PATH");
	char *copy;
	char *part;
	if (!path || !binary || !out || out_size == 0) return 0;
	copy = (char *)malloc(strlen(path) + 1);
	if (!copy) return 0;
	strcpy(copy, path);
	part = strtok(copy, ":");
	while (part) {
		int n = snprintf(out, out_size, "%s/%s", part, binary);
		if (n > 0 && (size_t)n < out_size && access(out, X_OK) == 0) {
			free(copy);
			return 1;
		}
		part = strtok(NULL, ":");
	}
	free(copy);
	out[0] = '\0';
	return 0;
}

bool s_target_backend_probe(s_target_backend backend, char *detail, size_t detail_size) {
	char tool[512] = {0};
	const char *home;
	if (!detail || detail_size == 0) return false;
	detail[0] = '\0';
	if (backend == S_TARGET_NATIVE || backend == S_TARGET_C_ABI) {
		snprintf(detail, detail_size, "available");
		return true;
	}
	if (backend == S_TARGET_CUDA) {
		if (find_on_path("nvcc", tool, sizeof(tool)) || access("/usr/local/cuda/bin/nvcc", X_OK) == 0) {
			snprintf(detail, detail_size, "available: nvcc=%s", tool[0] ? tool : "/usr/local/cuda/bin/nvcc");
			return true;
		}
		snprintf(detail, detail_size, "unavailable: install CUDA Toolkit and put nvcc on PATH");
		return false;
	}
	if (backend == S_TARGET_CANN) {
		home = getenv("ASCEND_HOME_PATH");
		if (!home) home = getenv("CANN_HOME");
		if (find_on_path("ccec_compiler", tool, sizeof(tool))) {
			snprintf(detail, detail_size, "available: ccec_compiler=%s", tool);
			return true;
		}
		if (home && access(home, R_OK) == 0) {
			snprintf(detail, detail_size, "available: toolkit=%s", home);
			return true;
		}
		snprintf(detail, detail_size, "unavailable: source CANN set_env.sh or set ASCEND_HOME_PATH");
		return false;
	}
	snprintf(detail, detail_size, "unknown backend");
	return false;
}
