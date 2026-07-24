import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports an unbundled SDK through the Windows runner', (
    tester,
  ) async {
    const gateway = NativeDiscordSocialSdkGateway();

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    );
    await expectLater(
      gateway.fetchRelationships(),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
  });
}
