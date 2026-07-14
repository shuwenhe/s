#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <string.h>

#include "network_windows.h"

#include <windows.h>
#include <ws2tcpip.h>

#pragma comment(lib, "Ws2_32.lib")

static int native_family(int family) {
	if (family == 2) return AF_INET;
	if (family == 10) return AF_INET6;
	return family;
}

static int resolve_address(const char *host, int port, int family, struct sockaddr_storage *storage, int *length) {
	struct addrinfo hints;
	struct addrinfo *result = NULL;
	char service[16];
	int rc;
	ZeroMemory(&hints, sizeof(hints));
	hints.ai_family = native_family(family);
	hints.ai_socktype = 0;
	hints.ai_protocol = 0;
	_snprintf_s(service, sizeof(service), _TRUNCATE, "%d", port);
	rc = getaddrinfo(host && *host ? host : NULL, service, &hints, &result);
	if (rc != 0 || !result || result->ai_addrlen > sizeof(*storage)) {
		if (result) freeaddrinfo(result);
		WSASetLastError(rc != 0 ? rc : WSAEINVAL);
		return 0;
	}
	ZeroMemory(storage, sizeof(*storage));
	memcpy(storage, result->ai_addr, result->ai_addrlen);
	*length = (int)result->ai_addrlen;
	freeaddrinfo(result);
	return 1;
}

int seed_win_network_startup(void) {
	WSADATA data;
	return WSAStartup(MAKEWORD(2, 2), &data);
}

void seed_win_network_cleanup(void) { WSACleanup(); }

SOCKET seed_win_socket(int family, int type, int protocol, int *error_code) {
	SOCKET fd = WSASocketW(native_family(family), type, protocol, NULL, 0, WSA_FLAG_OVERLAPPED);
	if (error_code) *error_code = fd == INVALID_SOCKET ? WSAGetLastError() : 0;
	return fd;
}

int seed_win_close(SOCKET socket_fd, int *error_code) {
	int rc = closesocket(socket_fd);
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

int seed_win_bind_or_connect(SOCKET socket_fd, const char *host, int port, int family, int connect_mode, int *error_code) {
	struct sockaddr_storage storage;
	int length = 0;
	int rc;
	if (!resolve_address(host, port, family, &storage, &length)) {
		if (error_code) *error_code = WSAGetLastError();
		return SOCKET_ERROR;
	}
	rc = connect_mode ? connect(socket_fd, (struct sockaddr *)&storage, length)
	                  : bind(socket_fd, (struct sockaddr *)&storage, length);
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

int seed_win_connect_deadline(SOCKET socket_fd, const char *host, int port, int family, int timeout_ms, int *error_code) {
	u_long nonblocking = 1;
	u_long blocking = 0;
	WSAPOLLFD poll_fd;
	int rc;
	int socket_error = 0;
	int error_length = sizeof(socket_error);
	if (timeout_ms < 0 || ioctlsocket(socket_fd, FIONBIO, &nonblocking) == SOCKET_ERROR) {
		if (error_code) *error_code = timeout_ms < 0 ? WSAEINVAL : WSAGetLastError();
		return SOCKET_ERROR;
	}
	rc = seed_win_bind_or_connect(socket_fd, host, port, family, 1, error_code);
	if (rc == SOCKET_ERROR && WSAGetLastError() == WSAEWOULDBLOCK) {
		poll_fd.fd = socket_fd;
		poll_fd.events = POLLWRNORM;
		poll_fd.revents = 0;
		rc = WSAPoll(&poll_fd, 1, timeout_ms);
		if (rc == 0) {
			WSASetLastError(WSAETIMEDOUT);
			rc = SOCKET_ERROR;
		} else if (rc > 0) {
			if (getsockopt(socket_fd, SOL_SOCKET, SO_ERROR, (char *)&socket_error, &error_length) == SOCKET_ERROR || socket_error != 0) {
				WSASetLastError(socket_error ? socket_error : WSAGetLastError());
				rc = SOCKET_ERROR;
			} else {
				rc = 0;
			}
		}
	}
	(void)ioctlsocket(socket_fd, FIONBIO, &blocking);
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

int seed_win_listen(SOCKET socket_fd, int backlog, int *error_code) {
	int rc = listen(socket_fd, backlog);
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

SOCKET seed_win_accept(SOCKET socket_fd, int *error_code) {
	SOCKET accepted = accept(socket_fd, NULL, NULL);
	if (error_code) *error_code = accepted == INVALID_SOCKET ? WSAGetLastError() : 0;
	return accepted;
}

int seed_win_set_deadline(SOCKET socket_fd, int read_timeout_ms, int write_timeout_ms, int *error_code) {
	DWORD read_timeout = (DWORD)read_timeout_ms;
	DWORD write_timeout = (DWORD)write_timeout_ms;
	int rc;
	if (read_timeout_ms < 0 || write_timeout_ms < 0) {
		if (error_code) *error_code = WSAEINVAL;
		return SOCKET_ERROR;
	}
	rc = setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&read_timeout, sizeof(read_timeout));
	if (rc == 0) rc = setsockopt(socket_fd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&write_timeout, sizeof(write_timeout));
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

int seed_win_poll(SOCKET socket_fd, short events, int timeout_ms, int *error_code) {
	WSAPOLLFD poll_fd;
	int rc;
	poll_fd.fd = socket_fd;
	poll_fd.events = events;
	poll_fd.revents = 0;
	rc = WSAPoll(&poll_fd, 1, timeout_ms);
	if (error_code) *error_code = rc == SOCKET_ERROR ? WSAGetLastError() : 0;
	return rc;
}

intptr_t seed_win_iocp_create(int *error_code) {
	HANDLE port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);
	if (error_code) *error_code = port ? 0 : (int)GetLastError();
	return (intptr_t)port;
}

int seed_win_iocp_register(intptr_t port, SOCKET socket_fd, uintptr_t key, int *error_code) {
	HANDLE result = CreateIoCompletionPort((HANDLE)socket_fd, (HANDLE)port, (ULONG_PTR)key, 0);
	if (error_code) *error_code = result ? 0 : (int)GetLastError();
	return result ? 0 : SOCKET_ERROR;
}

int seed_win_iocp_wait(intptr_t port, int timeout_ms, uintptr_t *key, unsigned long *bytes, int *error_code) {
	OVERLAPPED *overlapped = NULL;
	ULONG_PTR completion_key = 0;
	DWORD transferred = 0;
	BOOL ok = GetQueuedCompletionStatus((HANDLE)port, &transferred, &completion_key, &overlapped,
	                                     timeout_ms < 0 ? INFINITE : (DWORD)timeout_ms);
	if (key) *key = (uintptr_t)completion_key;
	if (bytes) *bytes = (unsigned long)transferred;
	if (error_code) *error_code = ok ? 0 : (int)GetLastError();
	return ok ? 1 : 0;
}

#else

int seed_windows_network_backend_unavailable(void) { return 1; }

#endif
