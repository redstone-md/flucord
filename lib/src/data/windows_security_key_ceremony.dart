import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../domain/multi_factor_auth.dart';

/// The Windows platform authenticator (Windows Hello), over `webauthn.dll`.
///
/// Straight FFI rather than a package: one struct-in, struct-out call plus a
/// free, all in the API Windows ships since 1903. The key Windows makes never
/// leaves the machine's trusted module; what crosses back is the public proof
/// Discord's route asks for.
///
/// The prompt is modal on the thread that opens it, so the ceremony runs on a
/// worker isolate: the settings window keeps drawing while Windows asks the
/// person to prove who they are.
final class WindowsSecurityKeyCeremony implements SecurityKeyCeremony {
  WindowsSecurityKeyCeremony({this.rpId = 'discord.com'})
    : _library = Platform.isWindows ? _open() : null;

  /// The library handed in rather than opened.
  ///
  /// Null means the module is genuinely absent, which is the case a test has
  /// to be able to state: on Windows the ordinary constructor would open it.
  WindowsSecurityKeyCeremony.withLibrary(
    DynamicLibrary? library, {
    this.rpId = 'discord.com',
  }) : _library = library;

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('webauthn.dll');
    } on Object {
      return null;
    }
  }

  /// The relying party Discord's keys belong to. Windows binds each key to
  /// this, so a key made here proves itself for Discord and nothing else.
  final String rpId;

  final DynamicLibrary? _library;

  @override
  bool get isAvailable {
    final library = _library;
    if (library == null) return false;
    final probe = library
        .lookupFunction<
          Int32 Function(Pointer<Int32>),
          int Function(Pointer<Int32>)
        >('WebAuthNIsUserVerifyingPlatformAuthenticatorAvailable');
    final available = calloc<Int32>();
    try {
      return probe(available) >= 0 && available.value != 0;
    } finally {
      calloc.free(available);
    }
  }

  @override
  Future<SecurityKeyRegistration?> createCredential({
    required String challenge,
    required SecurityKeyAccount account,
  }) async {
    if (_library == null) return null;
    // Plain values only across the isolate boundary, per the project's
    // message rules; the module is opened again on the far side.
    return Isolate.run(() => _makeCredential(challenge, account, rpId));
  }

  static SecurityKeyRegistration? _makeCredential(
    String challenge,
    SecurityKeyAccount account,
    String rpId,
  ) {
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open('webauthn.dll');
    } on Object {
      return null;
    }
    final makeCredential = library
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<_RpEntity>,
            Pointer<_UserEntity>,
            Pointer<_CoseCredentialParameters>,
            Pointer<_ClientData>,
            Pointer<_MakeCredentialOptions>,
            Pointer<Pointer<_Attestation>>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<_RpEntity>,
            Pointer<_UserEntity>,
            Pointer<_CoseCredentialParameters>,
            Pointer<_ClientData>,
            Pointer<_MakeCredentialOptions>,
            Pointer<Pointer<_Attestation>>,
          )
        >('WebAuthNAuthenticatorMakeCredential');
    final freeAttestation = library
        .lookupFunction<
          Void Function(Pointer<_Attestation>),
          void Function(Pointer<_Attestation>)
        >('WebAuthNFreeCredentialAttestation');

    final clientDataJsonModel = SecurityKeyClientData.create(
      challenge: challenge,
    );
    final clientDataBytes = utf8.encode(clientDataJsonModel.json);
    final userId = utf8.encode(account.userId);
    final rpIdPointer = rpId.toNativeUtf16();
    final rpNamePointer = 'Discord'.toNativeUtf16();
    final userNamePointer = account.displayName.toNativeUtf16();
    final hashAlgorithm = 'SHA-256'.toNativeUtf16();
    final credentialType = 'public-key'.toNativeUtf16();
    final clientDataJson = calloc<Uint8>(clientDataBytes.length);
    final userIdBytes = calloc<Uint8>(userId.length);
    clientDataJson
        .asTypedList(clientDataBytes.length)
        .setAll(0, clientDataBytes);
    userIdBytes.asTypedList(userId.length).setAll(0, userId);

    final coseParameters = calloc<_CoseCredentialParameters>();
    final coseParameterArray = calloc<_CoseCredentialParameter>(2);
    final rp = calloc<_RpEntity>();
    final user = calloc<_UserEntity>();
    final clientData = calloc<_ClientData>();
    final options = calloc<_MakeCredentialOptions>();
    final attestation = calloc<Pointer<_Attestation>>();
    try {
      coseParameterArray[0]
        ..version = 1
        ..credentialType = credentialType
        ..algorithm = -7; // ECDSA P-256 with SHA-256.
      coseParameterArray[1]
        ..version = 1
        ..credentialType = credentialType
        ..algorithm = -257; // RSASSA PKCS#1 v1.5 with SHA-256.
      coseParameters.ref
        ..count = 2
        ..parameters = coseParameterArray;
      rp.ref
        ..version = 1
        ..id = rpIdPointer
        ..name = rpNamePointer;
      user.ref
        ..version = 1
        ..idLength = userId.length
        ..idBytes = userIdBytes
        ..name = userNamePointer
        ..displayName = userNamePointer;
      clientData.ref
        ..version = 1
        ..jsonLength = clientDataBytes.length
        ..jsonBytes = clientDataJson
        ..hashAlgorithm = hashAlgorithm;
      options.ref
        ..version = 1
        ..timeoutMilliseconds = 120000
        // The platform authenticator is the point: a key bound to this
        // machine, proven with the person's face, fingerprint or PIN.
        ..authenticatorAttachment = 1
        // A second factor needs no discoverable credential, and asking for
        // one is what makes some authenticators refuse.
        ..requireResidentKey = 0
        // The whole strength of a security key is that the person had to
        // prove themselves to this machine.
        ..userVerificationRequirement = 1
        // Discord asks for the proof to work, not for the maker's word.
        ..attestationConveyancePreference = 1;

      final result = makeCredential(
        _parentWindow(),
        rp,
        user,
        coseParameters,
        clientData,
        options,
        attestation,
      );
      if (result != 0 || attestation.value == nullptr) return null;
      final made = attestation.value.ref;
      return SecurityKeyRegistration(
        credentialId: encodeBase64Url(
          made.credentialIdBytes
              .asTypedList(made.credentialIdLength)
              .toList(growable: false),
        ),
        attestationObject: encodeBase64Url(
          made.attestationObjectBytes
              .asTypedList(made.attestationObjectLength)
              .toList(growable: false),
        ),
        clientDataJson: clientDataJsonModel.base64Url,
      );
    } finally {
      if (attestation.value != nullptr) {
        freeAttestation(attestation.value);
      }
      calloc.free(coseParameters);
      calloc.free(coseParameterArray);
      calloc.free(rp);
      calloc.free(user);
      calloc.free(clientData);
      calloc.free(options);
      calloc.free(attestation);
      calloc.free(clientDataJson);
      calloc.free(userIdBytes);
      calloc.free(rpIdPointer);
      calloc.free(rpNamePointer);
      calloc.free(hashAlgorithm);
      calloc.free(credentialType);
    }
  }

  static Pointer<Void> _parentWindow() {
    DynamicLibrary? user32;
    try {
      user32 = DynamicLibrary.open('user32.dll');
    } on Object {
      user32 = null;
    }
    if (user32 == null) return nullptr;
    final findWindow = user32
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>),
          Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf16>)
        >('FindWindowW');
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    try {
      return findWindow(className, nullptr);
    } finally {
      calloc.free(className);
    }
  }
}

final class _RpEntity extends Struct {
  @Uint32()
  external int version;
  external Pointer<Utf16> id;
  external Pointer<Utf16> name;
}

final class _UserEntity extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int idLength;
  external Pointer<Uint8> idBytes;
  external Pointer<Utf16> name;
  external Pointer<Utf16> displayName;
}

final class _ClientData extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int jsonLength;
  external Pointer<Uint8> jsonBytes;
  external Pointer<Utf16> hashAlgorithm;
}

final class _CoseCredentialParameter extends Struct {
  @Uint32()
  external int version;
  external Pointer<Utf16> credentialType;
  @Int32()
  external int algorithm;
}

final class _CoseCredentialParameters extends Struct {
  @Uint32()
  external int count;
  external Pointer<_CoseCredentialParameter> parameters;
}

/// The make-credential options, laid out exactly as Windows writes them.
///
/// The nested credential and extension lists are flattened into their fields,
/// which is what the by-value embedding in the C struct comes to. Only the
/// fields a version-1 options struct carries are set; every Windows WebAuthn
/// API version understands version 1.
final class _MakeCredentialOptions extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int timeoutMilliseconds;
  // WEBAUTHN_CREDENTIALS: a count and a pointer.
  @Uint32()
  external int credentialCount;
  external Pointer<Uint8> credentials;
  // WEBAUTHN_EXTENSIONS: a count and a pointer.
  @Uint32()
  external int extensionCount;
  external Pointer<Uint8> extensions;
  @Uint32()
  external int authenticatorAttachment;
  @Int32()
  external int requireResidentKey;
  @Uint32()
  external int userVerificationRequirement;
  @Uint32()
  external int attestationConveyancePreference;
  @Uint32()
  external int flags;
  external Pointer<Uint8> cancellationId;
  external Pointer<Uint8> excludeCredentialList;
  @Uint32()
  external int enterpriseAttestation;
  @Uint32()
  external int largeBlobSupport;
  @Int32()
  external int preferResidentKey;
}

/// The attestation Windows hands back. Only the version-1 fields are read;
/// the struct is declared whole so its size matches what the API allocated.
final class _Attestation extends Struct {
  @Uint32()
  external int version;
  external Pointer<Utf16> formatType;
  @Uint32()
  external int authenticatorDataLength;
  external Pointer<Uint8> authenticatorDataBytes;
  @Uint32()
  external int attestationLength;
  external Pointer<Uint8> attestationBytes;
  @Uint32()
  external int attestationDecodeType;
  external Pointer<Uint8> attestationDecode;
  @Uint32()
  external int attestationObjectLength;
  external Pointer<Uint8> attestationObjectBytes;
  @Uint32()
  external int credentialIdLength;
  external Pointer<Uint8> credentialIdBytes;
  @Uint32()
  external int extensionCount;
  external Pointer<Uint8> extensions;
  @Uint32()
  external int usedTransport;
  @Int32()
  external int epAtt;
  @Int32()
  external int largeBlobSupported;
  @Int32()
  external int residentKey;
}
