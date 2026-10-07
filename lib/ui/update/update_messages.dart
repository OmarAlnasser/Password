import '../../l10n/app_localizations.dart';
import '../../services/update/update_failure.dart';

/// What to tell the user about a failed update step, in plain language.
///
/// Built from the [UpdateFailure] enum only; no URL, path or server text ever
/// reaches the screen. [canRetry] says whether trying again can help (a lost
/// connection, a damaged download), [offerReleasePage] whether the user should
/// be pointed to the release page to get the app by hand.
class UpdateFailureText {
  const UpdateFailureText(
    this.title,
    this.body, {
    this.canRetry = false,
    this.offerReleasePage = false,
    this.rejected = false,
  });

  final String title;
  final String body;
  final bool canRetry;
  final bool offerReleasePage;

  /// The update itself was refused for safety reasons (bad signature, older
  /// release replayed). Shown with the "rejected for your safety" title.
  final bool rejected;
}

UpdateFailureText describeUpdateFailure(
  AppLocalizations l,
  UpdateFailure failure,
) => switch (failure) {
  UpdateFailure.network || UpdateFailure.timeout => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorOffline,
    canRetry: true,
  ),
  UpdateFailure.badStatus => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorServer,
    canRetry: true,
  ),
  UpdateFailure.tooLarge ||
  UpdateFailure.truncated ||
  UpdateFailure.hashMismatch => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorDamaged,
    canRetry: true,
  ),
  UpdateFailure.tooManyRedirects ||
  UpdateFailure.insecureUrl ||
  UpdateFailure.hostNotAllowed => UpdateFailureText(
    l.updateRejectedTitle,
    l.updateErrorBlocked,
    rejected: true,
  ),
  UpdateFailure.signatureInvalid => UpdateFailureText(
    l.updateRejectedTitle,
    l.updateErrorSignature,
    rejected: true,
    offerReleasePage: true,
  ),
  UpdateFailure.rollback => UpdateFailureText(
    l.updateRejectedTitle,
    l.updateErrorRollback,
    rejected: true,
  ),
  UpdateFailure.manifestInvalid ||
  UpdateFailure.unsupportedSchema => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorSchema,
    offerReleasePage: true,
  ),
  UpdateFailure.noAsset => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorNoPackage,
  ),
  UpdateFailure.storage => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorStorage,
    canRetry: true,
  ),
  UpdateFailure.installFailed => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorInternal,
    canRetry: true,
    offerReleasePage: true,
  ),
  UpdateFailure.cancelled ||
  UpdateFailure.disabled ||
  UpdateFailure.internal => UpdateFailureText(
    l.updateErrorTitle,
    l.updateErrorInternal,
    canRetry: true,
  ),
};
