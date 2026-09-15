#include "flucord_rpc.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

#include <windows.h>

namespace {

constexpr FlucordRpcStatus kInvalidStatusPipe = FLUCORD_RPC_ERROR_PIPE;

std::wstring Utf8ToWide(const char* text) {
  const auto length =
      MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
  std::wstring wide(static_cast<size_t>(length > 0 ? length - 1 : 0), L'\0');
  if (length > 1) {
    MultiByteToWideChar(CP_UTF8, 0, text, -1, wide.data(),
                        static_cast<int>(wide.size()));
  }
  return wide;
}

}  // namespace

struct FlucordRpcPipe {
  HANDLE handle = INVALID_HANDLE_VALUE;
  std::thread reader;
  std::atomic<bool> running{false};
  FlucordRpcCallback read_callback = nullptr;
  void (*connected_callback)(void*) = nullptr;
  void* user_data = nullptr;
};

extern "C" {

FLUCORD_RPC_EXPORT int32_t flucord_rpc_exists(const char* path) {
  const std::wstring wide = Utf8ToWide(path);
  if (!WaitNamedPipeW(wide.c_str(), 0)) {
    // ERROR_SEM_TIMEOUT means the pipe exists but is busy, which is still
    // "exists". Any other failure says there is nothing at that name.
    return GetLastError() == ERROR_SEM_TIMEOUT ? 1 : 0;
  }
  return 1;
}

FLUCORD_RPC_EXPORT FlucordRpcStatus
flucord_rpc_create(const char* path,
                   void (*connected)(void* user_data),
                   FlucordRpcCallback read,
                   void* user_data,
                   FlucordRpcPipe** out_pipe) {
  if (path == nullptr || out_pipe == nullptr) {
    return FLUCORD_RPC_ERROR_STATE;
  }
  *out_pipe = nullptr;

  SECURITY_ATTRIBUTES inherit_none{sizeof(SECURITY_ATTRIBUTES), nullptr,
                                   FALSE};
  // PIPE_TYPE_BYTE keeps Dart's framing unchanged: bytes in, bytes out, in
  // the order the game and the client wrote them. PIPE_WAIT is the mode a
  // blocking reader needs. Only one instance: a second game binding the same
  // path is refused here instead of being served by two servers.
  HANDLE handle = CreateNamedPipeW(
      Utf8ToWide(path).c_str(),
      PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
      // Discord's frames are a few kilobytes at most; the buffers hold one
      // frame comfortably without pinning memory the session never uses.
      64 * 1024, 64 * 1024, 0, &inherit_none);
  if (handle == INVALID_HANDLE_VALUE) {
    return kInvalidStatusPipe;
  }

  auto* pipe = new FlucordRpcPipe();
  pipe->handle = handle;
  pipe->connected_callback = connected;
  pipe->read_callback = read;
  pipe->user_data = user_data;
  *out_pipe = pipe;
  return FLUCORD_RPC_OK;
}

FLUCORD_RPC_EXPORT FlucordRpcStatus
flucord_rpc_start_read(FlucordRpcPipe* pipe) {
  if (pipe == nullptr || pipe->handle == INVALID_HANDLE_VALUE) {
    return FLUCORD_RPC_ERROR_STATE;
  }
  if (pipe->reader.joinable()) return FLUCORD_RPC_OK;

  // The wait for a client runs on a thread of its own: ConnectNamedPipe
  // blocks until somebody opens the pipe, and the isolate must not.
  pipe->reader = std::thread([pipe]() {
    if (ConnectNamedPipe(pipe->handle, nullptr) == FALSE) {
      const DWORD error = GetLastError();
      // ERROR_PIPE_CONNECTED: a game connected between the create and this
      // call, which is a connection like any other.
      if (error != ERROR_PIPE_CONNECTED) {
        return;
      }
    }
    if (pipe->connected_callback != nullptr) {
      pipe->connected_callback(pipe->user_data);
    }
    std::vector<uint8_t> buffer(64 * 1024);
    DWORD read = 0;
    while (pipe->running.load()) {
      if (ReadFile(pipe->handle, buffer.data(),
                   static_cast<DWORD>(buffer.size()), &read, nullptr) ==
          FALSE) {
        break;
      }
      if (read == 0) break;
      if (pipe->read_callback != nullptr) {
        pipe->read_callback(pipe->user_data, buffer.data(),
                            static_cast<int32_t>(read));
      }
    }
  });
  return FLUCORD_RPC_OK;
}

FLUCORD_RPC_EXPORT FlucordRpcStatus flucord_rpc_write(FlucordRpcPipe* pipe,
                                                      const uint8_t* bytes,
                                                      int32_t length) {
  if (pipe == nullptr || pipe->handle == INVALID_HANDLE_VALUE) {
    return FLUCORD_RPC_ERROR_STATE;
  }
  if (bytes == nullptr || length < 0) return FLUCORD_RPC_ERROR_STATE;
  if (length == 0) return FLUCORD_RPC_OK;
  DWORD written = 0;
  if (WriteFile(pipe->handle, bytes, static_cast<DWORD>(length), &written,
                nullptr) == FALSE ||
      written != static_cast<DWORD>(length)) {
    return kInvalidStatusPipe;
  }
  return FLUCORD_RPC_OK;
}

FLUCORD_RPC_EXPORT void flucord_rpc_close(FlucordRpcPipe* pipe) {
  if (pipe == nullptr) return;
  pipe->running.store(false);
  if (pipe->handle != INVALID_HANDLE_VALUE) {
    // Disconnecting the pipe client unblocks a reader waiting on ReadFile;
    // CancelIoEx targets this handle's pending reads alone.
    CancelIoEx(pipe->handle, nullptr);
    DisconnectNamedPipe(pipe->handle);
    CloseHandle(pipe->handle);
    pipe->handle = INVALID_HANDLE_VALUE;
  }
  if (pipe->reader.joinable()) pipe->reader.join();
  delete pipe;
}

}  // extern "C"
