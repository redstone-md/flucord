import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef DaveSessionHandle = Pointer<Void>;
typedef DaveResultHandle = Pointer<Void>;
typedef DaveKeyRatchetHandle = Pointer<Void>;
typedef DaveEncryptorHandle = Pointer<Void>;
typedef DaveDecryptorHandle = Pointer<Void>;

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
      sessionGetKeyRatchet = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
          >('daveSessionGetKeyRatchet'),
      keyRatchetDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveKeyRatchetDestroy'),
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
          >('daveWelcomeResultDestroy'),
      encryptorCreate = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'daveEncryptorCreate',
          ),
      encryptorDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveEncryptorDestroy'),
      encryptorSetKeyRatchet = library
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Void>),
            void Function(Pointer<Void>, Pointer<Void>)
          >('daveEncryptorSetKeyRatchet'),
      encryptorSetPassthrough = library
          .lookupFunction<
            Void Function(Pointer<Void>, Bool),
            void Function(Pointer<Void>, bool)
          >('daveEncryptorSetPassthroughMode'),
      encryptorAssignSsrcToCodec = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32, Int32),
            void Function(Pointer<Void>, int, int)
          >('daveEncryptorAssignSsrcToCodec'),
      encryptorGetProtocolVersion = library
          .lookupFunction<
            Uint16 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('daveEncryptorGetProtocolVersion'),
      encryptorGetMaxCiphertextSize = library
          .lookupFunction<
            Size Function(Pointer<Void>, Int32, Size),
            int Function(Pointer<Void>, int, int)
          >('daveEncryptorGetMaxCiphertextByteSize'),
      encryptorHasKeyRatchet = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('daveEncryptorHasKeyRatchet'),
      encryptorIsPassthrough = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('daveEncryptorIsPassthroughMode'),
      encryptorEncrypt = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Uint32,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Size>,
            ),
            int Function(
              Pointer<Void>,
              int,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Size>,
            )
          >('daveEncryptorEncrypt'),
      decryptorCreate = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'daveDecryptorCreate',
          ),
      decryptorDestroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('daveDecryptorDestroy'),
      decryptorTransitionToKeyRatchet = library
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Void>),
            void Function(Pointer<Void>, Pointer<Void>)
          >('daveDecryptorTransitionToKeyRatchet'),
      decryptorTransitionToPassthrough = library
          .lookupFunction<
            Void Function(Pointer<Void>, Bool),
            void Function(Pointer<Void>, bool)
          >('daveDecryptorTransitionToPassthroughMode'),
      decryptorDecrypt = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Size>,
            ),
            int Function(
              Pointer<Void>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Size>,
            )
          >('daveDecryptorDecrypt'),
      decryptorGetMaxPlaintextSize = library
          .lookupFunction<
            Size Function(Pointer<Void>, Int32, Size),
            int Function(Pointer<Void>, int, int)
          >('daveDecryptorGetMaxPlaintextByteSize');

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
  final DaveKeyRatchetHandle Function(DaveSessionHandle, Pointer<Utf8>)
  sessionGetKeyRatchet;
  final void Function(DaveKeyRatchetHandle) keyRatchetDestroy;
  final bool Function(DaveResultHandle) commitResultIsFailed;
  final bool Function(DaveResultHandle) commitResultIsIgnored;
  final void Function(DaveResultHandle, Pointer<Pointer<Uint64>>, Pointer<Size>)
  commitResultGetRoster;
  final void Function(DaveResultHandle) commitResultDestroy;
  final void Function(DaveResultHandle, Pointer<Pointer<Uint64>>, Pointer<Size>)
  welcomeResultGetRoster;
  final void Function(DaveResultHandle) welcomeResultDestroy;
  final DaveEncryptorHandle Function() encryptorCreate;
  final void Function(DaveEncryptorHandle) encryptorDestroy;
  final void Function(DaveEncryptorHandle, DaveKeyRatchetHandle)
  encryptorSetKeyRatchet;
  final void Function(DaveEncryptorHandle, bool) encryptorSetPassthrough;
  final void Function(DaveEncryptorHandle, int, int) encryptorAssignSsrcToCodec;
  final int Function(DaveEncryptorHandle) encryptorGetProtocolVersion;
  final int Function(DaveEncryptorHandle, int, int)
  encryptorGetMaxCiphertextSize;
  final bool Function(DaveEncryptorHandle) encryptorHasKeyRatchet;
  final bool Function(DaveEncryptorHandle) encryptorIsPassthrough;
  final int Function(
    DaveEncryptorHandle,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Size>,
  )
  encryptorEncrypt;
  final DaveDecryptorHandle Function() decryptorCreate;
  final void Function(DaveDecryptorHandle) decryptorDestroy;
  final void Function(DaveDecryptorHandle, DaveKeyRatchetHandle)
  decryptorTransitionToKeyRatchet;
  final void Function(DaveDecryptorHandle, bool)
  decryptorTransitionToPassthrough;
  final int Function(
    DaveDecryptorHandle,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Size>,
  )
  decryptorDecrypt;
  final int Function(DaveDecryptorHandle, int, int)
  decryptorGetMaxPlaintextSize;

  static final Pointer<NativeFunction<DaveMlsFailureNative>> failureCallback =
      Pointer.fromFunction<DaveMlsFailureNative>(_ignoreMlsFailure);
}
