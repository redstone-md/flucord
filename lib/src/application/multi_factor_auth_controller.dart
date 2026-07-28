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

/// Drives the two-factor page.
///
/// The secret lives only here and only until the enrolment finishes or the
/// page closes. It is a credential: nothing writes it to disk, and the page
/// that showed it forgets it on the way out.
final class MultiFactorAuthController extends ChangeNotifier {
  MultiFactorAuthController(this._repositoryProvider, {Random? random})
    : _random = random;

  final MultiFactorAuthRepository? Function() _repositoryProvider;
  final Random? _random;

  TotpSecret? _secret;
  MfaEnrolment? _enrolment;
  MfaEnrolmentStage _stage = MfaEnrolmentStage.idle;
  Object? _error;
  bool _busy = false;
  bool _codeRefused = false;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  MfaEnrolmentStage get stage => _stage;
  TotpSecret? get secret => _secret;
  bool get isBusy => _busy;
  Object? get error => _error;

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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
