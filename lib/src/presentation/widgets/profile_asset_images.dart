import 'package:flutter/widgets.dart';

/// Where the pictures of profile frames and effects come from below it.
///
/// The app keeps them on disk, so a frame met before draws at once after a
/// restart. Without a scope, as in a widget test, they come straight from
/// the network.
class ProfileAssetImages extends InheritedWidget {
  const ProfileAssetImages({
    required this.image,
    required super.child,
    super.key,
  });

  /// The picture at a URL.
  final ImageProvider Function(String url) image;

  /// The picture source for [context].
  static ImageProvider Function(String url) of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileAssetImages>()?.image ??
      NetworkImage.new;

  @override
  bool updateShouldNotify(ProfileAssetImages oldWidget) =>
      image != oldWidget.image;
}
