/// The sizes of a sidebar's rows. The channel list and the account sidebar
/// both read them, so their DM rows match.
abstract final class SidebarRowMetrics {
  static const headerHeight = 48.0;

  /// A row that shows a person, such as a direct message: room for the
  /// avatar and an activity line under the name.
  static const personRowHeight = 40.0;
  static const personAvatarSize = 28.0;

  /// The space between rows, so two filled rows never touch.
  static const rowGap = 2.0;

  /// How far the list sits in from the sidebar's edges.
  static const listInset = 8.0;

  /// A row's padding on either side of its content.
  static const rowPadding = 8.0;
  static const iconSize = 16.0;
  static const iconGap = 8.0;
}
