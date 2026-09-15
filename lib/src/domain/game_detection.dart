import 'chat_models.dart';

/// One application Discord can recognise as a game.
///
/// `GET /applications/detectable` answers these. The route is not on the
/// public protocol surface: it is the stopgap the official client itself uses
/// to map a running executable to the game a member card should name, and
/// Flucord reads only the four fields that mapping needs.
final class DetectableGame {
  const DetectableGame({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.executables = const [],
  });

  final String id;
  final String name;

  /// Other names the game is known under. A match on one is a match on the
  /// game.
  final List<String> aliases;

  /// The executables Discord lists for the game, as absolute or relative
  /// paths. Only the file name decides a match, because the same title
  /// installs under different directories on different machines.
  final List<String> executables;

  static DetectableGame? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final id = payload['id'];
    final name = payload['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return DetectableGame(
      id: id,
      name: name,
      aliases: _strings(payload['aliases']),
      executables: _strings(payload['executables']),
    );
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }
}

/// Reads the games Discord can recognise.
///
/// A capability of the transport, like the other repository surfaces: the
/// route answers to a signed-in account, so a demo or disconnected
/// repository reports null rather than offering a list nobody can fetch.
abstract interface class DetectableGameRepository {
  /// The games Discord can recognise as a game, or null when the list
  /// could not be read.
  Future<List<DetectableGame>?> detectableGames();
}

/// Maps the executables running on this machine to the games the account
/// sees.
///
/// The pure half of game detection: the scanner produces the basenames of
/// what is running, the transport supplies the games Discord can recognise,
/// and this function is the whole rule between them. It lives in the domain
/// because the rule is a fact about Discord's presence, not about either
/// producer, and because it is what the tests drive.
///
/// One running game is published, the first match: a member row carries the
/// game being played, and two entries for one process scan can only mean the
/// same title matched twice (an alias and its game), never two games at once.
/// The executable basename is matched against the game's listed executables
/// and against its name and aliases, case-insensitively, which is how a
/// launcher-styled executable name still finds its title.
List<UserActivity> detectGames(
  Iterable<String> runningExecutables,
  Iterable<DetectableGame> detectable,
) {
  final running = [
    for (final executable in runningExecutables)
      if (executable.isNotEmpty) executable.toLowerCase(),
  ];
  if (running.isEmpty) return const [];
  final found = <String, UserActivity>{};
  for (final game in detectable) {
    UserActivity? activity;
    for (final executable in game.executables) {
      final basename = _basename(executable).toLowerCase();
      if (basename.isEmpty || !running.contains(basename)) continue;
      activity = _activityFor(game);
      break;
    }
    activity ??= _byName(game, running);
    if (activity != null) found[game.id] = activity;
  }
  final activities = found.values.toList(growable: false);
  return activities.isEmpty ? const [] : activities.sublist(0, 1);
}

UserActivity _activityFor(DetectableGame game) => UserActivity(
  name: game.name,
  type: ActivityType.playing,
  applicationId: game.id,
  flags: ActivityFlag.contextless,
);

UserActivity? _byName(DetectableGame game, List<String> running) {
  final names = [game.name.toLowerCase(), ...game.aliases.map(_lower)];
  for (final name in names) {
    if (name.isEmpty) continue;
    for (final executable in running) {
      if (executable == name) return _activityFor(game);
    }
  }
  return null;
}

String _lower(String value) => value.toLowerCase();

/// The file name of a path, on either separator.
String _basename(String path) {
  final last = path.lastIndexOf(RegExp(r'[\\/]'));
  return last < 0 ? path : path.substring(last + 1);
}
