part of 'message_search_grammar.dart';

/// One word of the search bar, already unquoted.
final class _MessageSearchToken {
  const _MessageSearchToken({
    required this.text,
    required this.value,
    this.filter,
  });

  /// The token as the user typed it, used when a filter has to be reported
  /// back as unusable.
  final String text;

  /// The part after `filter:`, or the whole word when this is free text.
  final String value;

  /// The lower-cased filter name, or null for free text.
  final String? filter;
}

/// Splits search-bar text into tokens.
///
/// Whitespace separates words unless it sits inside double quotes, and inside
/// quotes `\"` and `\\` are escapes — the same rules Discord re-serialises a
/// filter answer with, so text a user pasted back out of the bar parses to
/// what it came from. A colon only starts a filter when it appears outside
/// quotes, which is what keeps `"12:30"` a search for a time.
abstract final class _MessageSearchTokens {
  /// The filter words this grammar understands. A colon after anything else is
  /// an ordinary character, so `note:` stays free text.
  static const filters = {
    'from',
    'mentions',
    'has',
    'in',
    'pinned',
    'before',
    'after',
  };

  static List<_MessageSearchToken> split(String text) {
    final tokens = <_MessageSearchToken>[];
    final raw = StringBuffer();
    final value = StringBuffer();
    var quoted = false;
    var escaped = false;
    var colonAt = -1;

    void flush() {
      if (raw.isEmpty && value.isEmpty) return;
      final token = value.toString();
      final source = raw.toString();
      final name = colonAt > 0
          ? token.substring(0, colonAt).toLowerCase()
          : null;
      tokens.add(
        name != null && filters.contains(name)
            ? _MessageSearchToken(
                text: source,
                value: token.substring(colonAt + 1),
                filter: name,
              )
            : _MessageSearchToken(text: source, value: token),
      );
      raw.clear();
      value.clear();
      colonAt = -1;
    }

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      raw.write(char);
      if (escaped) {
        value.write(char);
        escaped = false;
        continue;
      }
      if (quoted) {
        if (char == r'\') {
          escaped = true;
          continue;
        }
        if (char == '"') {
          quoted = false;
          continue;
        }
        value.write(char);
        continue;
      }
      if (char == '"') {
        quoted = true;
        continue;
      }
      if (_isSpace(char)) {
        // The separator itself is not part of the token it ended.
        final source = raw.toString();
        raw
          ..clear()
          ..write(source.substring(0, source.length - 1));
        flush();
        continue;
      }
      if (char == ':' && colonAt < 0) colonAt = value.length;
      value.write(char);
    }
    flush();
    return tokens;
  }

  static bool _isSpace(String char) => char.trim().isEmpty;
}

/// A `before:`/`after:` answer, resolved to the span of time it names.
///
/// Discord accepts a day, a month or a whole year and turns each into a
/// half-open `[start, end)` range in local time; `before:` then keeps the lower
/// edge as an upper bound and `after:` keeps the upper edge as a lower bound.
final class _MessageSearchDate {
  const _MessageSearchDate({
    required this.startMillis,
    required this.endMillis,
  });

  final int startMillis;
  final int endMillis;

  static final _pattern = RegExp(r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$');

  static _MessageSearchDate? parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = match.group(2) == null ? null : int.parse(match.group(2)!);
    final day = match.group(3) == null ? null : int.parse(match.group(3)!);
    if (month != null && (month < 1 || month > 12)) return null;
    if (day != null && day < 1) return null;
    final start = DateTime(year, month ?? 1, day ?? 1);
    // A day that overflowed its month — 2024-02-31 — rolls forward silently in
    // Dart, which would search a range the user never named.
    if (day != null && (start.day != day || start.month != month)) return null;
    final end = switch ((month, day)) {
      (null, _) => DateTime(year + 1),
      (final m?, null) => DateTime(year, m + 1),
      (final m?, final d?) => DateTime(year, m, d + 1),
    };
    return _MessageSearchDate(
      startMillis: start.millisecondsSinceEpoch,
      endMillis: end.millisecondsSinceEpoch,
    );
  }
}
