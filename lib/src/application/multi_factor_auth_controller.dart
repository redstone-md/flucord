import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/multi_factor_auth.dart';

/// Where the enrolment has got to.
enum MfaEnrolmentStage {
  /// Nothing started, or finished and cleared away.
  idle,

  /// A secret exists and is on screen, waiting for a code from the app it was
  /// added to.
  awaitingCode,

  /// Discord accepted it and handed back the backup codes.
  enrolled,
}

/// Where a security-key enrolment has got to.
enum MfaSecurityKeyStage {
  /// No enrolment running.
  idle,

  /// Windows is asking the person to prove it is them. The prompt belongs to
  /// the machine, so there is nothing to type here while it is up.
  prompting,

  /// The key was made and registered.
  added,
}

/// Why a security-key enrolment or removal did not happen.
enum MfaSecurityKeyRefusal {
  /// The password was not accepted at the challenge.
  passwordRefused,

  /// The machine's prompt was closed before a key was made. The person
  /// changed their mind, which is not an error.
  keyDeclined,

  /// The proof was made but Discord would not take it.
  registrationRefused,

  /// A removal was refused: the password, or the key was already gone.
  removalRefused,
}

final class MultiFactorAuthController extends ChangeNotifier {
  MultiFactorAuthController(
    this._repositoryProvider, {
    Random? random,
    SecurityKeyCeremony? securityKeyCeremony,
    SecurityKeyAccount? Function()? securityKeyAccount,
  }) : _random = random,
       _securityKeyCeremony = securityKeyCeremony,
       _securityKeyAccount = securityKeyAccount;

  final MultiFactorAuthRepository? Function() _repositoryProvider;
  final Random? _random;

  /// The machine's own authenticator. The ceremony is machine-local rather
  /// than session-bound, so it is held rather than resolved per call.
  final SecurityKeyCeremony? _securityKeyCeremony;

  /// Reads the signed-in account, so the key's user handle belongs to
  /// whichever account is actually signed in.
  final SecurityKeyAccount? Function()? _securityKeyAccount;

  TotpSecret? _secret;
  MfaEnrolment? _enrolment;
  MfaEnrolmentStage _stage = MfaEnrolmentStage.idle;
  Object? _error;
  bool _busy = false;
  bool _codeRefused = false;
  bool _disposed = false;

  List<SecurityKey> _securityKeys = const [];
  bool _securityKeysLoaded = false;
  bool _securityKeysLoading = false;
  MfaSecurityKeyStage _securityKeyStage = MfaSecurityKeyStage.idle;
  MfaSecurityKeyRefusal? _securityKeyRefusal;
  SecurityKey? _addedSecurityKey;

  bool get isAvailable => _repositoryProvider() != null;
  MfaEnrolmentStage get stage => _stage;
  TotpSecret? get secret => _secret;
  bool get isBusy => _busy;
  Object? get error => _error;

  /// The keys registered on this account.
  List<SecurityKey> get securityKeys => List.unmodifiable(_securityKeys);

  bool get areSecurityKeysLoading => _securityKeysLoading;
  MfaSecurityKeyStage get securityKeyStage => _securityKeyStage;

  /// The last refusal and which one it was, so the page can say so rather
  /// than read it as an outage.
  MfaSecurityKeyRefusal? get securityKeyRefusal => _securityKeyRefusal;

  /// The key the last enrolment added, named on the page until it is
  /// dismissed.
  SecurityKey? get addedSecurityKey => _addedSecurityKey;

  /// Whether this machine can make a key at all. Stated rather than left to
  /// a button that could only ever fail.
  bool get isSecurityKeyCeremonyAvailable =>
      _securityKeyCeremony?.isAvailable ?? false;

  /// The last code was not one Discord accepted. Ordinary: six digits against
  /// a thirty-second window get mistyped.
  bool get wasCodeRefused => _codeRefused;

  /// The codes to write down, once enrolment succeeded.
  List<String> get backupCodes => _enrolment?.backupCodes ?? const [];

  /// Mints a secret to show. Does nothing if one is already on screen, so a
  /// second tap cannot swap the secret out from under the app it was added to.
  void beginEnrolment() {
    if (_stage != MfaEnrolmentStage.idle) return;
    if (_repositoryProvider() == null) return;
    _secret = TotpSecret.generate(random: _random);
    _stage = MfaEnrolmentStage.awaitingCode;
    _codeRefused = false;
    _error = null;
    _notify();
  }

  /// Sends the first working code, which is what proves the secret was stored.
  Future<bool> confirmEnrolment(String code) async {
    final secret = _secret;
    final repository = _repositoryProvider();
    if (secret == null || repository == null || _busy) return false;
    _busy = true;
    _codeRefused = false;
    _error = null;
    _notify();
    try {
      final enrolment = await repository.enableTotp(secret: secret, code: code);
      if (enrolment == null) {
        _codeRefused = true;
        return false;
      }
      _enrolment = enrolment;
      _stage = MfaEnrolmentStage.enrolled;
      // The secret has done its job. Keeping it would be keeping a credential
      // for no reason: from here on the authenticator holds it.
      _secret = null;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> disable(String code) async {
    final repository = _repositoryProvider();
    if (repository == null || _busy) return false;
    _busy = true;
    _codeRefused = false;
    _error = null;
    _notify();
    try {
      final accepted = await repository.disableTotp(code);
      _codeRefused = !accepted;
      if (accepted) reset();
      return accepted;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Switches text-message codes on. Discord uses the phone already on the
  /// account, so there is nothing to type here.
  Future<bool> enableSms() => _run(() => _repositoryProvider()!.enableSms());

  /// Switches them off, which Discord gates on the account password.
  ///
  /// The password is passed straight through to the one request that needs it
  /// and is never held: this controller has no field to keep it in.
  Future<bool> disableSms(String password) =>
      _run(() => _repositoryProvider()!.disableSms(password));

  /// Reads the backup codes again, or mints a new set.
  ///
  /// Two steps, because Discord makes them two: the password buys a pair of
  /// one-shot nonces, and a current authenticator code spends one of them.
  Future<bool> revealBackupCodes({
    required String password,
    required String code,
    bool regenerate = false,
  }) async {
    final repository = _repositoryProvider();
    if (repository == null || _busy) return false;
    _busy = true;
    _codeRefused = false;
    _error = null;
    _notify();
    try {
      final nonces = await repository.requestBackupCodeChallenge(password);
      if (nonces == null) {
        _codeRefused = true;
        return false;
      }
      final codes = await repository.viewBackupCodes(
        key: code,
        nonces: nonces,
        regenerate: regenerate,
      );
      if (codes == null) {
        _codeRefused = true;
        return false;
      }
      _enrolment = MfaEnrolment(backupCodes: codes);
      _stage = MfaEnrolmentStage.enrolled;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> _run(Future<bool> Function() action) async {
    if (_repositoryProvider() == null || _busy) return false;
    _busy = true;
    _codeRefused = false;
    _error = null;
    _notify();
    try {
      final accepted = await action();
      _codeRefused = !accepted;
      return accepted;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Drops the secret and the backup codes. Called when the page closes, and
  /// after switching two-factor off.
  void reset() {
    if (_stage == MfaEnrolmentStage.idle &&
        _secret == null &&
        _enrolment == null) {
      return;
    }
    _secret = null;
    _enrolment = null;
    _stage = MfaEnrolmentStage.idle;
    _codeRefused = false;
    _notify();
  }

  Future<void> loadSecurityKeys({bool refresh = false}) async {
    if (_securityKeysLoading) return;
    if (_securityKeysLoaded && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _securityKeysLoading = true;
    _error = null;
    _notify();
    try {
      _securityKeys = await repository.loadSecurityKeys();
      _securityKeysLoaded = true;
    } on Object catch (error) {
      _error = error;
    } finally {
      _securityKeysLoading = false;
      _notify();
    }
  }

  /// Makes a security key: the password buys Discord's challenge, Windows
  /// makes the key, and Discord records the proof.
  ///
  /// The password is passed straight through to the one request that needs
  /// it and never kept, exactly like the other password-gated second-factor
  /// actions on this page.
  Future<bool> beginSecurityKeyEnrolment({
    required String name,
    required String password,
  }) async {
    final repository = _repositoryProvider();
    final ceremony = _securityKeyCeremony;
    final account = _securityKeyAccount?.call();
    final trimmed = name.trim();
    // A key with no name cannot be registered, and running the prompt for
    // one would end in a refusal the wording of which would be about
    // Discord rather than about the empty field.
    if (repository == null ||
        ceremony == null ||
        account == null ||
        trimmed.isEmpty) {
      return false;
    }
    if (_securityKeyStage == MfaSecurityKeyStage.prompting || _busy) {
      return false;
    }
    _securityKeyRefusal = null;
    _error = null;
    try {
      final challenge = await repository.requestSecurityKeyChallenge(password);
      if (challenge == null) {
        _securityKeyRefusal = MfaSecurityKeyRefusal.passwordRefused;
        return false;
      }
      _securityKeyStage = MfaSecurityKeyStage.prompting;
      _notify();
      final registration = await ceremony.createCredential(
        challenge: challenge,
        account: account,
      );
      if (registration == null) {
        _securityKeyStage = MfaSecurityKeyStage.idle;
        _securityKeyRefusal = MfaSecurityKeyRefusal.keyDeclined;
        return false;
      }
      final registered = await repository.registerSecurityKey(
        name: trimmed,
        challenge: challenge,
        registration: registration,
      );
      if (!registered) {
        _securityKeyStage = MfaSecurityKeyStage.idle;
        _securityKeyRefusal = MfaSecurityKeyRefusal.registrationRefused;
        return false;
      }
      _securityKeyStage = MfaSecurityKeyStage.added;
      _addedSecurityKey = SecurityKey(
        id: registration.credentialId,
        name: trimmed,
      );
      await loadSecurityKeys(refresh: true);
      return true;
    } on Object catch (error) {
      _securityKeyStage = MfaSecurityKeyStage.idle;
      _error = error;
      return false;
    } finally {
      _notify();
    }
  }

  /// Removes a key, gated on the account password.
  Future<bool> removeSecurityKey(SecurityKey key, String password) async {
    final repository = _repositoryProvider();
    if (repository == null || _busy) return false;
    _busy = true;
    _securityKeyRefusal = null;
    _error = null;
    _notify();
    try {
      final removed = await repository.removeSecurityKey(key, password);
      if (!removed) {
        _securityKeyRefusal = MfaSecurityKeyRefusal.removalRefused;
        return false;
      }
      _securityKeys = [
        for (final other in _securityKeys)
          if (other.id != key.id) other,
      ];
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Clears the added state, so the page goes back to offering another key.
  void dismissAddedSecurityKey() {
    if (_securityKeyStage != MfaSecurityKeyStage.added) return;
    _securityKeyStage = MfaSecurityKeyStage.idle;
    _addedSecurityKey = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
