#include "selfhost_bridge.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <sys/wait.h>
#include <unistd.h>
#endif

static char *read_all(const char *path, compile_error *err) {
	FILE *fp = fopen(path, "rb");
	long size;
	char *text;
	if (!fp || fseek(fp, 0, SEEK_END) != 0 || (size = ftell(fp)) < 0 || fseek(fp, 0, SEEK_SET) != 0) {
		if (fp) fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read S lexer output");
		return NULL;
	}
	text = (char *)malloc((size_t)size + 1);
	if (!text) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return NULL;
	}
	if (fread(text, 1, (size_t)size, fp) != (size_t)size) {
		free(text);
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read S lexer output");
		return NULL;
	}
	text[size] = '\0';
	fclose(fp);
	return text;
}

static int hex_value(char ch) {
	if (ch >= '0' && ch <= '9') return ch - '0';
	if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
	if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
	return -1;
}

static char *decode_hex(const char *hex, compile_error *err) {
	size_t len = strlen(hex);
	size_t i;
	char *text;
	if (len % 2 != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid S lexer hex field");
		return NULL;
	}
	text = (char *)malloc(len / 2 + 1);
	if (!text) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return NULL;
	}
	for (i = 0; i < len; i += 2) {
		int hi = hex_value(hex[i]);
		int lo = hex_value(hex[i + 1]);
		if (hi < 0 || lo < 0) {
			free(text);
			error_set(err, ERR_SEMANTIC, 0, 0, "invalid S lexer hex field");
			return NULL;
		}
		text[i / 2] = (char)((hi << 4) | lo);
	}
	text[len / 2] = '\0';
	return text;
}

static int token_type_from_name(const char *name, token_type *out) {
	int value;
	for (value = TOKEN_EOF; value <= TOKEN_SEMICOLON; value++) {
		if (strcmp(token_type_name((token_type)value), name) == 0) {
			*out = (token_type)value;
			return 1;
		}
	}
	return 0;
}

static int parse_size(const char *text, size_t *out) {
	char *end = NULL;
	unsigned long value;
	errno = 0;
	value = strtoul(text, &end, 10);
	if (errno != 0 || !end || *end != '\0') return 0;
	*out = (size_t)value;
	return 1;
}

static bool parse_output(char *text, token_vec *out_tokens, compile_error *err) {
	char *line = text;
	token_vec_init(out_tokens);
	while (line && *line) {
		char *next = strchr(line, '\n');
		char *field1;
		char *field2;
		char *field3;
		if (next) *next++ = '\0';
		field1 = strchr(line, '|');
		if (!field1) goto malformed;
		*field1++ = '\0';
		field2 = strchr(field1, '|');
		if (!field2) goto malformed;
		*field2++ = '\0';
		field3 = strchr(field2, '|');
		if (!field3) goto malformed;
		*field3++ = '\0';
		if (strcmp(line, "ERROR") == 0) {
			char *message = strchr(field3, '|');
			size_t error_line, error_column;
			error_code code = strcmp(field1, "ILLEGAL_CHAR") == 0 ? ERR_ILLEGAL_CHAR :
				strcmp(field1, "UNTERMINATED_STRING") == 0 ? ERR_UNTERMINATED_STRING : ERR_SYNTAX;
			if (!message) goto malformed;
			*message++ = '\0';
			if (!parse_size(field2, &error_line) || !parse_size(field3, &error_column)) goto malformed;
			error_set(err, code, error_line, error_column, "%s", message);
			token_vec_free(out_tokens);
			return false;
		} else {
			token tok;
			char *column_text = strchr(field3, '|');
			if (column_text || !token_type_from_name(line, &tok.type)) goto malformed;
			tok.lexeme = decode_hex(field1, err);
			if (!tok.lexeme) goto failed;
			if (!parse_size(field2, &tok.pos.line) || !parse_size(field3, &tok.pos.column) || !token_vec_push(out_tokens, tok)) {
				free(tok.lexeme);
				goto malformed;
			}
		}
		line = next;
	}
	return true;

malformed:
	error_set(err, ERR_SEMANTIC, 0, 0, "malformed S lexer token stream");
failed:
	token_vec_free(out_tokens);
	return false;
}

bool selfhost_lexer_scan(const char *source, token_vec *out_tokens, compile_error *err) {
#ifdef _WIN32
	(void)source; (void)out_tokens;
	error_set(err, ERR_SEMANTIC, 0, 0, "S lexer bridge is not implemented on Windows");
	return false;
#else
	char input_template[] = "/tmp/s_selfhost_lexer_input_XXXXXX";
	char output_template[] = "/tmp/s_selfhost_lexer_output_XXXXXX";
	const char *lexer = getenv("S_SELFHOST_LEXER");
	int input_fd = -1;
	int output_fd = -1;
	pid_t pid;
	int status;
	char *output = NULL;
	bool ok = false;
	if (!lexer || lexer[0] == '\0') lexer = "./bin/s_lexer";
	input_fd = mkstemp(input_template);
	output_fd = mkstemp(output_template);
	if (input_fd < 0 || output_fd < 0 || write(input_fd, source, strlen(source)) != (ssize_t)strlen(source)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create S lexer bridge files");
		goto done;
	}
	close(input_fd); input_fd = -1;
	close(output_fd); output_fd = -1;
	pid = fork();
	if (pid < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to start S lexer");
		goto done;
	}
	if (pid == 0) {
		execl(lexer, lexer, input_template, output_template, (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "S lexer process failed: %s", lexer);
		goto done;
	}
	output = read_all(output_template, err);
	if (!output) goto done;
	ok = parse_output(output, out_tokens, err);
done:
	if (input_fd >= 0) close(input_fd);
	if (output_fd >= 0) close(output_fd);
	unlink(input_template);
	unlink(output_template);
	free(output);
	return ok;
#endif
}
