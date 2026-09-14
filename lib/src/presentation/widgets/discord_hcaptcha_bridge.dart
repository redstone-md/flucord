import 'dart:convert';

import '../../domain/discord_remote_auth.dart';

enum DiscordHcaptchaMessageType { ready, solved, error, expired }

final class DiscordHcaptchaMessage {
  const DiscordHcaptchaMessage._(this.type, this.token);

  final DiscordHcaptchaMessageType type;
  final String? token;

  static DiscordHcaptchaMessage? tryParse(Object? value) {
    if (value is! Map) return null;
    final type = switch (value['type']) {
      'ready' => DiscordHcaptchaMessageType.ready,
      'solved' => DiscordHcaptchaMessageType.solved,
      'error' => DiscordHcaptchaMessageType.error,
      'expired' => DiscordHcaptchaMessageType.expired,
      _ => null,
    };
    if (type == null) return null;
    final rawToken = value['token'];
    final token = rawToken is String && rawToken.trim().isNotEmpty
        ? rawToken.trim()
        : null;
    if (type == DiscordHcaptchaMessageType.solved && token == null) return null;
    return DiscordHcaptchaMessage._(type, token);
  }
}

final class DiscordHcaptchaBridge {
  const DiscordHcaptchaBridge._();

  static String documentReplacementScript(
    DiscordRemoteAuthCaptchaChallenge challenge,
  ) {
    final config = <String, Object?>{
      'sitekey': challenge.siteKey,
      'theme': 'dark',
      if (challenge.serveInvisible) 'size': 'invisible',
    };
    final encodedConfig = _javascriptJson(config);
    final encodedRqData = _javascriptJson(challenge.rqData);
    return '''
window.stop();
document.open();
document.write('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><main id="surface"><div id="captcha"></div><div id="status">Loading challenge...</div></main></body></html>');
document.close();
document.documentElement.style.cssText = 'background:#1e1f22;color:#f2f3f5;color-scheme:dark;';
document.body.style.cssText = 'margin:0;min-height:100vh;display:grid;place-items:center;background:#1e1f22;font:14px system-ui,sans-serif;overflow:hidden;';
document.getElementById('surface').style.cssText = 'width:100%;min-height:100vh;display:grid;place-items:center;align-content:center;gap:16px;';
document.getElementById('status').style.cssText = 'color:#b5bac1;';
window.__flucordPost = function(message) {
  window.chrome.webview.postMessage(message);
};
window.__flucordRender = function() {
  const config = $encodedConfig;
  const rqdata = $encodedRqData;
  config.callback = function(token) {
    window.__flucordPost({type:'solved', token:token});
  };
  config['error-callback'] = function() {
    window.__flucordPost({type:'error'});
  };
  config['expired-callback'] = function() {
    window.__flucordPost({type:'expired'});
  };
  document.getElementById('status').remove();
  const widgetId = window.hcaptcha.render('captcha', config);
  if (rqdata !== null && rqdata !== '') {
    window.hcaptcha.setData(widgetId, {rqdata:rqdata});
  }
  if (config.size === 'invisible') {
    window.hcaptcha.execute(widgetId);
  }
  window.__flucordPost({type:'ready'});
};
const sdk = document.createElement('script');
sdk.src = 'https://js.hcaptcha.com/1/api.js?render=explicit&onload=__flucordRender&recaptchacompat=off';
sdk.async = true;
sdk.defer = true;
sdk.onerror = function() { window.__flucordPost({type:'error'}); };
document.head.appendChild(sdk);
''';
  }

  static String _javascriptJson(Object? value) =>
      jsonEncode(value).replaceAll('<', r'\u003c');
}
