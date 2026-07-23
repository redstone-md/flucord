import 'package:flutter/material.dart';

class RemoteIdentityImage extends StatelessWidget {
  const RemoteIdentityImage({
    required this.url,
    required this.fallback,
    this.imageKey,
    super.key,
  });

  final String? url;
  final Widget fallback;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        if (imageUrl != null)
          Image.network(
            imageUrl,
            key: imageKey,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}
