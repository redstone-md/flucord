import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({required this.members, super.key});

  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final names = members.map((member) => member.displayName).toList();
    final label = switch (names.length) {
      0 => '',
      1 => '${names.first} is typing...',
      2 => '${names.first} and ${names.last} are typing...',
      _ => 'Several people are typing...',
    };
    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (names.isNotEmpty) ...[
              SizedBox(
                width: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var index = 0; index < 3; index++)
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: context.surfaces.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
