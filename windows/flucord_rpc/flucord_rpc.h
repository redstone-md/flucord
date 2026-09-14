// The server end of the \\?\pipe\discord-ipc-{n} named pipe, so a game can
// reach the Rich Presence server on Windows.
//
// Dart cannot open a named pipe with Socket.connect or ServerSocket.bind, and
// the pipe API lives in kernel32. This module owns the handle: it creates the
// pipe server, accepts one connection at a time, and moves bytes both ways
// through a plain pair of buffers, so Dart sees an ordinary push/pull pair
// and never touches a HANDLE.
//
// One server instance serves one pipe instance, which is one connected game:
// that is the shape Discord's own client keeps, and a second simultaneous
// connect is refused by the pipe's own single-instance mode.

#ifndef FLUCORD_RPC_H_
#define FLUCORD_RPC_H_

#include <stdint.h>

#if defined(_WIN32)
#define FLUCORD_RPC_EXPORT __declspec(dllexport)
#else
#define FLUCORD_RPC_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  FLUCORD_RPC_OK = 0,
  FLUCORD_RPC_ERROR_STATE = 1,
  FLUCORD_RPC_ERROR_PIPE = 2,
} FlucordRpcStatus;

typedef struct FlucordRpcPipe FlucordRpcPipe;

typedef void (*FlucordRpcCallback)(void* user_data,
                                   const uint8_t* bytes,
                                   int32_t length);

// Creates the named pipe server for path. The path is UTF-8 and carries the
// full \\.\pipe\... name. One game connects at a time: the pipe is created
// with FILE_FLAG_FIRST_PIPE_INSTANCE and a single instance. `connected` runs
// when a game opens the pipe; `read` runs for every chunk the game sends
// after that.
FLUCORD_RPC_EXPORT FlucordRpcStatus
flucord_rpc_create(const char* path,
                   void (*connected)(void* user_data),
                   FlucordRpcCallback read,
                   void* user_data,
                   FlucordRpcPipe** out_pipe);

// Starts reading the pipe. Bytes a game sends arrive through the read
// callback handed to flucord_rpc_create, one call per chunk as the OS
// delivered them.
FLUCORD_RPC_EXPORT FlucordRpcStatus flucord_rpc_start_read(FlucordRpcPipe* pipe);

// Writes one buffer to the connected game. The whole buffer is written
// before the call returns.
FLUCORD_RPC_EXPORT FlucordRpcStatus flucord_rpc_write(FlucordRpcPipe* pipe,
                                                      const uint8_t* bytes,
                                                      int32_t length);

// Closes the pipe. A connected game sees the pipe go away; a reading thread
// is joined before the call returns.
FLUCORD_RPC_EXPORT void flucord_rpc_close(FlucordRpcPipe* pipe);

// The number of pipes this process has already created for path, so a second
// bind of the same path fails here rather than at the OS.
FLUCORD_RPC_EXPORT int32_t flucord_rpc_exists(const char* path);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUCORD_RPC_H_
