#include <stdbool.h>
#include <stdio.h>

#include "../error/error.h"
#include "../intermediate/ir.h"
#include "../lexical/token.h"
#include "../runtime/memory.h"
#include "../semantic/scope.h"
#include "../syntax/ast.h"

bool seed_compile_source_text(const char *source_text, FILE *output, compile_error *err);

static bool execute_source_main(const char *src, long *ret, compile_error *err) {
	FILE *tmp;
	char buf[8192];
	size_t n;

	tmp = tmpfile();
	if (!tmp) {
		return false;
	}
	if (!seed_compile_source_text(src, tmp, err)) {
		fclose(tmp);
		return false;
	}
	fflush(tmp);
	fseek(tmp, 0, SEEK_SET);
	n = fread(buf, 1, sizeof(buf) - 1, tmp);
	buf[n] = '\0';
	fclose(tmp);
	return runtime_execute_text(buf, "main", ret, err);
}

static bool test_runtime_array_len_and_index(void) {
	const char *src =
		"fn main() int { "
		"  var xs = [4, 7, 9]; "
		"  return len(xs) + xs[1]; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 10;
}

static bool test_runtime_array_index_assignment(void) {
	const char *src =
		"fn main() int { "
		"  var xs = []float{cap: 3}; "
		"  var i = 0; "
		"  while i < 3 { "
		"    xs[i] = i + 1; "
		"    i = i + 1; "
		"  } "
		"  return len(xs) + xs[2]; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 6;
}

static bool test_runtime_nested_member_alias_compare(void) {
	const char *src =
		"fn main() int { "
		"  var cfg = Config { activation_type: \"gelu\" }; "
		"  var layer = Layer { config: cfg }; "
		"  if layer.config.activation_type == \"gelu\" { return 1; } "
		"  return 0; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 1;
}

static bool test_runtime_nested_member_return_alias(void) {
	const char *src =
		"fn build_network() Network { "
		"  Network { width: 7 } "
		"} "
		"fn main() int { "
		"  var layer = Layer { network: build_network() }; "
		"  return layer.network.width; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 7;
}

int main(void) {
	bool ok = true;

	if (!test_runtime_array_len_and_index()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_array_len_and_index");
		ok = false;
	}
	if (!test_runtime_array_index_assignment()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_array_index_assignment");
		ok = false;
	}
	if (!test_runtime_nested_member_alias_compare()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_nested_member_alias_compare");
		ok = false;
	}
	if (!test_runtime_nested_member_return_alias()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_nested_member_return_alias");
		ok = false;
	}

	if (!ok) {
		fprintf(stderr, "seed runtime regression tests failed\n");
		return 1;
	}

	printf("seed runtime regression tests passed\n");
	return 0;
}
