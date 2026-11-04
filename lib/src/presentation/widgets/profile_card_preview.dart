part of 'profile_card.dart';

/// The settings preview's lower half: a divider, then "About me" and
/// "Member since", each under a caption heading.
class _AboutSections extends StatelessWidget {
  const _AboutSections({required this.data});

  final ProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final since = data.memberSince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: context.surfaces.border),
        if (data.bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AboutSection(
            key: const ValueKey('profile-card-bio'),
            heading: 'About me',
            value: data.bio,
          ),
        ],
        if (since != null) ...[
          const SizedBox(height: 12),
          _AboutSection(
            key: const ValueKey('profile-card-member-since'),
            heading: 'Member since',
            value: MaterialLocalizations.of(
              context,
            ).formatShortDate(since.toLocal()),
          ),
        ],
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.heading, required this.value, super.key});

  final String heading;
  final String value;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: FlucordTextRole.caption.style.copyWith(
            color: surfaces.captionText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: FlucordTextRole.label.style.copyWith(color: surfaces.bodyText),
        ),
      ],
    );
  }
}
