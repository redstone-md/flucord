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
          _AboutSection.text(
            key: const ValueKey('profile-card-bio'),
            heading: 'About me',
            value: data.bio,
          ),
        ],
        if (since != null) ...[
          const SizedBox(height: 12),
          _AboutSection.text(
            key: const ValueKey('profile-card-member-since'),
            heading: 'Member since',
            value: _date(context, since),
          ),
        ],
      ],
    );
  }
}

/// [when] as a short date in the reader's locale: "Jun 12, 2019".
String _date(BuildContext context, DateTime when) =>
    MaterialLocalizations.of(context).formatShortDate(when.toLocal());

/// A caption [heading] over its [child], as the preview and the full
/// profile's card lay out each part.
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.heading, required this.child, super.key});

  /// [value] as a line of body text.
  _AboutSection.text({required String heading, required String value, Key? key})
    : this(heading: heading, child: _AboutText(value), key: key);

  final String heading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        heading,
        style: FlucordTextRole.caption.style.copyWith(
          color: context.surfaces.captionText,
        ),
      ),
      const SizedBox(height: 4),
      child,
    ],
  );
}

class _AboutText extends StatelessWidget {
  const _AboutText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: FlucordTextRole.label.style.copyWith(
      color: context.surfaces.bodyText,
    ),
  );
}
