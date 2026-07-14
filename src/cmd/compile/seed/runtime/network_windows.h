#ifndef S_SEED_NETWORK_WINDOWS_H
#define S_SEED_NETWORK_WINDOWS_H

#ifdef _WIN32
#include <stddef.h>
#include <stdint.h>
#include <winsock2.h>

int seed_win_network_startup(void);
void seed_win_network_cleanup(void);
SOCKET seed_win_socket(int family, int type, int protocol, int *error_code);
int seed_win_close(SOCKET socket_fd, int *error_code);
int seed_win_bind_or_connect(SOCKET socket_fd, const char *host, int port, int family, int connect_mode, int *error_code);
int seed_win_connect_deadline(SOCKET socket_fd, const char *host, int port, int family, int timeout_ms, int *error_code);
int seed_win_listen(SOCKET socket_fd, int backlog, int *error_code);
SOCKET seed_win_accept(SOCKET socket_fd, int *error_code);
int seed_win_set_deadline(SOCKET socket_fd, int read_timeout_ms, int write_timeout_ms, int *error_code);
int seed_win_poll(SOCKET socket_fd, short events, int timeout_ms, int *error_code);
intptr_t seed_win_iocp_create(int *error_code);
int seed_win_iocp_register(intptr_t port, SOCKET socket_fd, uintptr_t key, int *error_code);
int seed_win_iocp_wait(intptr_t port, int timeout_ms, uintptr_t *key, unsigned long *bytes, int *error_code);
#endif

#endif
