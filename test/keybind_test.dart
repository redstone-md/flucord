import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/application/keybind_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/application/voice_channel_surface.dart';
import 'package:flucord/src/data/file_keybind_repository.dart';
import 'package:flucord/src/domain/keybind.dart';
import 'package:flucord/src/platform/global_keyboard_hook.dart';
import 'package:flucord/src/presentation/widgets/keybind_section.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/application/streamer_mode_controller.dart';
import 'package:flucord/src/domain/streamer_mode.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the stored file', () {
    test('a binding survives a round trip', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-keys');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileKeybindRepository(directory: () async => directory);

      // Nothing stored yet is an empty map, not a failure.
      expect(await repository.load(), isEmpty);

      await repository.save({
        KeybindAction.pushToTalk: Keybind(
          keyId: LogicalKeyboardKey.keyT.keyId,
          modifiers: const {KeybindModifier.control, KeybindModifier.shift},
        ),
      });
      final read = await repository.load();

      expect(read.keys, [KeybindAction.pushToTalk]);
      expect(read[KeybindAction.pushToTalk]!.keyId, LogicalKeyboardKey.keyT.keyId);
      expect(read[KeybindAction.pushToTalk]!.modifiers, {
        KeybindModifier.control,
        KeybindModifier.shift,
      });
    });

    test('an entry a newer build wrote is skipped, not fatal', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-keys');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}${FileKeybindRepository.fileName}',
      ).writeAsString(
        jsonEncode({
          'TOGGLE_OVERLAY': {'key': 1},
          'TOGGLE_MUTE': {'key': 2, 'modifiers': ['control', 'nonsense']},
          'TOGGLE_DEAFEN': 'not a binding',
        }),
      );
      final repository = FileKeybindRepository(directory: () async => directory);

      final read = await repository.load();

      // The action Flucord does not have and the entry that is not a binding
      // are dropped; the modifier it does not know is dropped from within one.
      expect(read.keys, [KeybindAction.toggleMute]);
      expect(read[KeybindAction.toggleMute]!.modifiers, {
        KeybindModifier.control,
      });
    });

    test('a file that is not a map, or not readable, reads as nothing',
        () async {
      final directory = await Directory.systemTemp.createTemp('flucord-keys');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}${FileKeybindRepository.fileName}',
      ).writeAsString('["not", "a", "map"]');

      expect(
        await FileKeybindRepository(directory: () async => directory).load(),
        isEmpty,
      );
      expect(
        await FileKeybindRepository(
          directory: () async => throw StateError('no directory'),
        ).load(),
        isEmpty,
      );
    });
  });

  group('the controller', () {
    testWidgets('a recorded chord is assigned, saved and then fires', (
      tester,
    ) async {
      final repository = _MemoryKeybinds();
      final fired = <(KeybindAction, bool)>[];
      final controller = KeybindController(
        repository: repository,
        onTriggered: (action, {required pressed}) =>
            fired.add((action, pressed)),
      );
      addTearDown(controller.dispose);
      await controller.load();
      // A second load does not re-read: the bindings are already held.
      await controller.load();
      expect(repository.reads, 1);
      _install(controller);

      controller.record(KeybindAction.toggleMute);
      expect(controller.recording, KeybindAction.toggleMute);

      // A modifier alone is somebody still building the chord.
      await _press(tester, LogicalKeyboardKey.controlLeft, hold: true);
      expect(controller.recording, KeybindAction.toggleMute);
      await _press(tester, LogicalKeyboardKey.keyM);
      await tester.pump();
      await _release(tester, LogicalKeyboardKey.controlLeft);

      final binding = controller.bindingFor(KeybindAction.toggleMute)!;
      expect(binding.keyId, LogicalKeyboardKey.keyM.keyId);
      expect(binding.modifiers, {KeybindModifier.control});
      expect(binding.label, 'Ctrl + M');
      expect(repository.saved.single.keys, [KeybindAction.toggleMute]);
      expect(controller.recording, isNull);

      // And now the chord runs the action rather than being recorded.
      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyM);
      expect(fired, [(KeybindAction.toggleMute, true)]);
    });

    testWidgets('a hold action runs while held and ends on release', (
      tester,
    ) async {
      final fired = <(KeybindAction, bool)>[];
      final controller = await _controllerWith(
        {
          KeybindAction.pushToTalk: Keybind(
            keyId: LogicalKeyboardKey.f1.keyId,
          ),
        },
        onTriggered: (action, {required pressed}) =>
            fired.add((action, pressed)),
      );
      addTearDown(controller.dispose);

      await _press(tester, LogicalKeyboardKey.f1, hold: true);
      // A key repeat while held must not re-fire the action.
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f1);
      await _release(tester, LogicalKeyboardKey.f1);

      expect(fired, [
        (KeybindAction.pushToTalk, true),
        (KeybindAction.pushToTalk, false),
      ]);
    });

    testWidgets('a release with the modifier already let go still ends it', (
      tester,
    ) async {
      final fired = <(KeybindAction, bool)>[];
      final controller = await _controllerWith(
        {
          KeybindAction.pushToTalk: Keybind(
            keyId: LogicalKeyboardKey.keyV.keyId,
            modifiers: const {KeybindModifier.shift},
          ),
        },
        onTriggered: (action, {required pressed}) =>
            fired.add((action, pressed)),
      );
      addTearDown(controller.dispose);

      await _press(tester, LogicalKeyboardKey.shiftLeft, hold: true);
      await _press(tester, LogicalKeyboardKey.keyV, hold: true);
      // Shift goes first, which no longer matches the chord that opened it.
      await _release(tester, LogicalKeyboardKey.shiftLeft);
      await _release(tester, LogicalKeyboardKey.keyV);

      expect(fired.last, (KeybindAction.pushToTalk, false));
    });

    testWidgets('an unbound key is left to whatever had focus', (tester) async {
      var fired = 0;
      final controller = await _controllerWith(
        {KeybindAction.toggleMute: Keybind(keyId: LogicalKeyboardKey.f2.keyId)},
        onTriggered: (_, {required pressed}) => fired++,
      );
      addTearDown(controller.dispose);

      expect(
        controller.handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyQ,
            logicalKey: LogicalKeyboardKey.keyQ,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      expect(
        controller.handleKeyEvent(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyQ,
            logicalKey: LogicalKeyboardKey.keyQ,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      expect(fired, 0);
    });

    testWidgets('one chord runs one action', (tester) async {
      final repository = _MemoryKeybinds();
      final controller = KeybindController(
        repository: repository,
        onTriggered: (_, {required pressed}) {},
      );
      addTearDown(controller.dispose);
      await controller.load();
      _install(controller);

      controller.record(KeybindAction.toggleMute);
      await _press(tester, LogicalKeyboardKey.f3);
      controller.record(KeybindAction.toggleDeafen);
      await _press(tester, LogicalKeyboardKey.f3);

      // The second assignment takes the chord off the first, rather than
      // leaving which one fires up to map order.
      expect(controller.bindingFor(KeybindAction.toggleMute), isNull);
      expect(controller.bindingFor(KeybindAction.toggleDeafen), isNotNull);
    });

    test('clearing removes the binding and saves', () async {
      final repository = _MemoryKeybinds()
        ..stored = {
          KeybindAction.toggleMute: Keybind(
            keyId: LogicalKeyboardKey.f4.keyId,
          ),
        };
      final controller = KeybindController(
        repository: repository,
        onTriggered: (_, {required pressed}) {},
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.clear(KeybindAction.toggleMute);
      // Clearing what is not bound writes nothing.
      await controller.clear(KeybindAction.toggleDeafen);

      expect(controller.bindings, isEmpty);
      expect(repository.saved.single, isEmpty);
    });

    testWidgets('recording can be called off', (tester) async {
      final controller = await _controllerWith(const {});
      addTearDown(controller.dispose);

      controller
        ..record(KeybindAction.toggleCamera)
        ..cancelRecording()
        // Cancelling twice is not an event.
        ..cancelRecording();

      expect(controller.recording, isNull);
      await _press(tester, LogicalKeyboardKey.f5);
      expect(controller.bindings, isEmpty);
    });

    test('an unnamed key still reads as something', () {
      expect(Keybind(keyId: 0x1000000f00).label, 'Key 68719480576');
    });
  });

  group('the voice surface keybind', () {
    test('flips the open channel and answers when there is none', () {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);

      // Nothing open: nothing to flip.
      expect(controller.toggleVoiceChannelChat(), isFalse);

      controller.selectChannel('channel-1');
      expect(
        controller.voiceSurfaceOf('channel-1'),
        VoiceChannelSurface.room,
      );
      expect(controller.toggleVoiceChannelChat(), isTrue);
      expect(
        controller.voiceSurfaceOf('channel-1'),
        VoiceChannelSurface.chat,
      );
      expect(controller.toggleVoiceChannelChat(), isTrue);
      expect(
        controller.voiceSurfaceOf('channel-1'),
        VoiceChannelSurface.room,
      );
    });
  });

  group('the settings page', () {
    testWidgets('a chord is recorded and cleared from the list', (
      tester,
    ) async {
      final controller = await _controllerWith(const {});
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeybindSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Said out loud, because a binding that looked global and was not would
      // read as broken behind another window.
      expect(find.textContaining('while Flucord has focus'), findsOneWidget);
      expect(find.text('Not bound'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('keybind-record-TOGGLE_MUTE')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Press any key…'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('keybind-clear-TOGGLE_MUTE')));
      await tester.pumpAndSettle();
      expect(find.text('F6'), findsNothing);
    });

    testWidgets('recording can be called off from the same button', (
      tester,
    ) async {
      final controller = await _controllerWith(const {});
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeybindSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('keybind-record-PUSH_TO_TALK'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(controller.recording, isNull);
      // Held rather than toggled is stated on the row that behaves that way.
      expect(find.text('Held, not toggled'), findsNWidgets(2));
    });
  });

  group('keys from outside the window', () {
    test('a virtual key becomes the logical key Flutter would report', () {
      expect(virtualKeyToLogicalKey(0x41), LogicalKeyboardKey.keyA);
      expect(virtualKeyToLogicalKey(0x5a), LogicalKeyboardKey.keyZ);
      expect(virtualKeyToLogicalKey(0x30), LogicalKeyboardKey.digit0);
      expect(virtualKeyToLogicalKey(0x70), LogicalKeyboardKey.f1);
      expect(virtualKeyToLogicalKey(0x87), LogicalKeyboardKey.f24);
      expect(virtualKeyToLogicalKey(0x20), LogicalKeyboardKey.space);
      expect(virtualKeyToLogicalKey(0xa2), LogicalKeyboardKey.controlLeft);
      // A key nobody can bind is dropped rather than mapped to something
      // that would then match by accident.
      expect(virtualKeyToLogicalKey(0x5f), isNull);
    });

    testWidgets('a global key runs the action without swallowing it', (
      tester,
    ) async {
      final hook = _FakeHook();
      final fired = <(KeybindAction, bool)>[];
      final controller = KeybindController(
        repository: _MemoryKeybinds()
          ..stored = {
            KeybindAction.pushToTalk: Keybind(
              keyId: LogicalKeyboardKey.f9.keyId,
            ),
          },
        onTriggered: (action, {required pressed}) =>
            fired.add((action, pressed)),
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(hook.starts, 1);
      expect(controller.isGlobal, isTrue);
      expect(controller.supportsGlobal, isTrue);

      hook.send(LogicalKeyboardKey.f9, isDown: true);
      hook.send(LogicalKeyboardKey.f9, isDown: false);
      await tester.pump();

      expect(fired, [
        (KeybindAction.pushToTalk, true),
        (KeybindAction.pushToTalk, false),
      ]);
    });

    testWidgets('the modifiers the system reported are the ones matched', (
      tester,
    ) async {
      final hook = _FakeHook();
      final fired = <KeybindAction>[];
      final controller = KeybindController(
        repository: _MemoryKeybinds()
          ..stored = {
            KeybindAction.toggleMute: Keybind(
              keyId: LogicalKeyboardKey.keyM.keyId,
              modifiers: const {KeybindModifier.control, KeybindModifier.alt},
            ),
          },
        onTriggered: (action, {required pressed}) => fired.add(action),
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();

      // Control alone: not the chord.
      hook.send(LogicalKeyboardKey.keyM, isDown: true, modifiers: 1);
      hook.send(LogicalKeyboardKey.keyM, isDown: false);
      expect(fired, isEmpty);

      // Control and alt, which is what was bound.
      hook.send(LogicalKeyboardKey.keyM, isDown: true, modifiers: 1 | 4);
      await tester.pump();
      expect(fired, [KeybindAction.toggleMute]);
    });

    testWidgets('a chord seen by both the hook and the keyboard fires once', (
      tester,
    ) async {
      final hook = _FakeHook();
      final fired = <KeybindAction>[];
      final controller = KeybindController(
        repository: _MemoryKeybinds()
          ..stored = {
            KeybindAction.toggleMute: Keybind(
              keyId: LogicalKeyboardKey.f10.keyId,
            ),
          },
        onTriggered: (action, {required pressed}) => fired.add(action),
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();
      _install(controller);

      // The system sees it first, then the focused keyboard delivers the same
      // press — which still has to be swallowed so it does not reach the
      // composer, but must not run the action a second time.
      hook.send(LogicalKeyboardKey.f10, isDown: true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
      hook.send(LogicalKeyboardKey.f10, isDown: false);
      await tester.pump();

      expect(fired, [KeybindAction.toggleMute]);
    });

    testWidgets('a key arriving while recording is left to the keyboard', (
      tester,
    ) async {
      final hook = _FakeHook();
      final controller = KeybindController(
        repository: _MemoryKeybinds(),
        onTriggered: (_, {required pressed}) {},
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.record(KeybindAction.toggleMute);
      hook.send(LogicalKeyboardKey.f11, isDown: true);
      await tester.pump();

      // Recording reads the focused keyboard, where somebody setting a
      // binding is actually looking; taking it from the hook as well would
      // record the chord twice.
      expect(controller.bindings, isEmpty);
      expect(controller.recording, KeybindAction.toggleMute);
    });

    test('a hook the system refuses leaves the bindings local', () async {
      final hook = _FakeHook()..accept = false;
      final controller = KeybindController(
        repository: _MemoryKeybinds(),
        onTriggered: (_, {required pressed}) {},
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.supportsGlobal, isTrue);
      expect(controller.isGlobal, isFalse);
    });

    test('a platform with no hook says so rather than pretending', () async {
      const hook = UnavailableGlobalKeyboardHook();
      final controller = KeybindController(
        repository: _MemoryKeybinds(),
        onTriggered: (_, {required pressed}) {},
        hook: hook,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.supportsGlobal, isFalse);
      expect(controller.isGlobal, isFalse);
      expect(await hook.start(), isFalse);
      expect(hook.events, emitsDone);
      await hook.stop();
    });


    test('the real hook installs against the built module and comes back out',
        () async {
      // The module the client ships. Skipped where it has not been built, so
      // a checkout that has only run `flutter test` still passes.
      const path = 'build/windows/x64/runner/Release/flucord_hotkeys.dll';
      if (!Platform.isWindows || !File(path).existsSync()) return;
      final hook = WindowsGlobalKeyboardHook.withLibrary(
        DynamicLibrary.open(path),
      );
      addTearDown(hook.close);

      expect(hook.isSupported, isTrue);
      expect(await hook.start(), isTrue);
      expect(hook.isRunning, isTrue);
      // Asked twice: the second is the same answer, not a second hook.
      expect(await hook.start(), isTrue);

      await hook.stop();
      expect(hook.isRunning, isFalse);
      // And stopping what is already stopped does nothing.
      await hook.stop();
    });

    test('a build without the native module reports no hook', () async {
      final hook = WindowsGlobalKeyboardHook.withLibrary(null);

      // What a stripped build and every non-Windows host actually see.
      expect(hook.isSupported, isFalse);
      expect(await hook.start(), isFalse);
      expect(hook.isRunning, isFalse);
      await hook.stop();
      await hook.close();
    });
  });

  group('the settings window', () {
    testWidgets('the keybind page is reachable, with and without a controller',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = UserSettingsController(() => null);
      addTearDown(settings.dispose);

      // A build with no keybind controller says so rather than drawing an
      // empty list that reads as bindings taken and lost.
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(body: UserSettingsDialog(controller: settings)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-keybinds')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('user-keybinds-unavailable')),
        findsOneWidget,
      );

      final keybinds = await _controllerWith(const {});
      addTearDown(keybinds.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: UserSettingsDialog(
              controller: settings,
              keybindController: keybinds,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-keybinds')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('keybind-section')), findsOneWidget);
    });

    testWidgets('the streamer page is reachable, with and without a controller',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = UserSettingsController(() => null);
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(body: UserSettingsDialog(controller: settings)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-streamer')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('user-streamer-unavailable')),
        findsOneWidget,
      );

      final streamer = StreamerModeController(_NoStreamerSettings());
      addTearDown(streamer.dispose);
      await streamer.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: UserSettingsDialog(
              controller: settings,
              streamerModeController: streamer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-streamer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('streamer-mode-section')), findsOneWidget);
    });
  });
}


Future<KeybindController> _controllerWith(
  Map<KeybindAction, Keybind> stored, {
  KeybindHandler? onTriggered,
}) async {
  final controller = KeybindController(
    repository: _MemoryKeybinds()..stored = stored,
    onTriggered: onTriggered ?? (_, {required pressed}) {},
  );
  await controller.load();
  _install(controller);
  return controller;
}

/// Puts the controller where the app puts it: on the keyboard itself, so a
/// test exercises the same path a keystroke really takes.
void _install(KeybindController controller) {
  HardwareKeyboard.instance.addHandler(controller.handleKeyEvent);
  addTearDown(
    () => HardwareKeyboard.instance.removeHandler(controller.handleKeyEvent),
  );
}

/// Sends a key down through the real keyboard, so the controller sees the same
/// pressed-key set the app would.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool hold = false,
}) async {
  await tester.sendKeyDownEvent(key);
  if (!hold) await tester.sendKeyUpEvent(key);
}

Future<void> _release(WidgetTester tester, LogicalKeyboardKey key) =>
    tester.sendKeyUpEvent(key);

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
}

final class _MemoryKeybinds implements KeybindRepository {
  Map<KeybindAction, Keybind> stored = const {};
  final List<Map<KeybindAction, Keybind>> saved = [];
  int reads = 0;

  @override
  Future<Map<KeybindAction, Keybind>> load() async {
    reads++;
    return Map.of(stored);
  }

  @override
  Future<void> save(Map<KeybindAction, Keybind> bindings) async =>
      saved.add(Map.of(bindings));
}


final class _NoStreamerSettings implements StreamerModeRepository {
  @override
  Future<StreamerModeSettings> load() async => const StreamerModeSettings();

  @override
  Future<void> save(StreamerModeSettings settings) async {}
}


final class _FakeHook implements GlobalKeyboardHook {
  final StreamController<GlobalKeyEvent> _events =
      StreamController.broadcast();
  int starts = 0;
  bool accept = true;
  bool _running = false;

  void send(
    LogicalKeyboardKey key, {
    required bool isDown,
    int modifiers = 0,
  }) => _events.add(
    GlobalKeyEvent(key: key, modifiers: modifiers, isDown: isDown),
  );

  @override
  bool get isSupported => true;

  @override
  bool get isRunning => _running;

  @override
  Stream<GlobalKeyEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    starts++;
    _running = accept;
    return accept;
  }

  @override
  Future<void> stop() async => _running = false;
}
