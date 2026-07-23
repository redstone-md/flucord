import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef DaveSessionHandle = Pointer<Void>;
typedef DaveResultHandle = Pointer<Void>;

typedef DaveMlsFailureNative =
    Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>);

void _ignoreMlsFailure(
  Pointer<Utf8> source,
  Pointer<Utf8> reason,
  Pointer<Void> userData,
) {}

final class NativeDaveBindings {
  NativeDaveBindings(DynamicLibrary library)
    : maxSupportedProtocolVersion = library
          .lookupFunction<Uint16 Function(), int Function()>(
            'daveMaxSupportedProtocolVersion',
          ),
      free = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveFree'),
      sessionCreate = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<NativeFunction<DaveMlsFailureNative>>,
              Pointer<Void>,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<NativeFunction<DaveMlsFailureNative>>,
              Pointer<Void>,
            )
          >('daveSessionCreate'),
      sessionDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveSessionDestroy'),
      sessionInit = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint16, Uint64, Pointer<Utf8>),
            void Function(Pointer<Void>, int, int, Pointer<Utf8>)
          >('daveSessionInit'),
      sessionReset = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveSessionReset'),
      sessionSetProtocolVersion = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint16),
            void Function(Pointer<Void>, int)
          >('daveSessionSetProtocolVersion'),
      sessionGetProtocolVersion = library
          .lookupFunction<
            Uint16 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('daveSessionGetProtocolVersion'),
      sessionSetExternalSender = library
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Uint8>, Size),
            void Function(Pointer<Void>, Pointer<Uint8>, int)
          >('daveSessionSetExternalSender'),
      sessionProcessProposals = library
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Pointer<Utf8>>,
              Size,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            void Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Pointer<Utf8>>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('daveSessionProcessProposals'),
      sessionProcessCommit = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size),
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
          >('daveSessionProcessCommit'),
      sessionProcessWelcome = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Pointer<Utf8>>,
              Size,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Pointer<Utf8>>,
              int,
            )
          >('daveSessionProcessWelcome'),
      sessionGetKeyPackage = library
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            void Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
          >('daveSessionGetMarshalledKeyPackage'),
      commitResultIsFailed = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('daveCommitResultIsFailed'),
      commitResultIsIgnored = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('daveCommitResultIsIgnored'),
      commitResultGetRoster = library
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Pointer<Pointer<Uint64>>,
              Pointer<Size>,
            ),
            void Function(
              Pointer<Void>,
              Pointer<Pointer<Uint64>>,
              Pointer<Size>,
            )
          >('daveCommitResultGetRosterMemberIds'),
      commitResultDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveCommitResultDestroy'),
      welcomeResultGetRoster = library
          .lookupFunction<
            Void Function(
              Pointer<Void>,
              Pointer<Pointer<Uint64>>,
              Pointer<Size>,
            ),
            void Function(
              Pointer<Void>,
              Pointer<Pointer<Uint64>>,
              Pointer<Size>,
            )
          >('daveWelcomeResultGetRosterMemberIds'),
      welcomeResultDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveWelcomeResultDestroy');

  final int Function() maxSupportedProtocolVersion;
  final void Function(Pointer<Void>) free;
  final DaveSessionHandle Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<NativeFunction<DaveMlsFailureNative>>,
    Pointer<Void>,
  )
  sessionCreate;
  final void Function(DaveSessionHandle) sessionDestroy;
  final void Function(DaveSessionHandle, int, int, Pointer<Utf8>) sessionInit;
  final void Function(DaveSessionHandle) sessionReset;
  final void Function(DaveSessionHandle, int) sessionSetProtocolVersion;
  final int Function(DaveSessionHandle) sessionGetProtocolVersion;
  final void Function(DaveSessionHandle, Pointer<Uint8>, int)
  sessionSetExternalSender;
  final void Function(
    DaveSessionHandle,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Utf8>>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  sessionProcessProposals;
  final DaveResultHandle Function(DaveSessionHandle, Pointer<Uint8>, int)
  sessionProcessCommit;
  final DaveResultHandle Function(
    DaveSessionHandle,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Utf8>>,
    int,
  )
  sessionProcessWelcome;
  final void Function(DaveSessionHandle, Pointer<Pointer<Uint8>>, Pointer<Size>)
  sessionGetKeyPackage;
  final bool Function(DaveResultHandle) commitResultIsFailed;
  final bool Function(DaveResultHandle) commitResultIsIgnored;
  final void Function(DaveResultHandle, Pointer<Pointer<Uint64>>, Pointer<Size>)
  commitResultGetRoster;
  final void Function(DaveResultHandle) commitResultDestroy;
  final void Function(DaveResultHandle, Pointer<Pointer<Uint64>>, Pointer<Size>)
  welcomeResultGetRoster;
  final void Function(DaveResultHandle) welcomeResultDestroy;

  static final Pointer<NativeFunction<DaveMlsFailureNative>> failureCallback =
      Pointer.fromFunction<DaveMlsFailureNative>(_ignoreMlsFailure);
}
