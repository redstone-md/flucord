import 'package:flucord/src/data/discord/discord_profile_frames.dart';
import 'package:flucord/src/domain/profile_frame.dart';
import 'package:flutter_test/flutter_test.dart';

// FLUCORD-108: how the shop's product answer becomes a frame.

const _sku = '100000000000000401';

/// The shop's answer with one product: another colour first, then [_sku]
/// with [layers].
Map<String, Object?> _answer(List<Map<String, Object?>> layers) => {
  'products': [
    {
      'id': '100000000000000400',
      'skus': [
        _colour('100000000000000402', [
          {'id': '100000000000000431', 'order': 'front', 'anchor': 'top'},
        ]),
        _colour(_sku, layers),
      ],
    },
  ],
};

Map<String, Object?> _colour(String sku, List<Map<String, Object?>> layers) => {
  'id': sku,
  'tenant_metadata': {
    'collectibles': {
      'item': {
        'type': 3,
        'sku_id': sku,
        'layers': layers,
        'inner_width': 1200,
        'overflow_top': 211,
        'overflow_bottom': 186,
        'overflow_horizontal': 56,
      },
    },
  },
};

void main() {
  test('reads a three-layer frame with a centred border behind the card', () {
    final frame = DiscordProfileFrames.read(
      _answer([
        {'id': '100000000000000421', 'order': 'back', 'anchor': 'center'},
        {'id': '100000000000000422', 'order': 'front', 'anchor': 'top'},
        {'id': '100000000000000423', 'order': 'front', 'anchor': 'bottom'},
      ]),
      _sku,
    )!;

    expect(frame.innerWidth, 1200);
    expect(
      [for (final layer in frame.layers) (layer.anchor, layer.inFront)],
      [
        (ProfileFrameAnchor.center, false),
        (ProfileFrameAnchor.top, true),
        (ProfileFrameAnchor.bottom, true),
      ],
    );
    expect(
      frame.layers.first.src,
      'https://cdn.discordapp.com/media/v1/collectibles-shop/'
      '$_sku/100000000000000421/static',
    );
  });

  test('a frame the answer does not describe reads as none', () {
    expect(
      DiscordProfileFrames.read(_answer(const []), _sku),
      isNull,
      reason: 'no pictures',
    );
    expect(
      DiscordProfileFrames.read(_answer(const []), '100000000000000499'),
      isNull,
      reason: 'another SKU',
    );
  });
}
