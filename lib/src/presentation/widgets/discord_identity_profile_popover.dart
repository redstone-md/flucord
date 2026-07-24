import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/flucord_theme.dart';

final class DiscordIdentityProfileDetail {
  const DiscordIdentityProfileDetail({
    required this.label,
    required this.value,
    this.indicatorColor,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final Color? indicatorColor;
  final int maxLines;
}

class DiscordIdentityProfilePopover extends StatelessWidget {
  const DiscordIdentityProfilePopover({
    required this.semanticsLabel,
    required this.displayName,
    required this.statusLabel,
    required this.userId,
    required this.bannerColor,
    required this.avatar,
    required this.onMessage,
    this.secondaryLabel,
    this.details = const [],
    this.canMessage = true,
    this.copyButtonKey,
    this.messageButtonKey,
    super.key,
  });

  final String semanticsLabel;
  final String displayName;
  final String? secondaryLabel;
  final String statusLabel;
  final String userId;
  final Color bannerColor;
  final Widget avatar;
  final List<DiscordIdentityProfileDetail> details;
  final bool canMessage;
  final VoidCallback onMessage;
  final Key? copyButtonKey;
  final Key? messageButtonKey;

  @override
  Widget build(BuildContext context) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: semanticsLabel,
    child: Material(
      color: context.surfaces.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: context.surfaces.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height * 0.8).clamp(
            0.0,
            MediaQuery.sizeOf(context).height - 16,
          ),
        ),
        child: SingleChildScrollView(
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 16).clamp(0.0, 300.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(height: 68, color: bannerColor),
                    Positioned(
                      left: 16,
                      top: 38,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.surfaces.raised,
                            width: 5,
                          ),
                        ),
                        child: SizedBox.square(dimension: 64, child: avatar),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (secondaryLabel case final label?) ...[
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: context.surfaces.muted,
                          fontSize: 12,
                        ),
                      ),
                      for (final detail in details) ...[
                        const SizedBox(height: 14),
                        _ProfileLabel(label: detail.label),
                        const SizedBox(height: 6),
                        _ProfileDetailChip(detail: detail),
                      ],
                      const SizedBox(height: 14),
                      const _ProfileLabel(label: 'USER ID'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              userId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.surfaces.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          _CopyIdentityButton(
                            userId: userId,
                            buttonKey: copyButtonKey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: messageButtonKey,
                        onPressed: canMessage ? onMessage : null,
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Message'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProfileDetailChip extends StatelessWidget {
  const _ProfileDetailChip({required this.detail});

  final DiscordIdentityProfileDetail detail;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail.indicatorColor case final color?) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              detail.value,
              maxLines: detail.maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CopyIdentityButton extends StatefulWidget {
  const _CopyIdentityButton({required this.userId, this.buttonKey});

  final String userId;
  final Key? buttonKey;

  @override
  State<_CopyIdentityButton> createState() => _CopyIdentityButtonState();
}

class _CopyIdentityButtonState extends State<_CopyIdentityButton> {
  bool _copied = false;

  @override
  void didUpdateWidget(covariant _CopyIdentityButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _copied = false;
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: widget.buttonKey,
    onPressed: _copy,
    tooltip: _copied ? 'User ID copied' : 'Copy user ID',
    visualDensity: VisualDensity.compact,
    icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16),
  );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.userId));
    if (mounted) setState(() => _copied = true);
  }
}

class _ProfileLabel extends StatelessWidget {
  const _ProfileLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.surfaces.muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    ),
  );
}
