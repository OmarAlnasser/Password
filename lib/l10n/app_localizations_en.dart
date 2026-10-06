// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VaultSnap';

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
      'Tap a chip to copy it; long-press to use it in a field';

  @override
  String get ocrUseAs => 'Use as…';

  @override
  String get ocrReview => 'Review detected values before saving';

  @override
  String get ocrAmbiguous =>
      'Highlighted characters are easy to misread (0/O, l/I/1)';

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
  String get nameHint => 'e.g. Genshin Odette C2 acc';

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
      'Nobody can recover it, not even the VaultSnap developer. It is never stored or sent anywhere, and your vault is encrypted with it.';

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
}
