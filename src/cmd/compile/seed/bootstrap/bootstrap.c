#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "../error/error.h"

bool seed_compile_source_text(const char *source_text, FILE *output, compile_error *err);

static bool ensure_dir(const char *path, compile_error *err) {
	if (mkdir(path, 0755) == 0) {
		return true;
	}
	if (errno == EEXIST) {
		return true;
	}
	error_set(err, ERR_SEMANTIC, 0, 0, "failed to create dir: %s", path);
	return false;
}

static bool read_file_text(const char *path, char **out_text, compile_error *err) {
	FILE *fp;
	long n;
	size_t read_n;
	char *buf;

	*out_text = NULL;
	fp = fopen(path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open source: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek source: %s", path);
		return false;
	}
	n = ftell(fp);
	if (n < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to measure source: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind source: %s", path);
		return false;
	}

	buf = (char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	read_n = fread(buf, 1, (size_t)n, fp);
	fclose(fp);
	if (read_n != (size_t)n) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read source: %s", path);
		return false;
	}
	buf[n] = '\0';
	*out_text = buf;
	return true;
}

static bool compile_to_buffer(const char *source_text, char **out_text, compile_error *err) {
	FILE *tmp;
	char *buf;
	long n;
	size_t read_n;

	*out_text = NULL;
	tmp = tmpfile();
	if (!tmp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create temporary file");
		return false;
	}

	if (!seed_compile_source_text(source_text, tmp, err)) {
		fclose(tmp);
		return false;
	}
	if (fflush(tmp) != 0) {
		fclose(tmp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to flush temporary output");
		return false;
	}
	if (fseek(tmp, 0, SEEK_END) != 0) {
		fclose(tmp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek temporary output");
		return false;
	}
	n = ftell(tmp);
	if (n < 0) {
		fclose(tmp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to measure temporary output");
		return false;
	}
	if (fseek(tmp, 0, SEEK_SET) != 0) {
		fclose(tmp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind temporary output");
		return false;
	}

	buf = (char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(tmp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	read_n = fread(buf, 1, (size_t)n, tmp);
	fclose(tmp);
	if (read_n != (size_t)n) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read temporary output");
		return false;
	}
	buf[n] = '\0';
	*out_text = buf;
	return true;
}

static bool write_text_file(const char *path, const char *text, compile_error *err) {
	FILE *fp = fopen(path, "wb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write: %s", path);
		return false;
	}
	if (text && text[0] != '\0') {
		size_t n = strlen(text);
		if (fwrite(text, 1, n, fp) != n) {
			fclose(fp);
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to write: %s", path);
			return false;
		}
	}
	if (fclose(fp) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close: %s", path);
		return false;
	}
	return true;
}

bool seed_bootstrap_two_stage_check(const char *compiler_source_path, const char *output_dir, compile_error *err) {
	char *compiler_src = NULL;
	char *stage1 = NULL;
	char *stage2 = NULL;
	char stage1_path[512];
	char stage2_path[512];
	bool ok = false;

	error_clear(err);
	if (!compiler_source_path || !output_dir) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid bootstrap input");
		return false;
	}

	if (!ensure_dir(output_dir, err)) {
		goto done;
	}

	if (!read_file_text(compiler_source_path, &compiler_src, err)) {
		goto done;
	}

	if (!compile_to_buffer(compiler_src, &stage1, err)) {
		goto done;
	}

	if (!compile_to_buffer(compiler_src, &stage2, err)) {
		goto done;
	}

	snprintf(stage1_path, sizeof(stage1_path), "%s/stage1.ir", output_dir);
	snprintf(stage2_path, sizeof(stage2_path), "%s/stage2.ir", output_dir);
	if (!write_text_file(stage1_path, stage1, err) || !write_text_file(stage2_path, stage2, err)) {
		goto done;
	}

	if (strcmp(stage1, stage2) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "bootstrap mismatch: stage1 and stage2 outputs differ");
		goto done;
	}

	ok = true;

done:
	free(compiler_src);
	free(stage1);
	free(stage2);
	return ok;
}
