part of 'chat_models.dart';

final class ChannelCategory {
  const ChannelCategory({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.position,
  });

  final String id;
  final String spaceId;
  final String name;
  final int position;
}
