import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/presentation/widgets/discord_hcaptcha_bridge.dart';

void main() {
  test('builds an explicit Discord-hosted hCaptcha challenge', () {
    const challenge = DiscordRemoteAuthCaptchaChallenge(
      siteKey: 'site-key',
      service: 'hcaptcha',
      userAgent: 'Discord test user agent',
      rqData: 'request-data',
      rqToken: 'must-not-enter-the-webview',
    );

    final script = DiscordHcaptchaBridge.documentReplacementScript(challenge);

    expect(
      script,
      contains('https://js.hcaptcha.com/1/api.js?render=explicit'),
    );
    expect(script, contains('window.hcaptcha.render'));
    expect(script, contains('window.hcaptcha.setData'));
    expect(script, contains('recaptchacompat=off'));
    expect(script, contains('"sitekey":"site-key"'));
    expect(script, contains('const rqdata = "request-data"'));
    expect(script, contains("{type:'solved', token:token}"));
    expect(script, isNot(contains('must-not-enter-the-webview')));
  });

  test('accepts only typed bridge messages with a non-empty solved token', () {
    final solved = DiscordHcaptchaMessage.tryParse({
      'type': 'solved',
      'token': ' response-token ',
    });

    expect(solved, isNotNull);
    expect(solved!.type, DiscordHcaptchaMessageType.solved);
    expect(solved.token, 'response-token');
    expect(
      DiscordHcaptchaMessage.tryParse({'type': 'solved', 'token': ''}),
      isNull,
    );
    expect(DiscordHcaptchaMessage.tryParse({'type': 'unknown'}), isNull);
  });
}
