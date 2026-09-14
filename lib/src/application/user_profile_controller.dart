import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/user_profile.dart';

/// Drives the profile editor.
///
/// The draft is deliberately separate from the saved profile: an edit is not
/// applied until the user saves, and the server's echo replaces the draft
/// afterwards because Discord normalises several fields. Keeping both means the
/// form can show unsaved changes, discard them, and never present a value the
/// account does not actually hold.
///
/// The repository is resolved through a provider rather than captured, for the
/// same reason the settings controller does it: the transport is replaced when
/// the session changes, and a captured repository would keep editing the
/// account that just signed out.
final class UserProfileController extends ChangeNotifier {
  UserProfileController(this._repositoryProvider);

  final UserProfileRepository? Function() _repositoryProvider;

  UserProfileRepository? _repository;
  StreamSubscription<UserProfile>? _updates;
  bool _bound = false;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _credentialRefused = false;
  Object? _error;
  bool _disposed = false;

  String? _displayNameDraft;
  String? _bioDraft;
  String? _pronounsDraft;
  ProfileImage _avatarDraft = const ProfileImage.untouched();
  ProfileImage _bannerDraft = const ProfileImage.untouched();
  ProfileValue<int> _accentDraft = const ProfileValue.untouched();

  /// Whether this transport can edit a profile at all.
  bool get isSupported {
    _bind();
    return _repository != null;
  }

  UserProfile? get profile => _repository?.current;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  Object? get error => _error;

  String get displayName => _displayNameDraft ?? profile?.displayName ?? '';
  String get bio => _bioDraft ?? profile?.bio ?? '';
  String get pronouns => _pronounsDraft ?? profile?.pronouns ?? '';
  ProfileImage get pendingAvatar => _avatarDraft;
  ProfileImage get pendingBanner => _bannerDraft;

  /// The accent as it would be saved: the draft when touched, otherwise the
  /// stored one. Null means the avatar's own colour stands in.
  int? get accentColor =>
      _accentDraft.isUntouched ? profile?.accentColor : _accentDraft.value;

  /// Whether anything is waiting to be saved.
  bool get hasChanges => !_patch().isEmpty;

  /// Attaches to the active transport, reloading when it changes.
  void reconcile() {
    if (_bind()) unawaited(load());
  }

  Future<void> load() async {
    _bind();
    final repository = _repository;
    if (repository == null || _isLoading || _disposed) return;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      await repository.load();
    } on Object catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void editDisplayName(String value) {
    _displayNameDraft = value;
    _notify();
  }

  void editBio(String value) {
    _bioDraft = value;
    _notify();
  }

  void editPronouns(String value) {
    _pronounsDraft = value;
    _notify();
  }

  /// Stages a new avatar as a data URI, or removes the current one.
  void editAvatar(String? dataUri) {
    _avatarDraft = dataUri == null
        ? const ProfileImage.removed()
        : ProfileImage.replaced(dataUri);
    _notify();
  }

  void editBanner(String? dataUri) {
    _bannerDraft = dataUri == null
        ? const ProfileImage.removed()
        : ProfileImage.replaced(dataUri);
    _notify();
  }

  void editAccentColor(int? value) {
    _accentDraft = value == null
        ? const ProfileValue.cleared()
        : ProfileValue.set(value);
    _notify();
  }

  /// Throws away everything unsaved.
  void discard() {
    _clearDrafts();
    _error = null;
    _notify();
  }

  Future<bool> save() async {
    final repository = _repository;
    final patch = _patch();
    if (repository == null || _isSaving || patch.isEmpty) return false;
    _isSaving = true;
    _error = null;
    _notify();
    try {
      await repository.apply(patch);
      _clearDrafts();
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isSaving = false;
      _notify();
    }
  }

  /// Changes the account name, which Discord gates on the password.
  ///
  /// Separate from [save] on purpose: an ordinary profile edit must not carry
  /// a password, and a name change must not be bundled with a bio edit that
  /// would then need one too.
  Future<bool> changeUsername({
    required String username,
    required String password,
  }) => _applyCredentialChange(
    UserProfilePatch(username: username.trim(), password: password),
  );

  /// Changes the password. Discord reissues the session token when it takes
  /// one, which the session vault picks up on its own next write.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _applyCredentialChange(
    UserProfilePatch(newPassword: newPassword, password: currentPassword),
  );

  /// Whether the last credential change was refused — a wrong password, or a
  /// name somebody else already has. Not a failure: both are answers.
  bool get wasCredentialChangeRefused => _credentialRefused;

  Future<bool> _applyCredentialChange(UserProfilePatch patch) async {
    // Bind first: this can be the first thing a session is asked to do, and
    // an unbound controller would answer "no transport" for a transport that
    // is there.
    _bind();
    final repository = _repository;
    if (repository == null || _isSaving) return false;
    if (patch.isEmpty || (patch.password ?? '').isEmpty) return false;
    _isSaving = true;
    _error = null;
    _credentialRefused = false;
    _notify();
    try {
      final updated = await repository.apply(patch);
      _credentialRefused = updated == null;
      return updated != null;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isSaving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  /// Only fields the user actually changed, compared against the saved value so
  /// typing a name and typing it back is not a change.
  UserProfilePatch _patch() {
    final saved = profile;
    return UserProfilePatch(
      displayName: _changed(_displayNameDraft, saved?.displayName),
      bio: _changed(_bioDraft, saved?.bio),
      pronouns: _changed(_pronounsDraft, saved?.pronouns),
      accentColor: _accentDraft,
      avatar: _avatarDraft,
      banner: _bannerDraft,
    );
  }

  static String? _changed(String? draft, String? saved) =>
      draft == null || draft == (saved ?? '') ? null : draft;

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen(_acceptRemote);
    _clearDrafts();
    _error = null;
    return true;
  }

  void _acceptRemote(UserProfile profile) {
    // A change made on another device lands here. Unsaved drafts stay, because
    // silently replacing what the user is typing would lose their work.
    _notify();
  }

  void _clearDrafts() {
    _displayNameDraft = null;
    _bioDraft = null;
    _pronounsDraft = null;
    _avatarDraft = const ProfileImage.untouched();
    _bannerDraft = const ProfileImage.untouched();
    _accentDraft = const ProfileValue.untouched();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
