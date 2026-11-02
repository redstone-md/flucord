import 'package:flutter/material.dart';

import 'package:flucord/src/application/accessibility_controller.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/presentation/widgets/accessibility_dials.dart';

/// A `MaterialApp.builder` that applies [zoom] as the real app does, for a test
/// of one widget. A whole session gets its zoom from `testSession`.
Future<TransitionBuilder> zoomedAppBuilder(double zoom) async {
  final controller = AccessibilityController(
    FixedDials(AccessibilitySettings(zoom: zoom)),
  );
  await controller.load();
  return (_, child) =>
      AccessibilityDials(controller: controller, child: child!);
}

/// The dials a launch finds, so no test reads the machine's real settings file.
final class FixedDials implements AccessibilityRepository {
  const FixedDials(this._settings);

  final AccessibilitySettings _settings;

  @override
  Future<AccessibilitySettings> load() async => _settings;

  @override
  Future<void> save(AccessibilitySettings settings) async {}
}
