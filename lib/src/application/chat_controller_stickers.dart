part of 'chat_controller.dart';

extension ChatControllerStickers on ChatController {
  /// Whether this session's transport can send stickers at all.
  bool get canSendStickers => _repository is StickerRepository;

  Future<bool> sendStickers({
    required String channelId,
    required List<String> stickerIds,
  }) async {
    final workspace = _workspace;
    final repository = _repository is StickerRepository
        ? _repository as StickerRepository
        : null;
    final channel = workspace?.channelOrNull(channelId);
    final ids = stickerIds.toSet().toList(growable: false);
    if (workspace == null ||
        repository == null ||
        channel?.hasMessageTimeline != true ||
        ids.isEmpty ||
        ids.length > 3 ||
        ids.any(
          (id) => !workspace
              .stickersFor(channel!.spaceId)
              .any((sticker) => sticker.id == id),
        )) {
      return false;
    }
    return _sendingIn(channelId, () async {
      final message = await repository.sendStickers(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        stickerIds: ids,
      );
      _applySentMessage(message);
    });
  }
}
