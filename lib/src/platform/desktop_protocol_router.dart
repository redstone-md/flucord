import '../domain/channel_link.dart';

import 'desktop_integration.dart';

/// Routes flucord:// URLs from the OS into the app: channel links navigate,
/// any other URI of the scheme goes to the app's protocol handler. A URL that
/// arrives before the app attaches is retained, one per route.
final class DesktopProtocolRouter {
  DesktopAppSurface? _surface;
  ChannelLink? _pendingChannelLink;
  Uri? _pendingProtocolUri;

  void attach(DesktopAppSurface surface) {
    _surface = surface;
    final pendingProtocolUri = _pendingProtocolUri;
    if (pendingProtocolUri != null) {
      _pendingProtocolUri = null;
      surface.handleProtocolUri(pendingProtocolUri);
    }
    _flushChannelLink();
  }

  void receive(String rawUrl) {
    final channelLink = ChannelLink.tryParse(rawUrl);
    if (channelLink != null) {
      _pendingChannelLink = channelLink;
      _flushChannelLink();
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != ChannelLink.scheme) return;
    final surface = _surface;
    if (surface == null) {
      _pendingProtocolUri = uri;
    } else {
      surface.handleProtocolUri(uri);
    }
  }

  /// Delivers a retained link once the app is there to open it. A link that
  /// arrives after attach goes straight through; the app side holds it from
  /// there until the workspace is loaded.
  void _flushChannelLink() {
    final link = _pendingChannelLink;
    final surface = _surface;
    if (link == null || surface == null) return;
    _pendingChannelLink = null;
    surface.openChannelLink(link);
  }

  void detach() {
    _surface = null;
    _pendingChannelLink = null;
    _pendingProtocolUri = null;
  }
}
