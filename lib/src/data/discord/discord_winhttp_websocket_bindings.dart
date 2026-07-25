part of 'discord_desktop_websocket.dart';

final class _WinHttpBindings {
  _WinHttpBindings._(DynamicLibrary winHttp, DynamicLibrary kernel32)
    : openSession = winHttp.lookupFunction<_OpenNative, _OpenDart>(
        'WinHttpOpen',
      ),
      connect = winHttp.lookupFunction<_ConnectNative, _ConnectDart>(
        'WinHttpConnect',
      ),
      openRequest = winHttp
          .lookupFunction<_OpenRequestNative, _OpenRequestDart>(
            'WinHttpOpenRequest',
          ),
      setOption = winHttp.lookupFunction<_SetOptionNative, _SetOptionDart>(
        'WinHttpSetOption',
      ),
      addRequestHeaders = winHttp
          .lookupFunction<_AddHeadersNative, _AddHeadersDart>(
            'WinHttpAddRequestHeaders',
          ),
      sendRequest = winHttp
          .lookupFunction<_SendRequestNative, _SendRequestDart>(
            'WinHttpSendRequest',
          ),
      receiveResponse = winHttp
          .lookupFunction<_ReceiveResponseNative, _ReceiveResponseDart>(
            'WinHttpReceiveResponse',
          ),
      queryHeaders = winHttp
          .lookupFunction<_QueryHeadersNative, _QueryHeadersDart>(
            'WinHttpQueryHeaders',
          ),
      completeUpgrade = winHttp
          .lookupFunction<_CompleteUpgradeNative, _CompleteUpgradeDart>(
            'WinHttpWebSocketCompleteUpgrade',
          ),
      webSocketSend = winHttp
          .lookupFunction<_WebSocketSendNative, _WebSocketSendDart>(
            'WinHttpWebSocketSend',
          ),
      webSocketReceive = winHttp
          .lookupFunction<_WebSocketReceiveNative, _WebSocketReceiveDart>(
            'WinHttpWebSocketReceive',
          ),
      webSocketClose = winHttp
          .lookupFunction<_WebSocketCloseNative, _WebSocketCloseDart>(
            'WinHttpWebSocketClose',
          ),
      webSocketQueryCloseStatus = winHttp
          .lookupFunction<
            _WebSocketQueryCloseStatusNative,
            _WebSocketQueryCloseStatusDart
          >('WinHttpWebSocketQueryCloseStatus'),
      closeHandle = winHttp
          .lookupFunction<_CloseHandleNative, _CloseHandleDart>(
            'WinHttpCloseHandle',
          ),
      lastError = kernel32.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'GetLastError',
      );

  static _WinHttpBindings open() => _WinHttpBindings._(
    DynamicLibrary.open('winhttp.dll'),
    DynamicLibrary.open('kernel32.dll'),
  );

  final _OpenDart openSession;
  final _ConnectDart connect;
  final _OpenRequestDart openRequest;
  final _SetOptionDart setOption;
  final _AddHeadersDart addRequestHeaders;
  final _SendRequestDart sendRequest;
  final _ReceiveResponseDart receiveResponse;
  final _QueryHeadersDart queryHeaders;
  final _CompleteUpgradeDart completeUpgrade;
  final _WebSocketSendDart webSocketSend;
  final _WebSocketReceiveDart webSocketReceive;
  final _WebSocketCloseDart webSocketClose;
  final _WebSocketQueryCloseStatusDart webSocketQueryCloseStatus;
  final _CloseHandleDart closeHandle;
  final _LastErrorDart lastError;
}

typedef _OpenNative =
    Pointer<Void> Function(
      Pointer<Utf16>,
      Uint32,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Uint32,
    );
typedef _OpenDart =
    Pointer<Void> Function(
      Pointer<Utf16>,
      int,
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
    );
typedef _ConnectNative =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>, Uint16, Uint32);
typedef _ConnectDart =
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>, int, int);
typedef _OpenRequestNative =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Pointer<Utf16>>,
      Uint32,
    );
typedef _OpenRequestDart =
    Pointer<Void> Function(
      Pointer<Void>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Pointer<Utf16>>,
      int,
    );
typedef _SetOptionNative =
    Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32);
typedef _SetOptionDart = int Function(Pointer<Void>, int, Pointer<Void>, int);
typedef _AddHeadersNative =
    Int32 Function(Pointer<Void>, Pointer<Utf16>, Uint32, Uint32);
typedef _AddHeadersDart = int Function(Pointer<Void>, Pointer<Utf16>, int, int);
typedef _SendRequestNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf16>,
      Uint32,
      Pointer<Void>,
      Uint32,
      Uint32,
      UintPtr,
    );
typedef _SendRequestDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf16>,
      int,
      Pointer<Void>,
      int,
      int,
      int,
    );
typedef _ReceiveResponseNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _ReceiveResponseDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _QueryHeadersNative =
    Int32 Function(
      Pointer<Void>,
      Uint32,
      Pointer<Utf16>,
      Pointer<Void>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _QueryHeadersDart =
    int Function(
      Pointer<Void>,
      int,
      Pointer<Utf16>,
      Pointer<Void>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _CompleteUpgradeNative = Pointer<Void> Function(Pointer<Void>, UintPtr);
typedef _CompleteUpgradeDart = Pointer<Void> Function(Pointer<Void>, int);
typedef _WebSocketSendNative =
    Uint32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32);
typedef _WebSocketSendDart =
    int Function(Pointer<Void>, int, Pointer<Void>, int);
typedef _WebSocketReceiveNative =
    Uint32 Function(
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _WebSocketReceiveDart =
    int Function(
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _WebSocketCloseNative =
    Uint32 Function(Pointer<Void>, Uint16, Pointer<Void>, Uint32);
typedef _WebSocketCloseDart =
    int Function(Pointer<Void>, int, Pointer<Void>, int);
typedef _WebSocketQueryCloseStatusNative =
    Uint32 Function(
      Pointer<Void>,
      Pointer<Uint16>,
      Pointer<Void>,
      Uint32,
      Pointer<Uint32>,
    );
typedef _WebSocketQueryCloseStatusDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint16>,
      Pointer<Void>,
      int,
      Pointer<Uint32>,
    );
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);
typedef _LastErrorNative = Uint32 Function();
typedef _LastErrorDart = int Function();
