/// One way Discord will let an account prove its age.
///
/// The methods are named by Discord and carried out by third parties — a
/// wallet, a face-estimation vendor, an identity document check. Flucord shows
/// what is on offer and starts the one that was picked; the checking itself
/// happens on the vendor's own surface, never here.
final class AgeVerificationMethod {
  const AgeVerificationMethod({
    required this.method,
    this.vendor = '',
    this.title = '',
    this.description = '',
    this.providedBy = '',
  });

  /// Discord's own name for the method.
  final String method;

  /// The third party that would carry it out.
  final String vendor;

  final String title;
  final String description;

  /// Who Discord says provides it, when it names somebody separately from the
  /// vendor. Empty when it does not.
  final String providedBy;

  /// What to show as the name of this method. Discord localises the title
  /// server-side, so an empty one falls back to its own identifier rather
  /// than to wording invented here.
  String get label => title.isNotEmpty ? title : method;

  @override
  bool operator ==(Object other) =>
      other is AgeVerificationMethod &&
      other.method == method &&
      other.vendor == vendor &&
      other.title == title &&
      other.description == description &&
      other.providedBy == providedBy;

  @override
  int get hashCode =>
      Object.hash(method, vendor, title, description, providedBy);
}

/// What Discord answers when a method is started.
///
/// Deliberately thin. Beyond a link to follow, the answer is vendor-specific
/// and is consumed by that vendor's own SDK in Discord's client; nothing here
/// pretends to understand the rest of it.
final class AgeVerificationStart {
  const AgeVerificationStart({this.continueUrl = ''});

  /// Where the check continues, when Discord names somewhere. Empty when the
  /// method needs a vendor surface this client does not carry.
  final String continueUrl;

  bool get canContinue => continueUrl.isNotEmpty;
}

/// Reads the ways an account may prove its age, and starts one.
abstract interface class AgeVerificationRepository {
  /// `GET /age-verification/methods`.
  Future<List<AgeVerificationMethod>> loadMethods();

  /// `POST /age-verification/verify`.
  ///
  /// Returns null when Discord refused to start it, which it does for a
  /// method the account is not eligible for.
  Future<AgeVerificationStart?> start(AgeVerificationMethod method);
}
