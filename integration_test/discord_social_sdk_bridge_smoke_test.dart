import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_presence.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports an unbundled SDK through the Windows runner', (
    tester,
  ) async {
    final gateway = NativeDiscordSocialSdkGateway();

    final availability = await gateway.checkAvailability();

    expect(
      availability.status,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    );
    await expectLater(
      gateway.fetchCurrentUserId(),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
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
    await expectLater(
      gateway.updateRelationship(
        userId: '123456789',
        action: DiscordRelationshipAction.acceptRequest,
      ),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.sendFriendRequest('123456789'),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.fetchConversations(),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.fetchMessages(userId: '123456789'),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.sendMessage(userId: '123456789', content: 'smoke'),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.editMessage(
        userId: '123456789',
        messageId: '987654321',
        content: 'edited smoke',
      ),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.deleteMessage(userId: '123456789', messageId: '987654321'),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.setShowingChat(true),
      throwsA(
        isA<DiscordSocialSdkException>().having(
          (error) => error.code,
          'code',
          'sdk_not_bundled',
        ),
      ),
    );
    await expectLater(
      gateway.setOnlineStatus(DiscordOnlineStatus.idle),
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
