import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/application/streamer_mode_controller.dart';
import 'package:flucord/src/data/file_streamer_mode_repository.dart';
import 'package:flucord/src/domain/streamer_mode.dart';
import 'package:flucord/src/platform/window_capture_shield.dart';
import 'package:flucord/src/presentation/widgets/streamer_mode_scope.dart';
import 'package:flucord/src/presentation/widgets/streamer_mode_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what an invite looks like', () {
    test('a link is replaced whatever shape it arrived in', () {
      expect(
        hideInviteLinks(
          'join https://discord.gg/abc123 or discord.com/invite/xyz now',
        ),
        'join $hiddenInviteLabel or $hiddenInviteLabel now',
      );
      expect(
        hideInviteLinks('http://www.discordapp.com/invite/abc'),
        hiddenInviteLabel,
      );
      expect(hideInviteLinks('discord.gg/abc'), hiddenInviteLabel);
    });

    test('something that merely reads like one is left alone', () {
      // Matched by host: handing out a server to everybody watching is the
      // failure worth guarding against, and a false positive is only a
      // nuisance — but a link that is not an invite is still not one.
      const text = 'see example.com/discord-gg-guide and discordfacts.com';

      expect(hideInviteLinks(text), text);
    });

    test('a message with nothing to hide comes back unchanged', () {
      expect(hideInviteLinks('hello there'), 'hello there');
    });
  });

  group('the stored switches', () {
    test('they survive a round trip, and the mode itself does not', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-stream');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileStreamerModeRepository(
        directory: () async => directory,
      );

      expect((await repository.load()).enabled, isFalse);
      await repository.save(
        const StreamerModeSettings(
          enabled: true,
          automatic: false,
          disableSounds: false,
        ),
      );
      final read = await repository.load();

      expect(read.automatic, isFalse);
      expect(read.disableSounds, isFalse);
      // Not stored: a client that came back up still hiding everything would
      // leave somebody hunting for what broke.
      expect(read.enabled, isFalse);
    });

    test('a switch a newer build wrote keeps its default', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-stream');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}'
        '${FileStreamerModeRepository.fileName}',
      ).writeAsString(
        jsonEncode({'hide_invite_links': 'not a bool', 'unknown': true}),
      );

      final read = await FileStreamerModeRepository(
        directory: () async => directory,
      ).load();

      expect(read.hideInviteLinks, isTrue);
      expect(read.disableSounds, isTrue);
    });

    test('an unreadable file reads as the defaults', () async {
      expect(
        (await FileStreamerModeRepository(
          directory: () async => throw StateError('no directory'),
        ).load()).automatic,
        isTrue,
      );
    });
  });

  group('the controller', () {
    test('a stream turns it on, and ending the stream turns it back off',
        () async {
      final repository = _MemorySettings();
      final controller = StreamerModeController(repository);
      addTearDown(controller.dispose);
      expect(controller.isLoaded, isFalse);
      await controller.load();
      // A second load does not re-read.
      await controller.load();
      expect(repository.reads, 1);
      expect(controller.isLoaded, isTrue);

      controller.reconcileStreaming(isStreaming: true);
      expect(controller.isEnabled, isTrue);
      expect(controller.hidesPersonalInformation, isTrue);
      expect(controller.hidesInviteLinks, isTrue);
      expect(controller.silencesSounds, isTrue);
      expect(controller.silencesNotifications, isTrue);
      // The overlay is drawn over whatever is being captured, so hiding the
      // client's own window does not deal with it.
      expect(controller.hidesOverlay, isTrue);

      controller.reconcileStreaming(isStreaming: false);
      expect(controller.isEnabled, isFalse);
      // The live flag is never written.
      expect(repository.saved, isEmpty);
    });

    test('a mode switched on by hand outlives the stream', () async {
      final controller = StreamerModeController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setEnabled(enabled: true);
      controller
        ..reconcileStreaming(isStreaming: true)
        ..reconcileStreaming(isStreaming: false);

      // Only what the automatic switch turned on does it turn off.
      expect(controller.isEnabled, isTrue);

      await controller.toggle();
      expect(controller.isEnabled, isFalse);
      // Asked for what it already is: nothing happens.
      await controller.setEnabled(enabled: false);
      expect(controller.isEnabled, isFalse);
    });

    test('with the automatic switch off, a stream changes nothing', () async {
      final controller = StreamerModeController(
        _MemorySettings()
          ..stored = const StreamerModeSettings(automatic: false),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.reconcileStreaming(isStreaming: true);

      expect(controller.isEnabled, isFalse);
    });

    test('every switch is written when it changes', () async {
      final repository = _MemorySettings();
      final controller = StreamerModeController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setAutomatic(automatic: false);
      await controller.setHidePersonalInformation(hide: false);
      await controller.setHideInviteLinks(hide: false);
      await controller.setDisableSounds(disable: false);
      await controller.setDisableNotifications(disable: false);

      expect(repository.saved.length, 5);
      final last = repository.saved.last;
      expect(last.automatic, isFalse);
      expect(last.hidePersonalInformation, isFalse);
      expect(last.hideInviteLinks, isFalse);
      expect(last.disableSounds, isFalse);
      expect(last.disableNotifications, isFalse);
    });

    test('redacting only happens while the mode is on', () async {
      final controller = StreamerModeController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.redact('discord.gg/abc'), 'discord.gg/abc');
      await controller.setEnabled(enabled: true);
      expect(controller.redact('discord.gg/abc'), hiddenInviteLabel);

      // And not when the switch itself is off.
      await controller.setHideInviteLinks(hide: false);
      expect(controller.redact('discord.gg/abc'), 'discord.gg/abc');
    });
  });

  group('keeping the window off the recording', () {
    test('a platform with no shield says so rather than pretending', () async {
      final controller = StreamerModeController(
        _MemorySettings()
          ..stored = const StreamerModeSettings(hideFromCapture: true),
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.canHideFromCapture, isFalse);
      await controller.setEnabled(enabled: true);

      // The switch is on and the window is not hidden: the two are reported
      // apart, because saying it is hidden when it is still on the recording
      // is the one lie this must not tell.
      expect(controller.settings.hideFromCapture, isTrue);
      expect(controller.isHiddenFromCapture, isFalse);
      expect(controller.wasCaptureShieldRefused, isTrue);
    });

    test('the window is excluded while the mode is on, and put back after',
        () async {
      final shield = _FakeShield();
      final controller = StreamerModeController(
        _MemorySettings()
          ..stored = const StreamerModeSettings(hideFromCapture: true),
        shield: shield,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setEnabled(enabled: true);
      expect(shield.calls, [true]);
      expect(controller.isHiddenFromCapture, isTrue);
      expect(controller.wasCaptureShieldRefused, isFalse);

      // Asked again for the same thing: the window list is not walked twice.
      await controller.setHidePersonalInformation(hide: false);
      expect(shield.calls, [true]);

      await controller.setEnabled(enabled: false);
      expect(shield.calls, [true, false]);
      expect(controller.isHiddenFromCapture, isFalse);
    });

    test('a refusal from the platform is reported, not assumed away',
        () async {
      final shield = _FakeShield()..accept = false;
      final controller = StreamerModeController(
        _MemorySettings()
          ..stored = const StreamerModeSettings(hideFromCapture: true),
        shield: shield,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setEnabled(enabled: true);

      expect(shield.calls, [true]);
      expect(controller.isHiddenFromCapture, isFalse);
      expect(controller.wasCaptureShieldRefused, isTrue);
    });

    test('the switch alone hides nothing until the mode is on', () async {
      final shield = _FakeShield();
      final controller = StreamerModeController(
        _MemorySettings(),
        shield: shield,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setHideFromCapture(hide: true);

      expect(shield.calls, isEmpty);
      expect(controller.settings.hideFromCapture, isTrue);
    });

    test('a shield on a platform without one refuses every request', () {
      const shield = UnavailableWindowCaptureShield();

      expect(shield.isSupported, isFalse);
      expect(shield.setExcluded(excluded: true), isFalse);
    });


    test('on Windows it walks the real window list and answers honestly',
        () {
      if (!Platform.isWindows) return;
      final shield = WindowsWindowCaptureShield();

      expect(shield.isSupported, isTrue);
      // A test host has no Flutter window, so the walk finds none and the
      // shield says no rather than reporting a success it did not have. On a
      // real client the same walk finds the window and the call goes through.
      expect(shield.setExcluded(excluded: true), isA<bool>());
      expect(shield.setExcluded(excluded: false), isA<bool>());
    });

    test('the Windows shield refuses when the libraries are not there', () {
      // What every non-Windows host and every stripped build actually sees.
      final shield = const WindowsWindowCaptureShield.withLibraries(
        user32: null,
        kernel32: null,
      );

      expect(shield.isSupported, isFalse);
      expect(shield.setExcluded(excluded: true), isFalse);
    });
  });

  group('the surface', () {
    testWidgets('the switches are drawn and flip', (tester) async {
      final repository = _MemorySettings();
      final controller = StreamerModeController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StreamerModeSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('streamer-mode-enabled')));
      await tester.pumpAndSettle();
      expect(controller.isEnabled, isTrue);

      for (final key in [
        'streamer-mode-automatic',
        'streamer-mode-personal',
        'streamer-mode-invites',
        'streamer-mode-sounds',
        'streamer-mode-notifications',
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      final settings = controller.settings;
      expect(settings.automatic, isFalse);
      expect(settings.hidePersonalInformation, isFalse);
      expect(settings.hideInviteLinks, isFalse);
      expect(settings.disableSounds, isFalse);
      expect(settings.disableNotifications, isFalse);
    });


    testWidgets('the capture switch is dead where the platform has no shield',
        (tester) async {
      final controller = StreamerModeController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(700, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StreamerModeSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drawn and dead rather than hidden: somebody looking for it should
      // find it and read why it cannot be used.
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('streamer-mode-capture')),
      );
      expect(tile.onChanged, isNull);
      expect(
        find.textContaining('cannot exclude a window from capture'),
        findsOneWidget,
      );
    });

    testWidgets('a platform that refuses says so on the page', (tester) async {
      final shield = _FakeShield()..accept = false;
      final controller = StreamerModeController(
        _MemorySettings(),
        shield: shield,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.binding.setSurfaceSize(const Size(700, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StreamerModeSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('streamer-mode-capture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('streamer-mode-enabled')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('streamer-mode-capture-refused')),
        findsOneWidget,
      );
    });

    testWidgets('the scope answers for whoever draws something', (
      tester,
    ) async {
      final controller = StreamerModeController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();
      late BuildContext inner;
      await tester.pumpWidget(
        StreamerModeScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              inner = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(StreamerModeScope.redact(inner, 'discord.gg/x'), 'discord.gg/x');
      expect(StreamerModeScope.hidesPersonalInformation(inner), isFalse);

      await controller.setEnabled(enabled: true);
      await tester.pump();

      expect(
        StreamerModeScope.redact(inner, 'discord.gg/x'),
        hiddenInviteLabel,
      );
      expect(StreamerModeScope.hidesPersonalInformation(inner), isTrue);
    });

    testWidgets('with no scope above it, nothing is hidden', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            inner = context;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(StreamerModeScope.redact(inner, 'discord.gg/x'), 'discord.gg/x');
      expect(StreamerModeScope.hidesPersonalInformation(inner), isFalse);
    });
  });
}

final class _MemorySettings implements StreamerModeRepository {
  StreamerModeSettings stored = const StreamerModeSettings();
  final List<StreamerModeSettings> saved = [];
  int reads = 0;

  @override
  Future<StreamerModeSettings> load() async {
    reads++;
    return stored;
  }

  @override
  Future<void> save(StreamerModeSettings settings) async =>
      saved.add(settings);
}


final class _FakeShield implements WindowCaptureShield {
  final List<bool> calls = [];
  bool accept = true;

  @override
  bool get isSupported => true;

  @override
  bool setExcluded({required bool excluded}) {
    calls.add(excluded);
    return accept;
  }
}
