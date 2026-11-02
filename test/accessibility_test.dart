import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/application/accessibility_controller.dart';
import 'package:flucord/src/data/file_accessibility_repository.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/presentation/widgets/accessibility_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the stored dials', () {
    test('they survive a round trip', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-a11y');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileAccessibilityRepository(
        directory: () async => directory,
      );

      expect((await repository.load()).fontScale, 1.0);
      await repository.save(
        const AccessibilitySettings(
          fontScale: 1.25,
          zoom: 0.9,
          reducedMotion: true,
          spellcheck: false,
        ),
      );
      final read = await repository.load();

      expect(read.fontScale, 1.25);
      expect(read.zoom, 0.9);
      expect(read.reducedMotion, isTrue);
      expect(read.spellcheck, isFalse);
    });

    test('a dial a newer build wrote keeps its default', () async {
      final directory = await Directory.systemTemp.createTemp('flucord-a11y');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}'
        '${FileAccessibilityRepository.fileName}',
      ).writeAsString(
        jsonEncode({'font_scale': 'not a number', 'unknown': true}),
      );

      final read = await FileAccessibilityRepository(
        directory: () async => directory,
      ).load();

      expect(read.fontScale, 1.0);
      expect(read.spellcheck, isTrue);
    });

    test('an unreadable file reads as the defaults', () async {
      expect(
        (await FileAccessibilityRepository(
          directory: () async => throw StateError('no directory'),
        ).load()).fontScale,
        1.0,
      );
    });
  });

  group('the controller', () {
    test('a dial answers immediately and is written once it settles', () async {
      final repository = _MemorySettings();
      final controller = AccessibilityController(repository);
      addTearDown(controller.dispose);
      expect(controller.isLoaded, isFalse);
      await controller.load();
      // A second load does not re-read.
      await controller.load();
      expect(repository.reads, 1);
      expect(controller.isLoaded, isTrue);

      await controller.setFontScale(1.25);
      expect(controller.fontScale, 1.25);
      await controller.setZoom(0.9);
      expect(controller.zoom, 0.9);
      await controller.setReducedMotion(reduced: true);
      expect(controller.reducesMotion, isTrue);
      await controller.setSpellcheck(enabled: false);
      expect(controller.spellchecks, isFalse);

      expect(repository.saved.length, 4);
      final last = repository.saved.last;
      expect(last.fontScale, 1.25);
      expect(last.zoom, 0.9);
      expect(last.reducedMotion, isTrue);
      expect(last.spellcheck, isFalse);
    });

    test('a dial past its range is clamped to the usable one', () async {
      final controller = AccessibilityController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setFontScale(9);
      expect(controller.fontScale, AccessibilitySettings.maxFontScale);
      await controller.setZoom(0.1);
      expect(controller.zoom, AccessibilitySettings.minZoom);
    });

    test(
      'a write that fails leaves the change on screen and the error up',
      () async {
        final repository = _MemorySettings()
          ..saveError = StateError('the disk is gone');
        final controller = AccessibilityController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        await controller.setFontScale(1.5);

        // The interface answered the dial, and the failure is there to read.
        expect(controller.fontScale, 1.5);
        expect(controller.writeError, isStateError);

        repository.saveError = null;
        await controller.setZoom(1.2);
        expect(controller.writeError, isNull);
      },
    );
  });

  group('the settings window', () {
    testWidgets('every dial changes the interface as it is moved', (
      tester,
    ) async {
      final controller = AccessibilityController(_MemorySettings());
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(body: AccessibilitySection(controller: controller)),
        ),
      );

      // The font scale slider, dragged from its rest position.
      await tester.timedDrag(
        find.byKey(const ValueKey('accessibility-font-scale')),
        const Offset(40, 0),
        const Duration(milliseconds: 200),
      );
      expect(controller.fontScale, isNot(1.0));

      // The zoom slider.
      await tester.timedDrag(
        find.byKey(const ValueKey('accessibility-zoom')),
        const Offset(40, 0),
        const Duration(milliseconds: 200),
      );
      expect(controller.zoom, isNot(1.0));

      await tester.tap(
        find.byKey(const ValueKey('accessibility-reduced-motion')),
      );
      await tester.pumpAndSettle();
      expect(controller.reducesMotion, isTrue);

      await tester.tap(find.byKey(const ValueKey('accessibility-spellcheck')));
      await tester.pumpAndSettle();
      expect(controller.spellchecks, isFalse);

      expect(tester.takeException(), isNull);
    });
  });
}

final class _MemorySettings implements AccessibilityRepository {
  AccessibilitySettings stored = const AccessibilitySettings();
  int reads = 0;
  final List<AccessibilitySettings> saved = [];
  Object? saveError;

  @override
  Future<AccessibilitySettings> load() async {
    reads++;
    return stored;
  }

  @override
  Future<void> save(AccessibilitySettings settings) async {
    if (saveError != null) throw saveError!;
    saved.add(settings);
    stored = settings;
  }
}
