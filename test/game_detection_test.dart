import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flutter_test/flutter_test.dart';

DetectableGame _game(
  String name, {
  List<String> executables = const [],
  List<String> aliases = const [],
  String? id,
}) => DetectableGame(
  id: id ?? '100000000000000000',
  name: name,
  aliases: aliases,
  executables: executables,
);

void main() {
  group('the detectable game model', () {
    test('reads the fields the mapping needs', () {
      final game = DetectableGame.fromPayload({
        'id': '999999999999999999',
        'name': 'Deep Rock Galactic',
        'aliases': ['DRG'],
        'executables': ['FSD-Win64-Shipping.exe'],
      });

      expect(game!.id, '999999999999999999');
      expect(game.name, 'Deep Rock Galactic');
      expect(game.aliases, ['DRG']);
      expect(game.executables, ['FSD-Win64-Shipping.exe']);
    });

    test('refuses a payload without an id or a name', () {
      expect(DetectableGame.fromPayload({'name': 'No id'}), isNull);
      expect(DetectableGame.fromPayload({'id': '1'}), isNull);
      expect(DetectableGame.fromPayload('not a map'), isNull);
      expect(DetectableGame.fromPayload(null), isNull);
    });

    test('drops empty strings from the list fields', () {
      final game = DetectableGame.fromPayload({
        'id': '2',
        'name': 'Game',
        'aliases': ['', 'Alias'],
        'executables': ['game.exe', 42],
      });

      expect(game!.aliases, ['Alias']);
      expect(game.executables, ['game.exe']);
    });
  });

  group('detection', () {
    test('maps a running executable to its game by the listed path', () {
      final activities = detectGames(
        ['fsd-win64-shipping.exe', 'steam.exe'],
        [
          _game('Deep Rock Galactic', executables: ['FSD-Win64-Shipping.exe']),
        ],
      );

      expect(activities, hasLength(1));
      expect(activities.single.name, 'Deep Rock Galactic');
      expect(activities.single.type, ActivityType.playing);
      expect(activities.single.applicationId, '100000000000000000');
    });

    test('the match ignores the directory of the listed executable', () {
      final activities = detectGames(
        ['deeprock.exe'],
        [
          _game(
            'Deep Rock Galactic',
            executables: [r'C:\Games\DRG\deeprock.exe'],
          ),
        ],
      );

      expect(activities.single.name, 'Deep Rock Galactic');
    });

    test('the match ignores case on both sides', () {
      final activities = detectGames(
        ['FsD-WiN64-SHiPPiNG.EXE'],
        [
          _game('Deep Rock Galactic', executables: ['fsd-win64-shipping.exe']),
        ],
      );

      expect(activities, hasLength(1));
    });

    test('matches a game by its name when no executable is listed', () {
      final activities = detectGames(['solstice'], [_game('Solstice')]);

      expect(activities.single.name, 'Solstice');
    });

    test('matches a game by one of its aliases', () {
      final activities = detectGames(
        ['drg'],
        [
          _game('Deep Rock Galactic', aliases: ['DRG']),
        ],
      );

      expect(activities.single.name, 'Deep Rock Galactic');
    });

    test('one scan publishes one game, however many match', () {
      final activities = detectGames(
        ['game-a.exe', 'game-b.exe'],
        [
          _game('Game A', executables: ['game-a.exe']),
          _game('Game B', executables: ['game-b.exe']),
        ],
      );

      expect(activities, hasLength(1));
    });

    test('a game running twice is published once', () {
      final activities = detectGames(
        ['game.exe', 'game.exe'],
        [
          _game('The Game', executables: ['game.exe']),
        ],
      );

      expect(activities.single.name, 'The Game');
    });

    test('nothing running publishes nothing', () {
      expect(
        detectGames(const <String>[], [
          _game('Deep Rock Galactic', executables: ['fsd.exe']),
        ]),
        isEmpty,
      );
    });

    test('nothing detectable publishes nothing', () {
      expect(detectGames(['fsd.exe'], const <DetectableGame>[]), isEmpty);
    });

    test('an executable nothing recognises publishes nothing', () {
      expect(
        detectGames(
          ['notepad.exe'],
          [
            _game('Solstice', aliases: ['SOL']),
          ],
        ),
        isEmpty,
      );
    });

    test('empty executable entries are skipped, not treated as a match', () {
      final activities = detectGames([''], [_game('Anything')]);

      expect(activities, isEmpty);
    });

    test('an activity is shareable only through the contextless flag', () {
      final activities = detectGames(
        ['game.exe'],
        [
          _game('The Game', executables: ['game.exe']),
        ],
      );

      expect(activities.single.hasFlag(ActivityFlag.contextless), isTrue);
    });
  });
}
