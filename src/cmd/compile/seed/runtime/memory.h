#ifndef S_SEED_RUNTIME_MEMORY_H
#define S_SEED_RUNTIME_MEMORY_H

#include <stdbool.h>

#include "../error/error.h"

bool runtime_execute_text(const char *target_text, const char *entry_function, long *out_return, compile_error *err);
bool runtime_execute_text_with_argv(
	const char *target_text,
	const char *entry_function,
	long *out_return,
	compile_error *err,
	int argc,
	char **argv
);
bool runtime_execute_file(const char *target_path, const char *entry_function, long *out_return, compile_error *err);

#endif