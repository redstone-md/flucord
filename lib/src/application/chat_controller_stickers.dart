part of 'chat_controller.dart';

extension ChatControllerStickers on ChatController {
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
        channel?.kind != ChannelKind.text ||
        ids.isEmpty ||
        ids.length > 3 ||
        ids.any(
          (id) => !workspace
              .stickersFor(channel!.spaceId)
              .any((sticker) => sticker.id == id),
        ) ||
        _isSending) {
      return false;
    }
    _isSending = true;
    _notify();
    try {
      final message = await repository.sendStickers(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        stickerIds: ids,
      );
      _workspace = _workspace
          ?.upsertMessage(message)
          .clearChannelUnreadBoundary(channelId);
      _persistChannelActivity(channelId);
      _error = null;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }
}
