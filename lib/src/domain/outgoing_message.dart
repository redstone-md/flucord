part of 'chat_models.dart';

/// Hears how much of an upload has gone out, from 0 to 1.
typedef UploadProgressListener = void Function(double fraction);

/// Where a message this client sent stands while Discord does not have it.
sealed class OutgoingDelivery {
  const OutgoingDelivery();
}

/// The send is on its way. [uploadProgress] says how much of its files has
/// gone out, and is null until the upload reports.
final class OutgoingSending extends OutgoingDelivery {
  const OutgoingSending({this.uploadProgress});

  final double? uploadProgress;
}

/// The send failed. The message waits for the reader to retry or delete it.
final class OutgoingFailed extends OutgoingDelivery {
  const OutgoingFailed(this.error);

  final Object error;
}

/// A message this client sent, shown in the timeline before Discord has it.
///
/// Its nonce is a snowflake of the moment it was written, and it is the id the
/// timeline knows it by, so it sorts among the real messages. Discord echoes
/// the nonce on the message it creates, which is how the real message takes
/// this one's place.
final class OutgoingMessage {
  const OutgoingMessage({
    required this.message,
    required this.kind,
    this.delivery = const OutgoingSending(),
  });

  /// The message as the timeline draws it. Its id is the nonce.
  final ChatMessage message;
  final OutgoingKind kind;
  final OutgoingDelivery delivery;

  String get nonce => message.id;
  String get channelId => message.channelId;
  List<PendingAttachment> get attachments => kind.attachments;
  bool get hasFailed => delivery is OutgoingFailed;

  OutgoingMessage withDelivery(OutgoingDelivery delivery) =>
      OutgoingMessage(message: message, kind: kind, delivery: delivery);
}

/// What an outgoing message sends besides its text.
sealed class OutgoingKind {
  const OutgoingKind();

  /// The files the send uploads.
  List<PendingAttachment> get attachments;
}

/// A text message, with any files and the message it answers.
final class OutgoingText extends OutgoingKind {
  OutgoingText({
    required this.replyToMessageId,
    List<PendingAttachment> attachments = const [],
  }) : attachments = List.unmodifiable(attachments);

  /// The message this one answers. Kept apart from [ChatMessage.reply], which
  /// is null when the answered message is not held.
  final String? replyToMessageId;

  @override
  final List<PendingAttachment> attachments;
}

/// A voice message: [recording] is sent as its only file.
final class OutgoingVoice extends OutgoingKind {
  OutgoingVoice(this.recording) : attachments = [recording.attachment];

  final PendingVoiceMessage recording;

  @override
  final List<PendingAttachment> attachments;
}
