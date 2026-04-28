#include "error.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

void error_clear(compile_error *err) {
	if (!err) {
		return;
	}
	err->code = ERR_NONE;
	err->line = 0;
	err->column = 0;
	err->message[0] = '\0';
}

void error_set(compile_error *err, error_code code, size_t line, size_t column, const char *fmt, ...) {
	va_list args;

	if (!err) {
		return;
	}

	err->code = code;
	err->line = line;
	err->column = column;

	if (!fmt) {
		err->message[0] = '\0';
		return;
	}

	va_start(args, fmt);
	vsnprintf(err->message, sizeof(err->message), fmt, args);
	va_end(args);
	err->message[sizeof(err->message) - 1] = '\0';
}

bool error_is_set(const compile_error *err) {
	return err != NULL && err->code != ERR_NONE;
}