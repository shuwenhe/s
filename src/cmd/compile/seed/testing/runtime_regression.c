#include <arpa/inet.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "../error/error.h"
#include "../intermediate/ir.h"
#include "../lexical/token.h"
#include "../runtime/memory.h"
#include "../semantic/scope.h"
#include "../syntax/ast.h"

bool seed_compile_source_text(const char *source_text, FILE *output, compile_error *err);

typedef struct loopback_client_ctx {
	int port;
	int result;
} loopback_client_ctx;

static void *loopback_client_main(void *opaque) {
	loopback_client_ctx *ctx = (loopback_client_ctx *)opaque;
	struct sockaddr_in addr;
	int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	char value = 'x';
	ctx->result = 0;
	if (fd < 0) return NULL;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons((unsigned short)ctx->port);
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 && write(fd, &value, 1) == 1) ctx->result = 1;
	close(fd);
	return NULL;
}

typedef struct close_race_ctx {
	int fd;
	ssize_t result;
} close_race_ctx;

static void *close_race_reader(void *opaque) {
	close_race_ctx *ctx = (close_race_ctx *)opaque;
	char byte;
	ctx->result = read(ctx->fd, &byte, 1);
	return NULL;
}

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

static bool execute_network_source_main(const char *name, const char *src, long *ret, compile_error *err) {
	bool ok;
	error_clear(err);
	ok = execute_source_main(src, ret, err);
	if (!ok && error_is_set(err)) {
		fprintf(stderr, "%s: error[%d] at %zu:%zu: %s\n", name, (int)err->code, err->line, err->column, err->message);
	} else if (ok && *ret != 1) {
		fprintf(stderr, "%s: returned %ld\n", name, *ret);
	}
	return ok;
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

static bool test_runtime_host_file_operations(void) {
	const char *path = "/tmp/s_seed_runtime_file_test.txt";
	const char *src =
		"fn main() int { "
		"  if __host_write_text_file(\"/tmp/s_seed_runtime_file_test.txt\", \"hello from s\") < 0 { return 0; } "
		"  if __host_read_to_string(\"/tmp/s_seed_runtime_file_test.txt\") == \"hello from s\" { return 1; } "
		"  return 0; "
		"}";
	compile_error err;
	long ret = 0;
	bool ok = execute_source_main(src, &ret, &err) && ret == 1;
	remove(path);
	return ok;
}

static bool test_runtime_host_socket_operations(void) {
	const char *src =
		"extern \"libc:socket\" func native_socket(int domain, int kind, int protocol) int; "
		"extern \"libc:close\" func native_close(int fd) int; "
		"fn main() int { "
		"  var fd = native_socket(2, 1, 6); "
		"  if fd < 0 { return 0; } "
		"  if native_close(fd) < 0 { return 0; } "
		"  return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 1;
}

static bool test_runtime_tcp_loopback(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_listen(int fd, int backlog) int; "
		"extern \"intrinsic\" func __sys_accept(int fd) int; "
		"extern \"intrinsic\" func __sys_connect_deadline(int fd, string ip, int port, int family, int timeout_ms) int; "
		"extern \"intrinsic\" func __sys_local_port(int fd) int; "
		"extern \"intrinsic\" func __sys_write_string(int fd, string data) int; "
		"extern \"intrinsic\" func __sys_read_string(int fd, int size) string; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"extern \"intrinsic\" func __sys_errno() int; "
		"fn main() int { "
		"  var server = __sys_socket(2, 1, 6); if server < 0 { return 10; } "
		"  if __sys_bind(server, \"127.0.0.1\", 0, 2) < 0 { var code = __sys_errno(); __sys_close(server); return 100 + code; } "
		"  var port = __sys_local_port(server); if port <= 0 { __sys_close(server); return 12; } "
		"  if __sys_listen(server, 8) < 0 { __sys_close(server); return 13; } "
		"  var client = __sys_socket(2, 1, 6); if client < 0 { __sys_close(server); return 14; } "
		"  if __sys_connect_deadline(client, \"localhost\", port, 2, 1000) < 0 { __sys_close(client); __sys_close(server); return 15; } "
		"  var accepted = __sys_accept(server); if accepted < 0 { __sys_close(client); __sys_close(server); return 16; } "
		"  var written = __sys_write_string(client, \"tcp-loopback\"); "
		"  var data = __sys_read_string(accepted, 64); "
		"  __sys_close(accepted); __sys_close(client); __sys_close(server); "
		"  if written != 12 { return 17; } if data != \"tcp-loopback\" { return 18; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("tcp_loopback", src, &ret, &err) && ret == 1;
}

static bool test_runtime_udp_loopback(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_local_port(int fd) int; "
		"extern \"intrinsic\" func __sys_sendto_string(int fd, string data, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_recvfrom_string(int fd, int size) string; "
		"extern \"intrinsic\" func __sys_last_recvfrom_ip() string; "
		"extern \"intrinsic\" func __sys_last_recvfrom_port() int; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"extern \"intrinsic\" func __sys_errno() int; "
		"fn main() int { "
		"  var server = __sys_socket(2, 2, 17); if server < 0 { return 20; } "
		"  if __sys_bind(server, \"127.0.0.1\", 0, 2) < 0 { var code = __sys_errno(); __sys_close(server); return 200 + code; } "
		"  var port = __sys_local_port(server); "
		"  var client = __sys_socket(2, 2, 17); if client < 0 { __sys_close(server); return 22; } "
		"  if __sys_bind(client, \"127.0.0.1\", 0, 2) < 0 { return 25; } var client_port = __sys_local_port(client); "
		"  var written = __sys_sendto_string(client, \"udp-loopback\", \"127.0.0.1\", port, 2); "
		"  var data = __sys_recvfrom_string(server, 64); var peer_ip = __sys_last_recvfrom_ip(); var peer_port = __sys_last_recvfrom_port(); "
		"  __sys_close(client); __sys_close(server); "
		"  if written != 12 { return 23; } if data != \"udp-loopback\" { return 24; } "
		"  if peer_ip != \"127.0.0.1\" { return 26; } if peer_port != client_port { return 27; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("udp_loopback", src, &ret, &err) && ret == 1;
}

static bool test_runtime_socket_timeout(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_set_deadline_ms(int fd, int read_ms, int write_ms) int; "
		"extern \"intrinsic\" func __sys_poll_ready(int fd, int events, int timeout_ms) int; "
		"extern \"intrinsic\" func __sys_recvfrom_string(int fd, int size) string; "
		"extern \"intrinsic\" func __sys_errno() int; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"fn main() int { "
		"  var fd = __sys_socket(2, 2, 17); if fd < 0 { return 30; } "
		"  if __sys_bind(fd, \"127.0.0.1\", 0, 2) < 0 { var bind_code = __sys_errno(); __sys_close(fd); return 300 + bind_code; } "
		"  if __sys_poll_ready(fd, 1, 5) != 0 { __sys_close(fd); return 32; } "
		"  if __sys_set_deadline_ms(fd, 20, 20) < 0 { __sys_close(fd); return 33; } "
		"  var data = __sys_recvfrom_string(fd, 8); var code = __sys_errno(); __sys_close(fd); "
		"  if data != \"\" { return 34; } if code == 0 { return 35; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("socket_timeout", src, &ret, &err) && ret == 1;
}

static bool test_runtime_network_poller(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_listen(int fd, int backlog) int; "
		"extern \"intrinsic\" func __sys_accept(int fd) int; "
		"extern \"intrinsic\" func __sys_connect(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_local_port(int fd) int; "
		"extern \"intrinsic\" func __sys_write_string(int fd, string data) int; "
		"extern \"intrinsic\" func __sys_poller_create() int; "
		"extern \"intrinsic\" func __sys_poller_add(int poller_fd, int fd, int events) int; "
		"extern \"intrinsic\" func __sys_poller_del(int poller_fd, int fd) int; "
		"extern \"intrinsic\" func __sys_poller_wait(int poller_fd, int max_events, int timeout_ms) []int; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"fn main() int { "
		"  var server = __sys_socket(2, 1, 6); if server < 0 { return 40; } "
		"  if __sys_bind(server, \"127.0.0.1\", 0, 2) < 0 { __sys_close(server); return 41; } "
		"  if __sys_listen(server, 8) < 0 { __sys_close(server); return 42; } "
		"  var client = __sys_socket(2, 1, 6); "
		"  if __sys_connect(client, \"127.0.0.1\", __sys_local_port(server), 2) < 0 { return 43; } "
		"  var accepted = __sys_accept(server); var poller = __sys_poller_create(); "
		"  if poller < 0 { return 44; } if __sys_poller_add(poller, accepted, 1) < 0 { return 45; } "
		"  __sys_write_string(client, \"ready\"); var ready = __sys_poller_wait(poller, 4, 1000); "
		"  __sys_poller_del(poller, accepted); __sys_close(poller); __sys_close(accepted); __sys_close(client); __sys_close(server); "
		"  if len(ready) != 1 { return 46; } if ready[0] != accepted { return 47; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("network_poller", src, &ret, &err) && ret == 1;
}

static bool test_runtime_dns_and_interfaces(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_resolve_ip(string host, int family) []string; "
		"extern \"intrinsic\" func __sys_interface_addresses() []string; "
		"fn main() int { "
		"  var addresses = __sys_resolve_ip(\"localhost\", 0); if len(addresses) == 0 { return 50; } "
		"  var interfaces = __sys_interface_addresses(); if len(interfaces) == 0 { return 51; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("dns_and_interfaces", src, &ret, &err) && ret == 1;
}

static bool test_runtime_ipv6_loopback(void) {
	const char *src =
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_listen(int fd, int backlog) int; "
		"extern \"intrinsic\" func __sys_accept(int fd) int; "
		"extern \"intrinsic\" func __sys_connect_deadline(int fd, string host, int port, int family, int timeout_ms) int; "
		"extern \"intrinsic\" func __sys_local_port(int fd) int; "
		"extern \"intrinsic\" func __sys_write_string(int fd, string data) int; "
		"extern \"intrinsic\" func __sys_read_string(int fd, int size) string; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"fn main() int { "
		"  var server = __sys_socket(10, 1, 6); if server < 0 { return 52; } "
		"  if __sys_bind(server, \"::1\", 0, 10) < 0 { __sys_close(server); return 53; } "
		"  if __sys_listen(server, 4) < 0 { __sys_close(server); return 54; } "
		"  var client = __sys_socket(10, 1, 6); "
		"  if __sys_connect_deadline(client, \"::1\", __sys_local_port(server), 10, 1000) < 0 { return 55; } "
		"  var accepted = __sys_accept(server); __sys_write_string(client, \"ipv6\"); var data = __sys_read_string(accepted, 16); "
		"  __sys_close(accepted); __sys_close(client); __sys_close(server); if data != \"ipv6\" { return 56; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	return execute_network_source_main("ipv6_loopback", src, &ret, &err) && ret == 1;
}

static bool test_runtime_sendfile(void) {
	const char *path = "/tmp/s_seed_sendfile_test.txt";
	const char *src =
		"extern \"intrinsic\" func __host_write_text_file(string path, string data) int; "
		"extern \"intrinsic\" func __sys_open_read(string path) int; "
		"extern \"intrinsic\" func __sys_socket(int domain, int kind, int protocol) int; "
		"extern \"intrinsic\" func __sys_bind(int fd, string ip, int port, int family) int; "
		"extern \"intrinsic\" func __sys_listen(int fd, int backlog) int; "
		"extern \"intrinsic\" func __sys_accept(int fd) int; "
		"extern \"intrinsic\" func __sys_connect_deadline(int fd, string host, int port, int family, int timeout_ms) int; "
		"extern \"intrinsic\" func __sys_local_port(int fd) int; "
		"extern \"intrinsic\" func __sys_sendfile(int out_fd, int in_fd, int offset, int count) int; "
		"extern \"intrinsic\" func __sys_read_string(int fd, int size) string; "
		"extern \"intrinsic\" func __sys_close(int fd) int; "
		"fn main() int { "
		"  if __host_write_text_file(\"/tmp/s_seed_sendfile_test.txt\", \"sendfile-data\") < 0 { return 60; } "
		"  var input = __sys_open_read(\"/tmp/s_seed_sendfile_test.txt\"); if input < 0 { return 61; } "
		"  var server = __sys_socket(2, 1, 6); if __sys_bind(server, \"127.0.0.1\", 0, 2) < 0 { return 62; } __sys_listen(server, 2); "
		"  var client = __sys_socket(2, 1, 6); if __sys_connect_deadline(client, \"127.0.0.1\", __sys_local_port(server), 2, 1000) < 0 { return 63; } "
		"  var accepted = __sys_accept(server); var sent = __sys_sendfile(accepted, input, 0, 13); var data = __sys_read_string(client, 32); "
		"  __sys_close(input); __sys_close(accepted); __sys_close(client); __sys_close(server); "
		"  if sent != 13 { return 64; } if data != \"sendfile-data\" { return 65; } return 1; "
		"}";
	compile_error err;
	long ret = 0;
	bool ok = execute_network_source_main("sendfile", src, &ret, &err) && ret == 1;
	remove(path);
	return ok;
}

static bool test_native_concurrent_loopback(void) {
	enum { CLIENT_COUNT = 8 };
	int server = -1;
	struct sockaddr_in addr;
	socklen_t addr_len = sizeof(addr);
	pthread_t threads[CLIENT_COUNT];
	loopback_client_ctx contexts[CLIENT_COUNT];
	int created = 0;
	int accepted = 0;
	int i;
	bool ok = false;
	server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (server < 0) return false;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = 0;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    getsockname(server, (struct sockaddr *)&addr, &addr_len) < 0 || listen(server, CLIENT_COUNT) < 0) goto done;
	for (i = 0; i < CLIENT_COUNT; i++) {
		contexts[i].port = (int)ntohs(addr.sin_port);
		contexts[i].result = 0;
		if (pthread_create(&threads[i], NULL, loopback_client_main, &contexts[i]) != 0) goto join;
		created++;
	}
	while (accepted < CLIENT_COUNT) {
		int client = accept(server, NULL, NULL);
		char value = 0;
		if (client < 0) goto join;
		if (read(client, &value, 1) != 1 || value != 'x') { close(client); goto join; }
		close(client);
		accepted++;
	}
join:
	for (i = 0; i < created; i++) pthread_join(threads[i], NULL);
	if (created == CLIENT_COUNT && accepted == CLIENT_COUNT) {
		ok = true;
		for (i = 0; i < CLIENT_COUNT; i++) if (!contexts[i].result) ok = false;
	}
done:
	close(server);
	return ok;
}

static bool test_native_close_unblocks_read(void) {
	int pair[2];
	pthread_t reader;
	close_race_ctx ctx;
	struct timespec delay;
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) < 0) return false;
	ctx.fd = pair[0];
	ctx.result = 1;
	if (pthread_create(&reader, NULL, close_race_reader, &ctx) != 0) {
		close(pair[0]); close(pair[1]); return false;
	}
	delay.tv_sec = 0;
	delay.tv_nsec = 10 * 1000 * 1000;
	nanosleep(&delay, NULL);
	shutdown(pair[0], SHUT_RDWR);
	close(pair[0]);
	pthread_join(reader, NULL);
	close(pair[1]);
	return ctx.result <= 0;
}

static bool test_runtime_libc_ffi(void) {
	const char *src =
		"extern \"libc\" func strlen(string text) int; "
		"fn main() int { return strlen(\"native ffi\"); }";
	compile_error err;
	long ret = 0;
	return execute_source_main(src, &ret, &err) && ret == 10;
}

int main(int argc, char **argv) {
	bool ok = true;
	bool network_only = argc == 2 && strcmp(argv[1], "--network-only") == 0;

	if (!network_only && !test_runtime_array_len_and_index()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_array_len_and_index");
		ok = false;
	}
	if (!network_only && !test_runtime_array_index_assignment()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_array_index_assignment");
		ok = false;
	}
	if (!network_only && !test_runtime_nested_member_alias_compare()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_nested_member_alias_compare");
		ok = false;
	}
	if (!network_only && !test_runtime_nested_member_return_alias()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_nested_member_return_alias");
		ok = false;
	}
	if (!network_only && !test_runtime_host_file_operations()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_host_file_operations");
		ok = false;
	}
	if (!test_runtime_host_socket_operations()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_host_socket_operations");
		ok = false;
	}
	if (!test_runtime_tcp_loopback()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_tcp_loopback");
		ok = false;
	}
	if (!test_runtime_udp_loopback()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_udp_loopback");
		ok = false;
	}
	if (!test_runtime_socket_timeout()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_socket_timeout");
		ok = false;
	}
	if (!test_runtime_network_poller()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_network_poller");
		ok = false;
	}
	if (!test_runtime_dns_and_interfaces()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_dns_and_interfaces");
		ok = false;
	}
	if (!test_runtime_ipv6_loopback()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_ipv6_loopback");
		ok = false;
	}
	if (!test_runtime_sendfile()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_sendfile");
		ok = false;
	}
	if (!test_native_concurrent_loopback()) {
		fprintf(stderr, "FAIL: %s\n", "test_native_concurrent_loopback");
		ok = false;
	}
	if (!test_native_close_unblocks_read()) {
		fprintf(stderr, "FAIL: %s\n", "test_native_close_unblocks_read");
		ok = false;
	}
	if (!network_only && !test_runtime_libc_ffi()) {
		fprintf(stderr, "FAIL: %s\n", "test_runtime_libc_ffi");
		ok = false;
	}

	if (!ok) {
		fprintf(stderr, "seed runtime regression tests failed\n");
		return 1;
	}

	printf("%s passed\n", network_only ? "seed network tests" : "seed runtime regression tests");
	return 0;
}
