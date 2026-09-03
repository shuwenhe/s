#include "target.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static s_target_os parse_os(const char *name) {
	if (!name) return S_TARGET_OS_UNKNOWN;
	if (strcmp(name, "linux") == 0) return S_TARGET_OS_LINUX;
	if (strcmp(name, "darwin") == 0 || strcmp(name, "macos") == 0) return S_TARGET_OS_DARWIN;
	if (strcmp(name, "windows") == 0) return S_TARGET_OS_WINDOWS;
	return S_TARGET_OS_UNKNOWN;
}

static s_target_arch parse_arch(const char *name) {
	if (!name) return S_TARGET_ARCH_UNKNOWN;
	if (strcmp(name, "amd64") == 0 || strcmp(name, "x86_64") == 0) return S_TARGET_ARCH_AMD64;
	if (strcmp(name, "arm64") == 0 || strcmp(name, "aarch64") == 0) return S_TARGET_ARCH_ARM64;
	if (strcmp(name, "386") == 0 || strcmp(name, "i386") == 0) return S_TARGET_ARCH_386;
	return S_TARGET_ARCH_UNKNOWN;
}

const char *s_target_os_name(s_target_os os) {
	switch (os) {
		case S_TARGET_OS_LINUX: return "linux";
		case S_TARGET_OS_DARWIN: return "darwin";
		case S_TARGET_OS_WINDOWS: return "windows";
		default: return "unknown";
	}
}

const char *s_target_arch_name(s_target_arch arch) {
	switch (arch) {
		case S_TARGET_ARCH_AMD64: return "amd64";
		case S_TARGET_ARCH_ARM64: return "arm64";
		case S_TARGET_ARCH_386: return "386";
		default: return "unknown";
	}
}

const char *s_target_object_format(const s_target_platform *target) {
	if (!target) return "unknown";
	if (target->os == S_TARGET_OS_LINUX) return "elf";
	if (target->os == S_TARGET_OS_DARWIN) return "macho";
	if (target->os == S_TARGET_OS_WINDOWS) return "pe";
	return "unknown";
}

bool s_target_platform_parse(const char *text, s_target_platform *target, char *detail, size_t detail_size) {
	const char *slash;
	char os[32];
	char arch[32];
	size_t os_len;
	if (!text || !target) return false;
	slash = strchr(text, '/');
	if (!slash || slash == text || slash[1] == '\0' || strchr(slash + 1, '/')) {
		if (detail && detail_size) snprintf(detail, detail_size, "target must be OS/ARCH, got %s", text);
		return false;
	}
	os_len = (size_t)(slash - text);
	if (os_len >= sizeof(os) || strlen(slash + 1) >= sizeof(arch)) {
		if (detail && detail_size) snprintf(detail, detail_size, "target name is too long");
		return false;
	}
	memcpy(os, text, os_len);
	os[os_len] = '\0';
	strcpy(arch, slash + 1);
	target->os = parse_os(os);
	target->arch = parse_arch(arch);
	if (target->os == S_TARGET_OS_UNKNOWN || target->arch == S_TARGET_ARCH_UNKNOWN) {
		if (detail && detail_size) snprintf(detail, detail_size, "unsupported target %s", text);
		return false;
	}
	if (detail && detail_size) snprintf(detail, detail_size, "%s/%s (%s)", s_target_os_name(target->os), s_target_arch_name(target->arch), s_target_object_format(target));
	return true;
}

bool s_target_platform_from_environment(s_target_platform *target, char *detail, size_t detail_size) {
	const char *os = getenv("S_TARGET_OS");
	const char *arch = getenv("S_TARGET_ARCH");
	char triple[80];
	if (!os || !*os) {
#if defined(__APPLE__)
		os = "darwin";
#elif defined(_WIN32)
		os = "windows";
#elif defined(__linux__)
		os = "linux";
#else
		os = "unknown";
#endif
	}
	if (!arch || !*arch) {
#if defined(__aarch64__) || defined(_M_ARM64)
		arch = "arm64";
#elif defined(__x86_64__) || defined(_M_X64)
		arch = "amd64";
#elif defined(__i386__) || defined(_M_IX86)
		arch = "386";
#else
		arch = "unknown";
#endif
	}
	snprintf(triple, sizeof(triple), "%s/%s", os, arch);
	return s_target_platform_parse(triple, target, detail, detail_size);
}

bool s_target_platform_supports_standalone(const s_target_platform *target) {
	/* darwin/arm64 uses the hosted native path until its direct S backend lands. */
	return target && ((target->os == S_TARGET_OS_LINUX && target->arch == S_TARGET_ARCH_AMD64) ||
		(target->os == S_TARGET_OS_DARWIN && target->arch == S_TARGET_ARCH_ARM64));
}

static bool require_aot_target(s_target_platform *target, compile_error *err) {
	char detail[256];
	if (!s_target_platform_from_environment(target, detail, sizeof(detail))) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid AOT target: %s", detail);
		return false;
	}
	if (!s_target_platform_supports_standalone(target)) {
		error_set(err, ERR_SEMANTIC, 0, 0,
			"AOT target %s/%s is not implemented; available targets: linux/amd64, darwin/arm64",
			s_target_os_name(target->os), s_target_arch_name(target->arch));
		return false;
	}
	return true;
}

bool emit_aot_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err) {
	s_target_platform target;
	error_clear(err);
	if (!require_aot_target(&target, err)) return false;
	if (target.os == S_TARGET_OS_DARWIN && target.arch == S_TARGET_ARCH_ARM64) {
		return emit_native_from_ir_file(input_ir_path, output_binary_path, err);
	}
	return emit_standalone_amd64_from_ir_file(input_ir_path, output_binary_path, err);
}

bool emit_aot_assembly_from_ir_file(const char *input_ir_path, const char *output_assembly_path, compile_error *err) {
	s_target_platform target;
	error_clear(err);
	if (!require_aot_target(&target, err)) return false;
	if (target.os == S_TARGET_OS_DARWIN && target.arch == S_TARGET_ARCH_ARM64) {
		error_set(err, ERR_SEMANTIC, 0, 0,
			"darwin/arm64 AOT assembly emission is not exposed; use --emit-aot for the hosted native compiler");
		return false;
	}
	return emit_standalone_amd64_assembly_from_ir_file(input_ir_path, output_assembly_path, err);
}

bool emit_aot_object_from_ir_file(const char *input_ir_path, const char *output_object_path, compile_error *err) {
	s_target_platform target;
	error_clear(err);
	if (!require_aot_target(&target, err)) return false;
	if (target.os == S_TARGET_OS_DARWIN && target.arch == S_TARGET_ARCH_ARM64) {
		error_set(err, ERR_SEMANTIC, 0, 0,
			"darwin/arm64 AOT object emission is not exposed; use --emit-aot for the hosted native compiler");
		return false;
	}
	return emit_standalone_amd64_object_from_ir_file(input_ir_path, output_object_path, err);
}

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
