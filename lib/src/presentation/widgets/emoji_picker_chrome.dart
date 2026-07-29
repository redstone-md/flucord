part of 'emoji_picker.dart';

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.title, required this.spaceName});

  final String title;
  final String spaceName;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              spaceName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.surfaces.muted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
