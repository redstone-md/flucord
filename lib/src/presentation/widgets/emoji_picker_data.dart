part of 'emoji_picker.dart';

final class _UnicodeEmoji {
  const _UnicodeEmoji(this.glyph, this.name, [this.keywords = const []]);

  final String glyph;
  final String name;
  final List<String> keywords;

  bool matches(String query) =>
      query.isEmpty ||
      name.contains(query) ||
      keywords.any((keyword) => keyword.contains(query));
}

const _unicodeEmojis = [
  _UnicodeEmoji('😀', 'grinning', ['smile', 'happy']),
  _UnicodeEmoji('😄', 'smile', ['happy', 'joy']),
  _UnicodeEmoji('😂', 'joy', ['laugh', 'tears']),
  _UnicodeEmoji('🤣', 'rofl', ['laugh']),
  _UnicodeEmoji('😊', 'blush', ['smile']),
  _UnicodeEmoji('😍', 'heart_eyes', ['love']),
  _UnicodeEmoji('😎', 'sunglasses', ['cool']),
  _UnicodeEmoji('🤔', 'thinking', ['hmm']),
  _UnicodeEmoji('🫡', 'saluting', ['respect']),
  _UnicodeEmoji('😅', 'sweat_smile', ['relief']),
  _UnicodeEmoji('😭', 'sob', ['cry']),
  _UnicodeEmoji('😡', 'rage', ['angry']),
  _UnicodeEmoji('👍', 'thumbsup', ['yes', 'approve']),
  _UnicodeEmoji('👎', 'thumbsdown', ['no', 'reject']),
  _UnicodeEmoji('👏', 'clap', ['applause']),
  _UnicodeEmoji('🙏', 'pray', ['thanks', 'please']),
  _UnicodeEmoji('💪', 'muscle', ['strong']),
  _UnicodeEmoji('👀', 'eyes', ['look']),
  _UnicodeEmoji('❤️', 'heart', ['love']),
  _UnicodeEmoji('💯', 'hundred', ['perfect']),
  _UnicodeEmoji('🔥', 'fire', ['hot']),
  _UnicodeEmoji('✨', 'sparkles', ['shine']),
  _UnicodeEmoji('🎉', 'tada', ['party', 'celebrate']),
  _UnicodeEmoji('🚀', 'rocket', ['ship', 'launch']),
  _UnicodeEmoji('✅', 'white_check_mark', ['done', 'success']),
  _UnicodeEmoji('❌', 'x', ['fail', 'no']),
  _UnicodeEmoji('⚠️', 'warning', ['alert']),
  _UnicodeEmoji('💡', 'bulb', ['idea']),
  _UnicodeEmoji('🛠️', 'tools', ['build', 'fix']),
  _UnicodeEmoji('💻', 'computer', ['code', 'desktop']),
  _UnicodeEmoji('🐛', 'bug', ['debug']),
  _UnicodeEmoji('📌', 'pushpin', ['pin']),
  _UnicodeEmoji('📝', 'memo', ['note']),
  _UnicodeEmoji('🔒', 'lock', ['secure']),
  _UnicodeEmoji('🔊', 'loud_sound', ['audio']),
  _UnicodeEmoji('🎧', 'headphones', ['audio', 'music']),
  _UnicodeEmoji('📦', 'package', ['release']),
  _UnicodeEmoji('⚡', 'zap', ['fast', 'power']),
  _UnicodeEmoji('🌙', 'crescent_moon', ['night']),
  _UnicodeEmoji('☕', 'coffee', ['break']),
];
