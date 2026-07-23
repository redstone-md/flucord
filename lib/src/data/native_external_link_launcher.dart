import 'package:url_launcher/url_launcher.dart';

import '../domain/external_link_launcher.dart';

final class NativeExternalLinkLauncher implements ExternalLinkLauncher {
  const NativeExternalLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
