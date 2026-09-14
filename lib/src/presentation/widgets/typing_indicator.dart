import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({required this.members, super.key});

  final List<Member> members;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The three dots light up one after another.
  static const _stagger = [0.0, 0.15, 0.3];

  @override
  void initState() {
    super.initState();
    _updatePulse();
  }

  @override
  void didUpdateWidget(covariant TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulse();
  }

  /// Runs only while somebody is typing. A stopped controller also keeps
  /// `pumpAndSettle` working in tests over panes with no typing members.
  void _updatePulse() {
    if (widget.members.isEmpty) {
      _pulse.stop();
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  Animation<double> _dotOpacity(int index) =>
      Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(
          parent: _pulse,
          curve: Interval(_stagger[index], 1.0, curve: Curves.easeInOut),
        ),
      );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.members.map((member) => member.displayName).toList();
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
                      FadeTransition(
                        opacity: _dotOpacity(index),
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: context.surfaces.muted,
                            shape: BoxShape.circle,
                          ),
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
