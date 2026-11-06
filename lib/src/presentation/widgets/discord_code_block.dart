import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../theme/flucord_theme.dart';

/// Draws a fenced code block. A block tagged with a language highlight.js
/// knows is highlighted in the theme's syntax colours, as Discord does; any
/// other block is plain. The markdown body draws the frame around it.
final class DiscordCodeBlockBuilder extends MarkdownElementBuilder {
  DiscordCodeBlockBuilder({required this.style, required this.padding});

  final TextStyle? style;
  final EdgeInsets padding;

  static final _highlight = Highlight()..registerLanguages(builtinLanguages);

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // The parser ends the code with the line break before the closing fence.
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    return _CodeBlockView(
      text: _span(context, code, _languageOf(element)),
      padding: padding,
    );
  }

  /// The tag after the opening fence, which the parser puts on the inner
  /// `code` element as `language-<tag>`.
  static String? _languageOf(md.Element pre) {
    final inner = pre.children?.whereType<md.Element>().firstOrNull;
    return inner?.attributes['class']?.replaceFirst('language-', '');
  }

  TextSpan _span(BuildContext context, String code, String? language) {
    if (language == null || _highlight.getLanguage(language) == null) {
      return TextSpan(text: code, style: style);
    }
    final renderer = TextSpanRenderer(style, _scopeStyles(context.syntax));
    _highlight.highlight(code: code, language: language).render(renderer);
    return renderer.span ?? TextSpan(text: code, style: style);
  }

  static Map<String, TextStyle> _scopeStyles(FlucordSyntaxTheme syntax) => {
    for (final MapEntry(key: scope, value: role) in _scopeRoles.entries)
      scope: switch (role) {
        _Role.keyword => TextStyle(color: syntax.keyword),
        _Role.title => TextStyle(color: syntax.title),
        _Role.string => TextStyle(color: syntax.string),
        _Role.number => TextStyle(color: syntax.number),
        _Role.comment => TextStyle(
          color: syntax.comment,
          fontStyle: FontStyle.italic,
        ),
      },
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.w500),
  };

  /// Which colour each highlight.js scope takes. A scope not named here
  /// draws in the code's own colour.
  static const _scopeRoles = {
    'keyword': _Role.keyword,
    'doctag': _Role.keyword,
    'selector-tag': _Role.keyword,
    'variable.language_': _Role.keyword,
    'deletion': _Role.keyword,
    'title': _Role.title,
    'title.function_': _Role.title,
    'title.class_': _Role.title,
    'title.class_.inherited__': _Role.title,
    'section': _Role.title,
    'name': _Role.title,
    'selector-id': _Role.title,
    'selector-class': _Role.title,
    'string': _Role.string,
    'regexp': _Role.string,
    'symbol': _Role.string,
    'attribute': _Role.string,
    'addition': _Role.string,
    'number': _Role.number,
    'literal': _Role.number,
    'built_in': _Role.number,
    'type': _Role.number,
    'attr': _Role.number,
    'variable': _Role.number,
    'template-variable': _Role.number,
    'meta': _Role.number,
    'bullet': _Role.number,
    'link': _Role.number,
    'comment': _Role.comment,
    'quote': _Role.comment,
  };
}

enum _Role { keyword, title, string, number, comment }

/// The code, scrolled sideways when a line is wider than the block, as the
/// markdown body draws a plain one.
class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({required this.text, required this.padding});

  final TextSpan text;
  final EdgeInsets padding;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Text.rich(widget.text),
    ),
  );
}
