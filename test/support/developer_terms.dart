import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Words that mean something to the people who build Flucord, and nothing to
/// the people who use it.
final _developerTerms = RegExp(
  r'\b(transports?|gateway|sdk|oauth|presence|locale|surface|bridge|fallback|'
  r'scopes?|grant|copy-id|snowflake|payload)\b',
  caseSensitive: false,
);

/// Every text on screen that uses a developer term.
List<String> developerTermsOnScreen(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data ?? text.textSpan?.toPlainText() case final content?)
      if (_developerTerms.hasMatch(content)) content,
];
