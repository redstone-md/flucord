import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

/// The desktop window as the app sees it, for [testSession]'s `desktop`.
///
/// The app gets focus changes and links through the same seam the platform
/// layer uses. [linkAtLaunch] arrives when the app attaches, before any
/// workspace exists, as a link does that started the app.
final class FakeDesktopWindow implements DesktopIntegration {
  FakeDesktopWindow({this.linkAtLaunch});

  final ChannelLink? linkAtLaunch;
  late DesktopAppSurface _surface;

  void blur() => _surface.setApplicationActive(false);

  void focus() => _surface.setApplicationActive(true);

  @override
  Future<void> initialize() async {}

  @override
  void attach(DesktopAppSurface surface) {
    _surface = surface;
    final link = linkAtLaunch;
    if (link != null) surface.openChannelLink(link);
  }

  @override
  Future<void> dispose() async {}
}
