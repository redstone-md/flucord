import 'dart:async';
import 'dart:io';

import 'package:flucord/src/application/stream_quality_controller.dart';
import 'package:flucord/src/data/file_stream_quality_repository.dart';
import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/presentation/widgets/stream_quality_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamQualitySettings', () {
    test(
      'defaults are Discord web-client policy: 2.5 Mbit share, 1.2 camera',
      () {
        const settings = StreamQualitySettings();

        expect(settings.shareBitrate, 2500000);
        expect(settings.cameraBitrate, 1200000);
      },
    );

    test('round trips through json', () {
      const settings = StreamQualitySettings(
        shareBitrate: 6000000,
        cameraBitrate: 800000,
      );

      expect(StreamQualitySettings.fromJson(settings.toJson()), settings);
    });

    test('reads stored settings, falling back per field', () {
      // A file written by a newer build, or edited by hand, must not stop the
      // client: an unreadable bitrate simply keeps its default.
      expect(
        StreamQualitySettings.fromJson({
          'share_bitrate': 8000000,
          'camera_bitrate': 'as much as possible',
        }),
        const StreamQualitySettings(shareBitrate: 8000000),
      );
      expect(
        StreamQualitySettings.fromJson({'share_bitrate': 0}),
        const StreamQualitySettings(),
      );
      expect(
        StreamQualitySettings.fromJson('nope'),
        const StreamQualitySettings(),
      );
    });
  });

  group('FileStreamQualityRepository', () {
    test('a missing file answers the defaults', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-quality',
      );
      addTearDown(() => directory.delete(recursive: true));

      final repository = FileStreamQualityRepository(
        directory: () async => directory,
      );

      expect(await repository.load(), const StreamQualitySettings());
    });

    test('saves and loads back', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-quality',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileStreamQualityRepository(
        directory: () async => directory,
      );

      await repository.save(
        const StreamQualitySettings(
          shareBitrate: 4000000,
          cameraBitrate: 2000000,
        ),
      );

      expect(
        await repository.load(),
        const StreamQualitySettings(
          shareBitrate: 4000000,
          cameraBitrate: 2000000,
        ),
      );
    });

    test('an unreadable file answers the defaults', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-quality',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${FileStreamQualityRepository.fileName}',
      );
      await file.writeAsString('{not json');

      final repository = FileStreamQualityRepository(
        directory: () async => directory,
      );

      expect(await repository.load(), const StreamQualitySettings());
    });
  });

  group('StreamQualityController', () {
    test('loaded settings are what the next capture runs at', () async {
      final repository = _StoredRepository(
        const StreamQualitySettings(
          shareBitrate: 5000000,
          cameraBitrate: 640000,
        ),
      );
      final encoder = _FakeEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final controller = StreamQualityController(repository, capture: hub);

      await controller.load();

      expect(controller.shareBitrate, 5000000);
      expect((await hub.startShare()).bitrate, 5000000);
      await hub.stop();
      expect((await hub.startCamera()).bitrate, 640000);
    });

    test('a change applies to the next start and is kept', () async {
      final repository = _StoredRepository();
      final encoder = _FakeEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final controller = StreamQualityController(repository, capture: hub);
      await controller.load();

      await controller.setShareBitrate(8000000);

      expect((await hub.startShare()).bitrate, 8000000);
      expect(repository.saved?.shareBitrate, 8000000);
      // The camera side is untouched by a share change.
      expect(repository.saved?.cameraBitrate, 1200000);
    });

    test('setting the value it already has saves nothing', () async {
      final repository = _StoredRepository();
      final controller = StreamQualityController(
        repository,
        capture: VideoCaptureHub(encoder: _FakeEncoder()),
      );
      await controller.load();

      await controller.setCameraBitrate(1200000);

      expect(repository.saved, isNull);
    });

    test('a save that fails still applies, and says it was not kept', () async {
      final repository = _RefusingSaveRepository();
      final encoder = _FakeEncoder();
      final hub = VideoCaptureHub(encoder: encoder);
      final controller = StreamQualityController(repository, capture: hub);
      await controller.load();

      await controller.setShareBitrate(4000000);

      // The change is applied either way: what is lost is the next restart,
      // not this session.
      expect(controller.shareBitrate, 4000000);
      expect((await hub.startShare()).bitrate, 4000000);
      expect(controller.writeError, isNotNull);

      repository.refuse = false;
      await controller.setShareBitrate(6000000);
      expect(controller.writeError, isNull);
    });

    test('a bitrate that is not a positive number is refused', () async {
      final repository = _StoredRepository();
      final controller = StreamQualityController(
        repository,
        capture: VideoCaptureHub(encoder: _FakeEncoder()),
      );
      await controller.load();

      await controller.setShareBitrate(0);

      expect(controller.shareBitrate, 2500000);
      expect(repository.saved, isNull);
    });
  });

  group('StreamQualitySection', () {
    testWidgets('shows both bitrates and a change reaches the controller', (
      tester,
    ) async {
      final controller = StreamQualityController(
        _StoredRepository(),
        capture: VideoCaptureHub(encoder: _FakeEncoder()),
      );
      await controller.load();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(body: StreamQualitySection(controller: controller)),
        ),
      );

      expect(
        find.byKey(const ValueKey('stream-quality-section')),
        findsOneWidget,
      );
      expect(find.text('2.5 Mbit'), findsOneWidget);
      expect(find.text('1.2 Mbit'), findsOneWidget);

      // Tapping the middle of the share slider commits on release.
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('stream-quality-share')),
      );
      final middle = (slider.min + (slider.max - slider.min) / 2).round();
      await tester.tap(find.byKey(const ValueKey('stream-quality-share')));
      await tester.pumpAndSettle();

      expect(controller.shareBitrate, middle);
    });
  });
}

final class _StoredRepository implements StreamQualityRepository {
  _StoredRepository([this._settings]);

  StreamQualitySettings? _settings;
  StreamQualitySettings? saved;

  @override
  Future<StreamQualitySettings> load() async =>
      _settings ?? const StreamQualitySettings();

  @override
  Future<void> save(StreamQualitySettings settings) async {
    saved = settings;
    _settings = settings;
  }
}

final class _RefusingSaveRepository implements StreamQualityRepository {
  bool refuse = true;

  @override
  Future<StreamQualitySettings> load() async =>
      const StreamQualitySettings();

  @override
  Future<void> save(StreamQualitySettings settings) async {
    if (refuse) throw const FileSystemException('disk full');
  }
}

final class _FakeEncoder implements VideoEncoderService {
  final StreamController<EncodedVideoFrame> _frames =
      StreamController.broadcast();

  @override
  bool get isSupported => true;

  @override
  int get displayCount => 1;

  @override
  List<String> get cameraNames => const ['Camera'];

  @override
  Stream<EncodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start(VideoEncoderSettings settings) async {}

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async {}
}
