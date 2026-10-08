// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hisn';

  @override
  String get createVault => 'Create your vault';

  @override
  String get masterPassword => 'Master password';

  @override
  String get confirmPassword => 'Confirm master password';

  @override
  String get passwordsDontMatch => 'Passwords do not match';

  @override
  String get passwordTooWeak =>
      'Choose a stronger password (at least \"strong\")';

  @override
  String get masterPasswordHint =>
      'This password is never sent anywhere and cannot be reset. If you forget it, only your recovery key can unlock the vault.';

  @override
  String get create => 'Create';

  @override
  String get signInExisting => 'Sign in to an existing vault';

  @override
  String get recoveryKeyTitle => 'Your recovery key';

  @override
  String get recoveryKeyExplain =>
      'Write this down and keep it somewhere safe. It is shown only once and is the only way back in if you forget your master password.';

  @override
  String recoveryKeyConfirm(Object group) {
    return 'Type the last group ($group) to confirm you saved it';
  }

  @override
  String get iSavedIt => 'I saved it';

  @override
  String get unlock => 'Unlock';

  @override
  String get unlockWithBiometrics => 'Unlock with biometrics';

  @override
  String get useRecoveryKey => 'Use recovery key';

  @override
  String get recoveryKey => 'Recovery key';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get invalidRecoveryKey => 'Invalid recovery key';

  @override
  String tryAgainIn(Object seconds) {
    return 'Too many attempts. Try again in ${seconds}s';
  }

  @override
  String get search => 'Search';

  @override
  String get favorites => 'Favorites';

  @override
  String get allItems => 'All items';

  @override
  String get noEntries => 'No entries yet';

  @override
  String get addEntry => 'Add entry';

  @override
  String get editEntry => 'Edit entry';

  @override
  String get title => 'Title';

  @override
  String get username => 'Email / username';

  @override
  String get password => 'Password';

  @override
  String get url => 'Website';

  @override
  String get notes => 'Notes';

  @override
  String get tags => 'Tags (comma separated)';

  @override
  String get favorite => 'Favorite';

  @override
  String get totpSecret => 'TOTP secret or otpauth:// URI';

  @override
  String get invalidTotp => 'Invalid TOTP secret';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String deleteConfirm(Object title) {
    return 'Delete \"$title\"?';
  }

  @override
  String copied(Object seconds) {
    return 'Copied. Clipboard clears in ${seconds}s';
  }

  @override
  String get copy => 'Copy';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get passwordHistory => 'Password history';

  @override
  String get oneTimeCode => 'One-time code';

  @override
  String get generator => 'Password generator';

  @override
  String get generate => 'Generate';

  @override
  String length(Object n) {
    return 'Length: $n';
  }

  @override
  String get lowercase => 'Lowercase (a-z)';

  @override
  String get uppercase => 'Uppercase (A-Z)';

  @override
  String get digits => 'Digits (0-9)';

  @override
  String get symbols => 'Symbols';

  @override
  String get excludeAmbiguous => 'Avoid look-alikes (0/O, l/I/1)';

  @override
  String get passphrase => 'Passphrase';

  @override
  String words(Object n) {
    return 'Words: $n';
  }

  @override
  String get useThis => 'Use this password';

  @override
  String get strength0 => 'Very weak';

  @override
  String get strength1 => 'Weak';

  @override
  String get strength2 => 'Fair';

  @override
  String get strength3 => 'Strong';

  @override
  String get strength4 => 'Very strong';

  @override
  String get settings => 'Settings';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get autoLock => 'Auto-lock after inactivity';

  @override
  String minutes(Object n) {
    return '$n min';
  }

  @override
  String get lockOnBackground => 'Lock when app goes to background';

  @override
  String get clipboardClear => 'Clear clipboard after';

  @override
  String seconds(Object n) {
    return '$n s';
  }

  @override
  String get biometrics => 'Biometric unlock';

  @override
  String get changePassword => 'Change master password';

  @override
  String get currentPassword => 'Current master password';

  @override
  String get newPassword => 'New master password';

  @override
  String get passwordChanged => 'Master password changed';

  @override
  String get lock => 'Lock';

  @override
  String get importExport => 'Import / export';

  @override
  String get exportEncrypted => 'Export encrypted backup';

  @override
  String get importEncrypted => 'Import encrypted backup';

  @override
  String get importCsv => 'Import CSV (Chrome / Bitwarden)';

  @override
  String get exportPassword => 'Export password';

  @override
  String imported(Object n, Object skipped) {
    return 'Imported $n entries ($skipped skipped)';
  }

  @override
  String get exported => 'Backup saved';

  @override
  String get csvWarning =>
      'Delete the CSV file after importing: it contains your passwords in plain text.';

  @override
  String get scanScreenshot => 'Import from screenshot';

  @override
  String get pickImage => 'Choose image';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get ocrNoText => 'No text found in the image';

  @override
  String get ocrTapChip =>
      'Tap a piece of text to use it as the username, password, link or name.';

  @override
  String get ocrUseAs => 'Use as…';

  @override
  String get ocrReview => 'Review detected values before saving';

  @override
  String get ocrAmbiguous =>
      'Highlighted characters are easy to misread (0/O, l/I/1)';

  @override
  String get ocrChipsTitle => 'Detected text';

  @override
  String ocrShowAll(int n) {
    return 'Show all ($n)';
  }

  @override
  String get ocrAsUsername => 'Username';

  @override
  String get ocrAsPassword => 'Password';

  @override
  String get ocrAsLink => 'Link';

  @override
  String get ocrAsName => 'Name';

  @override
  String get ocrOtherReadings => 'Other readings';

  @override
  String get ocrPickHint =>
      'Not sure which text is the email or the password. Tap a piece of text below to use it, or type it in.';

  @override
  String get ocrWhatWasRead => 'What was read';

  @override
  String get ocrWhatWasReadNote =>
      'The text the scanner recognised, kept in memory only. It can show why a login was missed.';

  @override
  String ocrPassTitle(int n, Object name) {
    return 'Pass $n: $name';
  }

  @override
  String get ocrPassNothing => 'Nothing read';

  @override
  String ocrPassFailed(Object reason) {
    return 'Failed ($reason)';
  }

  @override
  String get ocrTipsTitle => 'Tips';

  @override
  String get ocrTipCrop =>
      'Copy a bigger area: leave a little space around the email and password.';

  @override
  String get ocrTipVisible =>
      'Make sure the text is clearly visible on screen, not covered, blurred or very small.';

  @override
  String get ocrTipAgain =>
      'Copy the image again, then try again. Copying the text itself instead of a screenshot also works.';

  @override
  String get ocrNoLanguageTitle => 'Windows has no OCR language installed';

  @override
  String get ocrNoLanguageBody =>
      'Windows reads text in images with an OCR language pack, and none is installed. To add one:';

  @override
  String get ocrNoLanguageStep1 =>
      'Open Settings > Time & language > Language & region.';

  @override
  String get ocrNoLanguageStep2 =>
      'Choose Add a language and pick one (English reads email addresses and passwords well).';

  @override
  String get ocrNoLanguageStep3 =>
      'Make sure Optical character recognition is ticked while it installs.';

  @override
  String get ocrNoLanguageStep4 => 'Come back here and paste again.';

  @override
  String get ocrTooLargeTitle => 'The image is too large to scan';

  @override
  String get ocrTooLargeBody =>
      'Copy or crop a smaller area around the email and password, then try again.';

  @override
  String get ocrUnsupportedTitle => 'This image can\'t be read';

  @override
  String get ocrUnsupportedBody =>
      'Copy it again as a normal screenshot (PNG or JPEG) and try again.';

  @override
  String get ocrUnreadableTitle => 'The image file couldn\'t be opened';

  @override
  String get ocrUnreadableBody =>
      'The file may have been moved or deleted. Copy the image again and try again.';

  @override
  String get ocrTimeoutTitle => 'Scanning took too long';

  @override
  String get ocrTimeoutBody =>
      'Scanning was stopped. Copy a smaller area around the email and password and try again.';

  @override
  String get ocrFailedTitle => 'Text recognition failed';

  @override
  String get ocrFailedBody =>
      'Something went wrong while reading the image. Try again, or copy a bigger area.';

  @override
  String get ocrPasteAgain => 'Paste again';

  @override
  String get ocrFillByHand => 'Fill in by hand';

  @override
  String get deleteSourceImage => 'Delete the source image?';

  @override
  String get deleteSourceImageBody =>
      'The screenshot contains your password in plain text. Cloud photo backups may already have a copy.';

  @override
  String get keep => 'Keep';

  @override
  String get imageDeleted => 'Image deleted';

  @override
  String get securityDashboard => 'Security dashboard';

  @override
  String get weakPasswords => 'Weak passwords';

  @override
  String get reusedPasswords => 'Reused passwords';

  @override
  String get oldPasswords => 'Old passwords (> 1 year)';

  @override
  String get breachedPasswords => 'Found in data breaches';

  @override
  String get checkBreaches => 'Check for breaches';

  @override
  String get hibpExplain =>
      'Only the first 5 characters of each password\'s SHA-1 hash are sent to Have I Been Pwned. Your passwords never leave the device.';

  @override
  String get allGood => 'Nothing to fix';

  @override
  String get sync => 'Sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get enableSync => 'Enable sync';

  @override
  String get email => 'Email';

  @override
  String syncEnabled(Object email) {
    return 'Synced as $email';
  }

  @override
  String get syncFailed => 'Sync failed';

  @override
  String lastSynced(Object time) {
    return 'Last synced $time';
  }

  @override
  String get signOut => 'Sign out of sync';

  @override
  String get quickSearch => 'Quick search';

  @override
  String get error => 'Something went wrong';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get pasteLogin => 'Paste login';

  @override
  String get pasteNothingFound =>
      'No login found on the clipboard. Copy a screenshot or text with the email and password first.';

  @override
  String get saveLogin => 'Save login';

  @override
  String get quickMode => 'Quick';

  @override
  String get advancedMode => 'Advanced';

  @override
  String get name => 'Name';

  @override
  String get whereFrom => 'Where is it from? (link)';

  @override
  String get whyNotes => 'Why / notes';

  @override
  String get clearScreenshotTitle =>
      'Clear the screenshot from your clipboard?';

  @override
  String get clearTextTitle => 'Clear the copied text from your clipboard?';

  @override
  String get clearClipboardBody =>
      'It still shows this password, and other apps can read it. Copies already saved in a clipboard history (Windows + V, your keyboard app) are not removed; delete them there.';

  @override
  String get clear => 'Clear';

  @override
  String get clipboardCleared => 'Clipboard cleared';

  @override
  String get fetchIcons => 'Fetch website icons';

  @override
  String get fetchIconsNote =>
      'Icons are downloaded directly from each site, so the site sees your IP address.';

  @override
  String get reviewImport => 'Review import';

  @override
  String importFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n logins in the file',
      one: '1 login in the file',
    );
    return '$_temp0';
  }

  @override
  String importSkippedRows(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n rows skipped (empty or not logins)',
      one: '1 row skipped (empty or not a login)',
    );
    return '$_temp0';
  }

  @override
  String get importReviewHint =>
      'Ticked logins are imported. Tap a login to fix it.';

  @override
  String importN(int n) {
    return 'Import $n';
  }

  @override
  String get noWebsite => 'No website';

  @override
  String get noUsername => '(no username)';

  @override
  String get reviewNew => 'New';

  @override
  String get reviewUpdate => 'Update';

  @override
  String get reviewMerged => 'Merged duplicates';

  @override
  String get reviewSkip => 'Already saved';

  @override
  String get reviewAttention => 'Needs attention';

  @override
  String reviewUpdates(Object title) {
    return 'Replaces the password of “$title”; the old one stays in its history';
  }

  @override
  String get issueMissingPassword => 'No password';

  @override
  String get issueMissingUsername => 'No username';

  @override
  String get issueInvalidEmail => 'Email looks wrong';

  @override
  String get issueUsernameIsUrl => 'Username is a link';

  @override
  String get issuePasswordLooksLikeEmail => 'Password looks like an email';

  @override
  String get issueUsernameLooksLikePassword => 'Username looks like a password';

  @override
  String get issueInvalidUrl => 'No valid website';

  @override
  String get issueInsecureHttp => 'Not secure (http)';

  @override
  String get issueDuplicateInFile => 'Duplicate in file';

  @override
  String get issueExistsWithDifferentPassword => 'Saved with another password';

  @override
  String get editLogin => 'Edit login';

  @override
  String get swapUserPassword => 'Swap username and password';

  @override
  String get deleteCsvTitle => 'Now delete the CSV file';

  @override
  String get deleteCsvBody =>
      'It holds all your passwords in plain text. Delete it from Downloads, empty the trash or recycle bin, and remove any copy in cloud storage or email.';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get forgotPasswordTitle => 'Forgot your master password?';

  @override
  String get forgotPasswordBody =>
      'Nobody can recover it, not even the Hisn developer. It is never stored or sent anywhere, and your vault is encrypted with it.';

  @override
  String get useRecoveryKeyExplain =>
      'Unlock with the recovery key you saved when you created the vault, then choose a new password.';

  @override
  String get resetVault => 'Reset vault — erase everything';

  @override
  String get resetVaultExplain =>
      'Start over with an empty vault. Everything stored in this vault is lost.';

  @override
  String get resetVaultTitle => 'Erase this vault?';

  @override
  String get resetVaultBody =>
      'This permanently deletes every password and note in the vault on this device. It cannot be undone.';

  @override
  String get resetConfirmWord => 'DELETE';

  @override
  String resetTypeToConfirm(Object word) {
    return 'Type $word to confirm';
  }

  @override
  String get eraseVault => 'Erase vault';

  @override
  String get updateAvailable => 'Update available';

  @override
  String updateVersionNumber(Object version) {
    return 'Version $version';
  }

  @override
  String updateVersionAvailable(Object version) {
    return 'Version $version is available';
  }

  @override
  String updateYourVersion(Object version) {
    return 'You have $version';
  }

  @override
  String updateDownloadSize(Object size) {
    return 'Download size: $size';
  }

  @override
  String updateSizeMb(Object size) {
    return '$size MB';
  }

  @override
  String updateSizeKb(Object size) {
    return '$size KB';
  }

  @override
  String updateReleased(Object date) {
    return 'Released $date';
  }

  @override
  String get updateWhatsNew => 'What’s new';

  @override
  String get updateNoNotes => 'No release notes were provided.';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateSkipVersion => 'Skip this version';

  @override
  String get updateSkipNote =>
      'You won’t be reminded about this version. A newer one will still be offered.';

  @override
  String get updateHideBanner => 'Hide for now';

  @override
  String get updateTapForDetails => 'Tap for details';

  @override
  String get updateDownloading => 'Downloading update';

  @override
  String updateBannerDownloading(Object percent) {
    return 'Downloading update… $percent%';
  }

  @override
  String updateDownloadProgress(Object percent, Object size) {
    return '$percent% of $size';
  }

  @override
  String get updateDownloadBackground =>
      'You can keep using the app. The download continues in the background.';

  @override
  String get updateCancelDownload => 'Cancel download';

  @override
  String get updateVerifying => 'Checking the download';

  @override
  String get updateVerifyingNote =>
      'Comparing the file with the signed release information…';

  @override
  String get updateReadyTitle => 'Ready to install';

  @override
  String get updateReadyNote =>
      'The download is complete and verified. Nothing is installed until you tap the button.';

  @override
  String get updateReadyAndroid =>
      'Android will open its installer. Tap Install there to finish.';

  @override
  String get updateReadyWindows =>
      'The app will lock your vault, close, install the update and open again.';

  @override
  String get updateInstall => 'Install';

  @override
  String get updateInstallWindows => 'Close and install';

  @override
  String get updateInstalling => 'Handing over to the installer…';

  @override
  String get updateInstallingWindows => 'Closing to install…';

  @override
  String get updateInstallerOpen =>
      'The system installer is open. Tap Install there to finish.';

  @override
  String get updateInstallerReopen => 'Open the installer again';

  @override
  String get updatePermissionTitle => 'Allow installs from this app';

  @override
  String get updatePermissionBody =>
      'Android needs your permission before this app can install updates. In the settings page that just opened, turn on “Allow from this source”, go back, then tap Install again.';

  @override
  String get updateInstallFailedAndroid =>
      'Android didn’t accept this update. The installed app may have been signed differently (for example a test build). In that case install the new version by hand from the release page. Uninstalling removes the vault stored on this device, so export or sync it first.';

  @override
  String get updateInstallFailedWindows =>
      'The update couldn’t be installed automatically. The app’s folder may be protected (for example inside Program Files) or in use. Nothing was changed. Download the new version from the release page and replace the app by hand.';

  @override
  String get updateInstallUnsupported =>
      'Installing updates isn’t available here. Download the new version from the release page.';

  @override
  String get updateOpenReleasePage => 'Open release page';

  @override
  String get updateCopyLink => 'Copy link';

  @override
  String get updateLinkCopied => 'Link copied';

  @override
  String get updateRetry => 'Try again';

  @override
  String get updateErrorTitle => 'Couldn’t update';

  @override
  String get updateRejectedTitle => 'Update rejected for your safety';

  @override
  String get updateErrorOffline =>
      'Couldn’t reach GitHub. Check your internet connection and try again.';

  @override
  String get updateErrorServer =>
      'The update server didn’t answer properly. Try again later.';

  @override
  String get updateErrorDamaged =>
      'The downloaded file was incomplete or didn’t match the signed release information, so it was deleted. Try downloading it again.';

  @override
  String get updateErrorBlocked =>
      'The download was blocked because it didn’t come from the official release address.';

  @override
  String get updateErrorSignature =>
      'This update’s signature could not be verified, so it was not used. Nothing was installed. If this keeps happening, get the app again from the official release page.';

  @override
  String get updateErrorRollback =>
      'An older release than one already seen was offered, so it was ignored. Nothing was installed.';

  @override
  String get updateErrorSchema =>
      'This update can’t be read by this version of the app. Download the new version from the release page.';

  @override
  String get updateErrorNoPackage =>
      'The latest release has no package for this device yet. Try again later.';

  @override
  String get updateErrorStorage =>
      'The update couldn’t be saved on this device. Free some space and try again.';

  @override
  String get updateErrorInternal =>
      'Something went wrong with the update. Try again later.';

  @override
  String get updateAutoCheck => 'Check for updates automatically';

  @override
  String get updateAutoCheckNote =>
      'Looks for a new version on GitHub at most once a day. Nothing from your vault is sent, but GitHub sees your IP address.';

  @override
  String get updateCheckNow => 'Check now';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateVersionTitle => 'Version';

  @override
  String updateVersionBuild(Object version, Object build) {
    return '$version (build $build)';
  }

  @override
  String get updateDevBuild => 'Development build';

  @override
  String updateLastChecked(Object when) {
    return 'Last checked: $when';
  }

  @override
  String get updateNeverChecked => 'Not checked yet';

  @override
  String get updateUpToDate => 'You have the latest version.';

  @override
  String get updateViewUpdate => 'View update';

  @override
  String get updateBannerFailed => 'The update didn’t finish';

  @override
  String get updateNoticeTitle => 'The last update didn’t finish';

  @override
  String get updateNoticeRolledBack =>
      'The update could not be completed. The previous version is still installed and working.';

  @override
  String get updateNoticeDamaged =>
      'The update failed and the app may be damaged. Download the latest release from the release page and replace the app’s folder.';

  @override
  String get updateNoticeAborted =>
      'The update did not start, so nothing was changed.';

  @override
  String get updateSettingsGroup => 'Updates';

  @override
  String get updateDevOff => 'Updates are off in development builds.';

  @override
  String get crackLessThanSecond => 'less than a second';

  @override
  String crackSeconds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String crackMinutes(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String crackHours(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String crackDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String crackMonths(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String crackYears(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years',
      one: '1 year',
    );
    return '$_temp0';
  }

  @override
  String get crackCenturies => 'centuries';

  @override
  String get noResults => 'No results';

  @override
  String get passwordHidden => 'Password hidden';
}
