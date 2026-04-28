#ifndef S_SEED_ERROR_H
#define S_SEED_ERROR_H

#include <stdbool.h>
#include <stddef.h>

typedef enum error_code {
	ERR_NONE = 0,
	ERR_ILLEGAL_CHAR,
	ERR_UNTERMINATED_STRING,
	ERR_OUT_OF_MEMORY,
	ERR_SYNTAX,
	ERR_SEMANTIC,
} error_code;

typedef struct compile_error {
	error_code code;
	size_t line;
	size_t column;
	char message[256];
} compile_error;

void error_clear(compile_error *err);
void error_set(compile_error *err, error_code code, size_t line, size_t column, const char *fmt, ...);
bool error_is_set(const compile_error *err);

#endif