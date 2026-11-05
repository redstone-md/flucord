import 'package:flucord/src/presentation/widgets/discord_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// A relative timestamp reads in seconds under a minute away, so it is
/// redrawn every second there, and every minute further out.
void main() {
  final now = DateTime.utc(2026, 11, 5, 12);
  String stamp(Duration from) =>
      '<t:${now.add(from).millisecondsSinceEpoch ~/ 1000}:R>';

  test('a timestamp seconds away is redrawn every second', () {
    expect(
      DiscordMarkdown.relativeRefresh(
        'ends ${stamp(const Duration(seconds: -30))}',
        now,
      ),
      const Duration(seconds: 1),
    );
  });

  test('a timestamp minutes away is redrawn every minute', () {
    expect(
      DiscordMarkdown.relativeRefresh(
        'starts ${stamp(const Duration(minutes: 5))}',
        now,
      ),
      const Duration(minutes: 1),
    );
  });

  test('a body with no relative timestamp needs no redraw', () {
    expect(DiscordMarkdown.relativeRefresh('plain text', now), isNull);
  });
}
