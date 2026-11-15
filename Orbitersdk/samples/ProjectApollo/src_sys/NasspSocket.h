// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#if defined(_WIN32)
#include <winsock.h>
#else
#include <arpa/inet.h>
#include <cerrno>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace nassp {
#if defined(_WIN32)
using SocketHandle = SOCKET;
constexpr SocketHandle invalidSocket = INVALID_SOCKET;
constexpr int socketSendFlags = 0;

inline int LastSocketError() { return WSAGetLastError(); }
inline bool RetrySocketError(int error) { return error == WSAEWOULDBLOCK || error == WSAEINTR; }
inline bool SocketDisconnected(int error)
{
	return error == WSAECONNRESET || error == WSAECONNABORTED || error == WSAENOTSOCK ||
		error == WSAENOTCONN || error == WSAESHUTDOWN;
}
#else
using SocketHandle = int;
constexpr SocketHandle invalidSocket = -1;
constexpr int socketSendFlags = MSG_NOSIGNAL;

inline int LastSocketError() { return errno; }
inline bool RetrySocketError(int error) { return error == EAGAIN || error == EWOULDBLOCK || error == EINTR; }
inline bool SocketDisconnected(int error)
{
	return error == ECONNRESET || error == ECONNABORTED || error == ENOTSOCK ||
		error == ENOTCONN || error == EPIPE;
}
#endif

class SocketRuntime {
public:
	SocketRuntime() = default;
	SocketRuntime(const SocketRuntime&) = delete;
	SocketRuntime& operator=(const SocketRuntime&) = delete;
	~SocketRuntime()
	{
#if defined(_WIN32)
		if (started) WSACleanup();
#endif
	}
	int Start()
	{
#if defined(_WIN32)
		if (started) return 0;
		WSADATA data{};
		const auto status = WSAStartup(MAKEWORD(2, 2), &data);
		started = status == 0;
		return status;
#else
		return 0;
#endif
	}

private:
#if defined(_WIN32)
	bool started = false;
#endif
};

class Socket {
public:
	Socket() = default;
	Socket(const Socket&) = delete;
	Socket& operator=(const Socket&) = delete;
	~Socket() { Close(); }

	explicit operator bool() const { return handle != invalidSocket; }
	SocketHandle Get() const { return handle; }
	void Close()
	{
		if (handle == invalidSocket) return;
#if defined(_WIN32)
		closesocket(handle);
#else
		close(handle);
#endif
		handle = invalidSocket;
	}

	int Open(int type, int protocol)
	{
		Close();
#if defined(_WIN32)
		handle = socket(AF_INET, type, protocol);
		return Configure();
#else
		handle = socket(AF_INET, type | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol);
		return *this ? 0 : LastSocketError();
#endif
	}

	int Accept(const Socket& listener)
	{
		Close();
#if defined(_WIN32)
		handle = accept(listener.Get(), nullptr, nullptr);
		return Configure();
#else
		handle = accept4(listener.Get(), nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
		return *this ? 0 : LastSocketError();
#endif
	}

private:
	SocketHandle handle = invalidSocket;

#if defined(_WIN32)
	int Configure()
	{
		if (!*this) return LastSocketError();
		u_long nonBlocking = 1;
		if (ioctlsocket(handle, FIONBIO, &nonBlocking) == 0) return 0;
		const int error = LastSocketError();
		Close();
		return error;
	}
#endif
};
}
