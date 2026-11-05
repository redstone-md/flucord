import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/user_notes.dart';
import '../domain/user_profile.dart';

/// Drives the full profile popover for somebody else.
///
/// One controller serves whichever user the popover is open on: the popover is
/// transient, the account and the notes are not, and keeping one controller
/// means opening the next profile costs no new subscriptions. The profile
/// plane is resolved through a provider for the same reason every account
/// surface is: a session swap must not fetch a profile with credentials that
/// just signed out.
final class MemberProfileController extends ChangeNotifier {
  MemberProfileController({
    required UserProfileRepository? Function() profileProvider,
    required UserNotesRepository? Function() notesProvider,
    String? Function(String guildId)? serverNameOf,
  }) : _profileProvider = profileProvider,
       _notesProvider = notesProvider,
       _serverNameOf = serverNameOf;

  final UserProfileRepository? Function() _profileProvider;
  final UserNotesRepository? Function() _notesProvider;
  final String? Function(String guildId)? _serverNameOf;

  StreamSubscription<UserNotes>? _notesSubscription;
  bool _disposed = false;

  String? _openUserId;
  String? _openServerId;
  bool _isLoading = false;
  Object? _error;
  OtherUserProfile? _profile;
  bool _profileUnavailable = false;

  /// The profile plane that gave the held answer. Another one means another
  /// account, whose answer may differ.
  UserProfileRepository? _answeredBy;
  bool _noteSaving = false;
  bool _noteRefused = false;

  /// Which user the popover is open on, or null when it is closed.
  String? get openUserId => _openUserId;

  OtherUserProfile? get profile => _profile;

  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Whether the fetch came back empty rather than failing: Discord refuses
  /// the profile route for somebody this account has no relationship with,
  /// and the popover answers that by showing what the roster already knows.
  bool get profileUnavailable => _profileUnavailable;

  bool get noteSaving => _noteSaving;

  /// Whether the last note write was refused, which is an answer to say in
  /// words rather than a broken session.
  bool get noteRefused => _noteRefused;

  /// The note kept on the open user, or null when there is none.
  String? get note => _notesProvider()?.current.noteFor(_openUserId ?? '');

  /// The name the workspace already holds for [guildId], or null when the
  /// server is not loaded. The profile route sends mutual servers as ids only.
  String? serverName(String guildId) => _serverNameOf?.call(guildId);

  /// Whether this transport can show a full profile or a note at all.
  bool get isSupported =>
      _profileProvider() != null || _notesProvider() != null;

  /// Opens the popover on [userId] in [serverId], or outside a server when
  /// it is null, fetching the profile and the notes.
  ///
  /// A profile the repository holds from earlier in the session shows at
  /// once and is replaced when the fresh one comes. The answer held for the
  /// same user and server is kept rather than refetched: the popover closes and reopens on the same person in a
  /// session's lifetime, and the profile route is rate-limited. A refusal
  /// is kept too. A failure is not, so the next open tries again, and
  /// neither is an answer given to another account.
  Future<void> open(String userId, {String? serverId}) async {
    if (_disposed) return;
    _bindNotes();
    final answered =
        (_profile != null || _profileUnavailable) &&
        identical(_answeredBy, _profileProvider());
    if (_openUserId == userId &&
        _openServerId == serverId &&
        (answered || _isLoading)) {
      return;
    }
    _openUserId = userId;
    _openServerId = serverId;
    // What this session last saw of them, shown while the fresh answer comes.
    _profile = _profileProvider()?.heldProfileOf(userId, serverId: serverId);
    _profileUnavailable = false;
    _error = null;
    _noteRefused = false;
    _notify();
    await _fetchProfile(userId, serverId);
  }

  /// Re-reads the profile of the open user, after a failure.
  Future<void> retry() async {
    final userId = _openUserId;
    if (userId == null || _disposed) return;
    _error = null;
    _notify();
    await _fetchProfile(userId, _openServerId);
  }

  /// Saves the note on the open user, or removes it when [text] is empty.
  ///
  /// A refused write leaves the field as it is and raises [noteRefused], so
  /// the popover can say what happened instead of dropping the text.
  Future<bool> saveNote(String text) async {
    final userId = _openUserId;
    final notes = _notesProvider();
    if (userId == null || notes == null || _disposed || _noteSaving) {
      return false;
    }
    final trimmed = text.trim();
    _noteRefused = false;
    _noteSaving = true;
    _notify();
    try {
      final taken = await notes.setNote(
        userId: userId,
        note: trimmed.isEmpty ? null : trimmed,
      );
      _noteRefused = !taken;
      return taken;
    } finally {
      _noteSaving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_notesSubscription?.cancel());
    _notesSubscription = null;
    super.dispose();
  }

  Future<void> _fetchProfile(String userId, String? serverId) async {
    final profile = _profileProvider();
    _answeredBy = profile;
    if (profile == null) {
      // A transport with no profile plane still shows the roster's answer,
      // which the popover draws from its own member row.
      _profileUnavailable = true;
      _notify();
      return;
    }
    _isLoading = true;
    _notify();
    try {
      final fetched = await profile.loadProfileOf(userId, serverId: serverId);
      if (!_isOpenOn(userId, serverId)) return;
      _profile = fetched;
      _profileUnavailable = fetched == null;
    } on Object catch (error) {
      if (!_isOpenOn(userId, serverId)) return;
      // A profile already on screen stays, so a failed refresh goes unseen.
      if (_profile == null) _error = error;
    } finally {
      _isLoading = false;
      if (!_disposed) _notify();
    }
  }

  bool _isOpenOn(String userId, String? serverId) =>
      _openUserId == userId && _openServerId == serverId;

  /// Follows the live notes store rather than one captured at construction,
  /// so a note edited on another device repaints the open popover.
  void _bindNotes() {
    final notes = _notesProvider();
    if (identical(notes, _boundNotes)) return;
    unawaited(_notesSubscription?.cancel());
    _notesSubscription = notes?.updates.listen((_) => _notify());
    _boundNotes = notes;
  }

  UserNotesRepository? _boundNotes;

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
