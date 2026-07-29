import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/application/voice_overlay_controller.dart';
import 'package:flucord/src/platform/voice_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the window is handed', () {
    test('straight RGBA becomes premultiplied BGRA', () {
      // Half-transparent red. Straight alpha here draws a dark fringe around
      // every edge, which is what UpdateLayeredWindow does with the wrong
      // format.
      final premultiplied = premultipliedBgraFromRgba(
        Uint8List.fromList([255, 0, 0, 128, 10, 20, 30, 255]),
      );

      expect(premultiplied.sublist(0, 4), [0, 0, 128, 128]);
      // Opaque pixels are only reordered, not scaled.
      expect(premultiplied.sublist(4), [30, 20, 10, 255]);
    });

    testWidgets('a roster is drawn at the size the rows need', (tester) async {
      // runAsync: rasterising goes through the engine, which the fake async
      // of a widget test never lets finish.
      final picture = await tester.runAsync(
        () => paintOverlay(const [
          OverlaySpeaker(name: 'Mira', isSpeaking: true),
          OverlaySpeaker(
            name: 'Someone with a very long display name',
            isSpeaking: false,
          ),
        ]),
      );

      expect(picture, isNotNull);
      expect(picture!.width, 220);
      expect(picture.height, 68);
      expect(picture.pixels.length, 220 * 68 * 4);
      // Something was actually drawn: an all-zero buffer is a blank rectangle.
      expect(picture.pixels.any((byte) => byte != 0), isTrue);
    });
  });

  group('the controller', () {
    test('nothing is drawn until somebody asks for it', () async {
      final overlay = _FakeOverlay();
      final controller = VoiceOverlayController(
        overlay: overlay,
        roster: () => const [OverlaySpeaker(name: 'Mira', isSpeaking: true)],
        isHiddenByStreamerMode: () => false,
      );
      addTearDown(controller.dispose);

      expect(controller.isWanted, isFalse);
      await controller.refresh();
      expect(overlay.shown, isEmpty);

      await controller.setEnabled(enabled: true);
      expect(overlay.shown.single.single.name, 'Mira');
      expect(controller.isWanted, isTrue);
    });

    test('streamer mode takes it off screen without turning it off', () async {
      final overlay = _FakeOverlay();
      var hidden = false;
      final controller = VoiceOverlayController(
        overlay: overlay,
        roster: () => const [OverlaySpeaker(name: 'Mira', isSpeaking: false)],
        isHiddenByStreamerMode: () => hidden,
      );
      addTearDown(controller.dispose);
      await controller.setEnabled(enabled: true);

      hidden = true;
      await controller.refresh();

      expect(overlay.hides, 1);
      // Still wanted: the mode hid it, nobody switched it off.
      expect(controller.isWanted, isTrue);

      hidden = false;
      await controller.refresh();
      expect(overlay.shown, hasLength(2));
    });

    test('an empty room is no overlay rather than an empty box', () async {
      final overlay = _FakeOverlay();
      final controller = VoiceOverlayController(
        overlay: overlay,
        roster: () => const [],
        isHiddenByStreamerMode: () => false,
      );
      addTearDown(controller.dispose);

      await controller.setEnabled(enabled: true);

      expect(overlay.shown.single, isEmpty);
    });

    test('toggling off hides it, and asking twice does nothing', () async {
      final overlay = _FakeOverlay();
      final controller = VoiceOverlayController(
        overlay: overlay,
        roster: () => const [OverlaySpeaker(name: 'Mira', isSpeaking: false)],
        isHiddenByStreamerMode: () => false,
      );
      addTearDown(controller.dispose);

      await controller.toggle();
      await controller.toggle();
      await controller.setEnabled(enabled: false);

      expect(overlay.shown, hasLength(1));
      expect(overlay.hides, 1);
      expect(controller.isWanted, isFalse);
    });

    test('a platform with no overlay says so', () async {
      const overlay = UnavailableVoiceOverlay();
      final controller = VoiceOverlayController(
        overlay: overlay,
        roster: () => const [],
        isHiddenByStreamerMode: () => false,
      );
      addTearDown(controller.dispose);

      expect(controller.isSupported, isFalse);
      expect(controller.isVisible, isFalse);
      expect(
        await overlay.show(const [
          OverlaySpeaker(name: 'Mira', isSpeaking: true),
        ]),
        isFalse,
      );
      overlay
        ..hide()
        ..close();
    });


    test('the real window takes a picture and goes away again', () async {
      const path = 'build/windows/x64/runner/Release/flucord_overlay.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final overlay = WindowsVoiceOverlay.withLibrary(
        DynamicLibrary.open(path),
      );
      addTearDown(overlay.close);

      expect(overlay.isSupported, isTrue);
      // A real layered window, put on screen and taken off within the test.
      expect(
        await overlay.show(const [
          OverlaySpeaker(name: 'Mira', isSpeaking: true),
        ]),
        isTrue,
      );
      expect(overlay.isVisible, isTrue);

      overlay.hide();
      expect(overlay.isVisible, isFalse);

      // An empty roster hides rather than drawing an empty box.
      expect(await overlay.show(const []), isFalse);
    });

    test('a build without the module never claims a window', () async {
      final overlay = WindowsVoiceOverlay.withLibrary(null);

      expect(overlay.isSupported, isFalse);
      expect(
        await overlay.show(const [
          OverlaySpeaker(name: 'Mira', isSpeaking: true),
        ]),
        isFalse,
      );
      expect(overlay.isVisible, isFalse);
    });
  });
}

final class _FakeOverlay implements VoiceOverlay {
  final List<List<OverlaySpeaker>> shown = [];
  int hides = 0;
  bool _visible = false;

  @override
  bool get isSupported => true;

  @override
  bool get isVisible => _visible;

  @override
  Future<bool> show(List<OverlaySpeaker> speakers) async {
    shown.add(speakers);
    _visible = speakers.isNotEmpty;
    return _visible;
  }

  @override
  void hide() {
    hides++;
    _visible = false;
  }

  @override
  void close() => _visible = false;
}
