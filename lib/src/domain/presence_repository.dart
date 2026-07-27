import 'chat_models.dart';

/// How a custom status should expire.
///
/// Discord stores the expiry as an absolute millisecond stamp, but every
/// client offers the same fixed menu of durations, and computing the stamp
/// from a duration in one place keeps the surface from having to know that the
/// account clock is what the server compares against.
enum CustomStatusDuration {
  never(null),
  thirtyMinutes(Duration(minutes: 30)),
  oneHour(Duration(hours: 1)),
  fourHours(Duration(hours: 4)),
  today(Duration(hours: 24));

  const CustomStatusDuration(this.duration);

  final Duration? duration;

  String get label => switch (this) {
    never => "Don't clear",
    thirtyMinutes => '30 minutes',
    oneHour => '1 hour',
    fourHours => '4 hours',
    today => 'Today',
  };

  /// The epoch-millisecond stamp Discord stores, or `0` for "never".
  int expiryAt(DateTime now) {
    final span = duration;
    return span == null ? 0 : now.add(span).millisecondsSinceEpoch;
  }
}

/// The presence plane a transport can carry.
///
/// Presence is not a property of an account but of a live socket: only a
/// transport that holds the gateway connection can broadcast opcode 3 or be
/// told what anybody else is doing. Stating the capability here — rather than
/// letting a surface guess from the repository's runtime type — is what lets a
/// bot or demo transport say honestly that it has none, and keeps the status
/// picker from offering a control that could never take effect.
abstract interface class PresenceService {
  /// What this client is broadcasting for the signed-in account, idle
  /// promotion included.
  SelfPresence get selfPresence;

  /// The status the account chose, before the idle promotion rewrites it.
  ///
  /// A user who picked Online and walked away broadcasts Idle; the picker must
  /// still show Online as the selected row, or the next frame would silently
  /// make the promotion permanent.
  Presence get chosenStatus;

  /// The custom status as stored, or null when the account carries none.
  UserActivity? get customStatus;

  /// The account's other logged-in clients, newest information first.
  List<UserSession> get sessions;

  /// Emits whenever [selfPresence], [chosenStatus] or [sessions] change.
  Stream<SelfPresence> get selfPresenceUpdates;

  /// Whether the account's stored settings have arrived, which is what makes a
  /// write legal: a status group rebuilt from nothing would erase preferences
  /// this client does not model.
  bool get canEdit;

  /// Chooses the account's status. Only [Presence.selectable] values are sent;
  /// anything else is refused rather than written to the account.
  Future<void> setStatus(Presence status);

  /// Sets the custom status message and its emoji.
  ///
  /// An empty [text] and an empty [emojiName] together mean "clear it", which
  /// Discord models as removing the whole submessage rather than blanking its
  /// leaves.
  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  });

  /// Records real user input so the idle machine knows the user is here.
  void markActive();
}
