import 'dart:math';

/// Computes the member-list row ranges a viewport should subscribe to.
///
/// Discord pages member lists in fixed 100-row windows and always keeps the
/// head page subscribed, because the group headers and the first members are
/// what every other index is measured against. Reproducing the page alignment
/// and the half-viewport overscan matters: a subscription that is not aligned
/// to a page boundary gets no rows back at all.
abstract final class DiscordMemberListRanges {
  static const pageSize = 100;

  /// The range every subscribed channel starts with.
  static const initial = <List<int>>[
    [0, pageSize - 1],
  ];

  /// Pages covering the viewport plus half a viewport of overscan.
  ///
  /// The result always begins with `[0, 99]` and is ascending, page-aligned,
  /// and non-overlapping.
  static List<List<int>> forViewport({
    required double scrollOffset,
    required double viewportHeight,
    required double rowHeight,
  }) {
    if (rowHeight <= 0 || viewportHeight <= 0) return initial;
    final offset = max(0.0, scrollOffset);

    int rowsOf(double pixels, [int delta = 0]) =>
        max(0, (pixels / rowHeight).ceil() + delta);

    final overscan = rowsOf(viewportHeight / 2);
    var low = rowsOf(offset, -overscan);
    final high = rowsOf(offset + viewportHeight, overscan);

    final ranges = <List<int>>[];
    int emit(int start) {
      ranges.add([start, start + pageSize - 1]);
      return start + pageSize;
    }

    if (low > 0) low = max(emit(0), low);
    low = (low ~/ pageSize) * pageSize;
    while (low <= high) {
      low = emit(low);
    }
    return List<List<int>>.unmodifiable(ranges.map(List<int>.unmodifiable));
  }

  /// Whether two range sets describe the same subscription.
  ///
  /// The renderer suppresses a resend when the recomputed pages are unchanged,
  /// which is what keeps scrolling from flooding the socket.
  static bool sameRanges(List<List<int>> a, List<List<int>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final left = a[index];
      final right = b[index];
      if (left.length != right.length) return false;
      for (var part = 0; part < left.length; part++) {
        if (left[part] != right[part]) return false;
      }
    }
    return true;
  }
}
