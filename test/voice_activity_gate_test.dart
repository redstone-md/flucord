import 'package:flucord/src/application/voice_activity_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fan that is always there becomes the floor and stops opening', () {
    final gate = VoiceActivityGate();

    // Before the floor is learned, a -45 dBFS fan is louder than the assumed
    // quiet room and opens the gate; once it is the quietest thing heard for
    // the whole window, it is the floor, and the threshold sits above it.
    var lastOpen = true;
    for (var i = 0; i < gate.floorWindow + gate.hangoverFrames + 1; i++) {
      lastOpen = gate.accept(-45);
    }
    expect(lastOpen, isFalse);
    expect(gate.threshold, -35);

    expect(gate.accept(-25), isTrue, reason: 'speech over the fan');
  });

  test('the pauses inside speech hold the floor, not the peaks', () {
    final gate = VoiceActivityGate();
    // Ten seconds of talking: -30 dBFS syllables with -55 dBFS gaps between
    // them. A floor that followed the peaks would close the gate mid-word.
    var open = true;
    for (var i = 0; i < 500; i++) {
      open = gate.accept(i % 4 == 3 ? -55 : -30) && open;
    }
    expect(open, isTrue);
    expect(gate.threshold, -45);
  });

  test('digital silence does not make the gate hair-trigger', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < gate.floorWindow; i++) {
      expect(gate.accept(double.negativeInfinity), isFalse);
    }
    expect(gate.threshold, gate.minThreshold);
  });

  test('the gate closes only after the hangover', () {
    final gate = VoiceActivityGate();
    expect(gate.accept(-30), isTrue);
    for (var i = 0; i < gate.hangoverFrames; i++) {
      expect(gate.accept(-70), isTrue, reason: 'frame $i is the tail');
    }
    expect(gate.accept(-70), isFalse);
  });

  test('a manual threshold overrides the learned floor', () {
    final gate = VoiceActivityGate();
    // A fan that is always there: without a manual threshold it becomes
    // the floor and the gate closes on speech that is quieter than the
    // fan plus the margin.
    var open = false;
    for (var i = 0; i < gate.floorWindow + gate.hangoverFrames + 1; i++) {
      open = gate.accept(-45);
    }
    expect(open, isFalse);

    // A threshold set by hand sits where the room really is, whatever the
    // fan has taught the window.
    gate.setManualThreshold(-50);
    expect(gate.threshold, -50);
    expect(gate.isAutomatic, isFalse);
    expect(gate.accept(-48), isTrue, reason: 'above the manual threshold');

    // The floor keeps being learned while the manual threshold is in
    // force, so returning to the automatic gate starts from an honest
    // floor rather than a window that stopped hearing.
    for (var i = 0; i < gate.floorWindow; i++) {
      gate.accept(-40);
    }
    expect(gate.floor, -40);
    gate.setManualThreshold(null);
    expect(gate.isAutomatic, isTrue);
    expect(gate.threshold, -30);
  });

  test('a manual threshold is clamped to the range the gate can hold', () {
    final gate = VoiceActivityGate();
    gate.setManualThreshold(-200);
    expect(gate.threshold, gate.minThreshold);
    gate.setManualThreshold(0);
    expect(gate.threshold, gate.maxThreshold);
  });

  test('the hangover still applies under a manual threshold', () {
    final gate = VoiceActivityGate();
    gate.setManualThreshold(-50);
    expect(gate.accept(-40), isTrue);
    for (var i = 0; i < gate.hangoverFrames; i++) {
      expect(gate.accept(-70), isTrue, reason: 'frame $i is the tail');
    }
    expect(gate.accept(-70), isFalse);
  });
}
