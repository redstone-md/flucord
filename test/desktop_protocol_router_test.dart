import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/platform/desktop_protocol_router.dart';

void main() {
  test('retains an OAuth callback until the surface attaches', () async {
    final router = DesktopProtocolRouter();
    final surface = _SurfaceStub();

    router.receive(
      'flucord://oauth/discord/callback?code=code-1&state=state-1',
    );
    router.attach(surface);

    expect(surface.handledUris, [
      Uri.parse('flucord://oauth/discord/callback?code=code-1&state=state-1'),
    ]);
  });

  test(
    'retains a channel link until the surface attaches, then opens it',
    () async {
      final router = DesktopProtocolRouter();
      final surface = _SurfaceStub();

      router.receive('flucord://channels/night/night-ops');
      expect(surface.openedLinks, isEmpty);

      router.attach(surface);

      expect(
        surface.openedLinks.single,
        ChannelLink(spaceId: 'night', channelId: 'night-ops'),
      );
      expect(surface.handledUris, isEmpty);
    },
  );

  test('opens a channel link through the attached surface', () async {
    final router = DesktopProtocolRouter();
    final surface = _SurfaceStub();
    router.attach(surface);

    router.receive('flucord://channels/night/night-ops');

    expect(
      surface.openedLinks.single,
      ChannelLink(spaceId: 'night', channelId: 'night-ops'),
    );
    expect(surface.handledUris, isEmpty);
  });

  test('ignores foreign schemes and detaches callbacks', () async {
    final router = DesktopProtocolRouter();
    final surface = _SurfaceStub();
    router.attach(surface);

    router.receive('https://discord.com/oauth2/authorize');
    router.detach();
    router.receive('flucord://oauth/discord/callback?code=late');

    expect(surface.handledUris, isEmpty);
  });
}

final class _SurfaceStub extends ChangeNotifier implements DesktopAppSurface {
  final List<ChannelLink> openedLinks = [];
  final List<Uri> handledUris = [];

  @override
  int? get unreadChannelCount => null;

  @override
  String? get activeChannelId => null;

  @override
  Stream<DesktopMessageNotification> get messageNotifications =>
      const Stream.empty();

  @override
  void openChannelLink(ChannelLink link) => openedLinks.add(link);

  @override
  void handleProtocolUri(Uri uri) => handledUris.add(uri);

  @override
  void setApplicationActive(bool value) {}

  @override
  void setWindowVisible(bool value) {}
}
