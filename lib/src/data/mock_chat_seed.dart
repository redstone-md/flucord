import '../domain/chat_models.dart';

final class MockChatSeed {
  const MockChatSeed._();

  static const spaces = [
    CommunitySpace(
      id: 'forge',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: 'night',
      name: 'Night Shift',
      monogram: 'NS',
      colorValue: 0xff765341,
    ),
    CommunitySpace(
      id: 'studio',
      name: 'Signal Studio',
      monogram: 'SS',
      colorValue: 0xff5f5b76,
    ),
    CommunitySpace(
      id: 'lab',
      name: 'Home Lab',
      monogram: 'HL',
      colorValue: 0xff59636a,
    ),
  ];

  static const categories = [
    ChannelCategory(
      id: 'forge-project',
      spaceId: 'forge',
      name: 'The Forge',
      position: 0,
    ),
  ];
}
