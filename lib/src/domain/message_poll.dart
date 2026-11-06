part of 'chat_models.dart';

final class PollAnswer {
  const PollAnswer({
    required this.id,
    required this.text,
    required this.count,
    this.emojiId,
    this.emojiName,
    this.emojiAnimated = false,
    this.votedByCurrentUser = false,
  });

  final int id;
  final String text;
  final int count;
  final String? emojiId;
  final String? emojiName;
  final bool emojiAnimated;
  final bool votedByCurrentUser;

  PollAnswer copyWith({int? count, bool? votedByCurrentUser}) => PollAnswer(
    id: id,
    text: text,
    count: count ?? this.count,
    emojiId: emojiId,
    emojiName: emojiName,
    emojiAnimated: emojiAnimated,
    votedByCurrentUser: votedByCurrentUser ?? this.votedByCurrentUser,
  );
}

final class MessagePoll {
  MessagePoll({
    required this.question,
    required List<PollAnswer> answers,
    required this.allowMultiselect,
    required this.isFinalized,
    this.expiry,
  }) : answers = List.unmodifiable(answers);

  final String question;
  final List<PollAnswer> answers;
  final DateTime? expiry;
  final bool allowMultiselect;
  final bool isFinalized;

  int get totalVotes =>
      answers.fold(0, (total, answer) => total + answer.count);

  /// The answers the account voted for.
  Set<int> get ownVote => {
    for (final answer in answers)
      if (answer.votedByCurrentUser) answer.id,
  };

  /// Whether the poll still takes votes at [now]. An ended poll only shows
  /// its results.
  bool isOpenAt(DateTime now) =>
      !isFinalized && (expiry == null || expiry!.isAfter(now));

  /// The poll once the account's whole vote is [answerIds]. An empty set
  /// takes the vote back. The counts move only for answers that change.
  MessagePoll withOwnVote(Set<int> answerIds) => copyWith(
    answers: [
      for (final answer in answers)
        switch ((answer.votedByCurrentUser, answerIds.contains(answer.id))) {
          (false, true) => answer.copyWith(
            count: answer.count + 1,
            votedByCurrentUser: true,
          ),
          (true, false) => answer.copyWith(
            count: answer.count > 0 ? answer.count - 1 : 0,
            votedByCurrentUser: false,
          ),
          _ => answer,
        },
    ],
  );

  MessagePoll copyWith({
    List<PollAnswer>? answers,
    DateTime? expiry,
    bool? isFinalized,
  }) => MessagePoll(
    question: question,
    answers: answers ?? this.answers,
    expiry: expiry ?? this.expiry,
    allowMultiselect: allowMultiselect,
    isFinalized: isFinalized ?? this.isFinalized,
  );
}

final class PendingPoll {
  static const minAnswers = 2;
  static const maxAnswers = 10;
  static const maxQuestionLength = 300;
  static const maxAnswerLength = 55;
  static const maxDurationHours = 32 * 24;

  PendingPoll({
    required this.question,
    required List<String> answers,
    required this.durationHours,
    this.allowMultiselect = false,
  }) : answers = List.unmodifiable(answers);

  final String question;
  final List<String> answers;
  final int durationHours;
  final bool allowMultiselect;

  PendingPoll normalized() => PendingPoll(
    question: question.trim(),
    answers: answers.map((answer) => answer.trim()).toList(growable: false),
    durationHours: durationHours,
    allowMultiselect: allowMultiselect,
  );

  bool get isValid =>
      question.isNotEmpty &&
      question.length <= maxQuestionLength &&
      answers.length >= minAnswers &&
      answers.length <= maxAnswers &&
      answers.every(
        (answer) => answer.isNotEmpty && answer.length <= maxAnswerLength,
      ) &&
      durationHours >= 1 &&
      durationHours <= maxDurationHours;
}
