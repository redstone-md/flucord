import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/soundboard_controller.dart';
import '../../domain/soundboard.dart';
import '../../theme/flucord_theme.dart';

/// The soundboard button a voice room carries, and the sheet behind it.
class SoundboardButton extends StatelessWidget {
  const SoundboardButton({
    required this.controller,
    required this.channelId,
    super.key,
  });

  final SoundboardController controller;

  /// The voice channel a sound would play into.
  final String channelId;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported || controller.guildId == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const ValueKey('soundboard-open'),
      tooltip: 'Soundboard',
      onPressed: () => unawaited(
        SoundboardSheet.show(
          context,
          controller: controller,
          channelId: channelId,
        ),
      ),
      icon: const Icon(Icons.music_note_outlined),
    );
  }
}

/// The grid of sounds this account may play here.
class SoundboardSheet extends StatelessWidget {
  const SoundboardSheet({
    required this.controller,
    required this.channelId,
    super.key,
  });

  final SoundboardController controller;
  final String channelId;

  static Future<void> show(
    BuildContext context, {
    required SoundboardController controller,
    required String channelId,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.surfaces.canvas,
    builder: (_) =>
        SoundboardSheet(controller: controller, channelId: channelId),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Soundboard',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (controller.isSending)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _body(context),
          ],
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (controller.isLoading && controller.sounds.isEmpty) {
      return const Padding(
        key: ValueKey('soundboard-loading'),
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (controller.sounds.isEmpty) {
      return Column(
        key: const ValueKey('soundboard-empty'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.error == null
                ? 'This server has no sounds yet.'
                : 'Discord did not return the soundboard.',
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('soundboard-retry'),
            onPressed: () => unawaited(controller.load()),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'That sound could not be played.',
              key: const ValueKey('soundboard-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sound in controller.sounds)
                  _SoundTile(
                    sound: sound,
                    onPressed: () =>
                        unawaited(controller.play(channelId, sound)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({required this.sound, required this.onPressed});

  final SoundboardSound sound;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = sound.name.isEmpty ? 'Sound' : sound.name;
    return Tooltip(
      message: sound.isAvailable
          ? label
          : '$label is unavailable while the server is below the boost level '
                'that unlocked it.',
      child: Material(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('soundboard-sound-${sound.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: sound.isAvailable ? onPressed : null,
          child: Opacity(
            opacity: sound.isAvailable ? 1 : 0.45,
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sound.emojiName ?? '🔊',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
