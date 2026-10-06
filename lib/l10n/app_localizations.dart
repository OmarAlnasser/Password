import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VaultSnap'**
  String get appTitle;

  /// No description provided for @createVault.
  ///
  /// In en, this message translates to:
  /// **'Create your vault'**
  String get createVault;

  /// No description provided for @masterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm master password'**
  String get confirmPassword;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDontMatch;

  /// No description provided for @passwordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password (at least \"strong\")'**
  String get passwordTooWeak;

  /// No description provided for @masterPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'This password is never sent anywhere and cannot be reset. If you forget it, only your recovery key can unlock the vault.'**
  String get masterPasswordHint;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @signInExisting.
  ///
  /// In en, this message translates to:
  /// **'Sign in to an existing vault'**
  String get signInExisting;

  /// No description provided for @recoveryKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery key'**
  String get recoveryKeyTitle;

  /// No description provided for @recoveryKeyExplain.
  ///
  /// In en, this message translates to:
  /// **'Write this down and keep it somewhere safe. It is shown only once and is the only way back in if you forget your master password.'**
  String get recoveryKeyExplain;

  /// No description provided for @recoveryKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type the last group ({group}) to confirm you saved it'**
  String recoveryKeyConfirm(Object group);

  /// No description provided for @iSavedIt.
  ///
  /// In en, this message translates to:
  /// **'I saved it'**
  String get iSavedIt;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @unlockWithBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockWithBiometrics;

  /// No description provided for @useRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Use recovery key'**
  String get useRecoveryKey;

  /// No description provided for @recoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get recoveryKey;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get wrongPassword;

  /// No description provided for @invalidRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery key'**
  String get invalidRecoveryKey;

  /// No description provided for @tryAgainIn.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds}s'**
  String tryAgainIn(Object seconds);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @allItems.
  ///
  /// In en, this message translates to:
  /// **'All items'**
  String get allItems;

  /// No description provided for @noEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get noEntries;

  /// No description provided for @addEntry.
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get addEntry;

  /// No description provided for @editEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get editEntry;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Email / username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @url.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get url;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get tags;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @totpSecret.
  ///
  /// In en, this message translates to:
  /// **'TOTP secret or otpauth:// URI'**
  String get totpSecret;

  /// No description provided for @invalidTotp.
  ///
  /// In en, this message translates to:
  /// **'Invalid TOTP secret'**
  String get invalidTotp;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String deleteConfirm(Object title);

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied. Clipboard clears in {seconds}s'**
  String copied(Object seconds);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @passwordHistory.
  ///
  /// In en, this message translates to:
  /// **'Password history'**
  String get passwordHistory;

  /// No description provided for @oneTimeCode.
  ///
  /// In en, this message translates to:
  /// **'One-time code'**
  String get oneTimeCode;

  /// No description provided for @generator.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get generator;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @length.
  ///
  /// In en, this message translates to:
  /// **'Length: {n}'**
  String length(Object n);

  /// No description provided for @lowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase (a-z)'**
  String get lowercase;

  /// No description provided for @uppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase (A-Z)'**
  String get uppercase;

  /// No description provided for @digits.
  ///
  /// In en, this message translates to:
  /// **'Digits (0-9)'**
  String get digits;

  /// No description provided for @symbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get symbols;

  /// No description provided for @excludeAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Avoid look-alikes (0/O, l/I/1)'**
  String get excludeAmbiguous;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @words.
  ///
  /// In en, this message translates to:
  /// **'Words: {n}'**
  String words(Object n);

  /// No description provided for @useThis.
  ///
  /// In en, this message translates to:
  /// **'Use this password'**
  String get useThis;

  /// No description provided for @strength0.
  ///
  /// In en, this message translates to:
  /// **'Very weak'**
  String get strength0;

  /// No description provided for @strength1.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strength1;

  /// No description provided for @strength2.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get strength2;

  /// No description provided for @strength3.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strength3;

  /// No description provided for @strength4.
  ///
  /// In en, this message translates to:
  /// **'Very strong'**
  String get strength4;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock after inactivity'**
  String get autoLock;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String minutes(Object n);

  /// No description provided for @lockOnBackground.
  ///
  /// In en, this message translates to:
  /// **'Lock when app goes to background'**
  String get lockOnBackground;

  /// No description provided for @clipboardClear.
  ///
  /// In en, this message translates to:
  /// **'Clear clipboard after'**
  String get clipboardClear;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{n} s'**
  String seconds(Object n);

  /// No description provided for @biometrics.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometrics;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current master password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New master password'**
  String get newPassword;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Master password changed'**
  String get passwordChanged;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @importExport.
  ///
  /// In en, this message translates to:
  /// **'Import / export'**
  String get importExport;

  /// No description provided for @exportEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Export encrypted backup'**
  String get exportEncrypted;

  /// No description provided for @importEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Import encrypted backup'**
  String get importEncrypted;

  /// No description provided for @importCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV (Chrome / Bitwarden)'**
  String get importCsv;

  /// No description provided for @exportPassword.
  ///
  /// In en, this message translates to:
  /// **'Export password'**
  String get exportPassword;

  /// No description provided for @imported.
  ///
  /// In en, this message translates to:
  /// **'Imported {n} entries ({skipped} skipped)'**
  String imported(Object n, Object skipped);

  /// No description provided for @exported.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get exported;

  /// No description provided for @csvWarning.
  ///
  /// In en, this message translates to:
  /// **'Delete the CSV file after importing: it contains your passwords in plain text.'**
  String get csvWarning;

  /// No description provided for @scanScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Import from screenshot'**
  String get scanScreenshot;

  /// No description provided for @pickImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get pickImage;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @ocrNoText.
  ///
  /// In en, this message translates to:
  /// **'No text found in the image'**
  String get ocrNoText;

  /// No description provided for @ocrTapChip.
  ///
  /// In en, this message translates to:
  /// **'Tap a piece of text to use it as the username, password, link or name.'**
  String get ocrTapChip;

  /// No description provided for @ocrUseAs.
  ///
  /// In en, this message translates to:
  /// **'Use as…'**
  String get ocrUseAs;

  /// No description provided for @ocrReview.
  ///
  /// In en, this message translates to:
  /// **'Review detected values before saving'**
  String get ocrReview;

  /// No description provided for @ocrAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Highlighted characters are easy to misread (0/O, l/I/1)'**
  String get ocrAmbiguous;

  /// No description provided for @ocrChipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Detected text'**
  String get ocrChipsTitle;

  /// No description provided for @ocrShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all ({n})'**
  String ocrShowAll(int n);

  /// No description provided for @ocrAsUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get ocrAsUsername;

  /// No description provided for @ocrAsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get ocrAsPassword;

  /// No description provided for @ocrAsLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get ocrAsLink;

  /// No description provided for @ocrAsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ocrAsName;

  /// No description provided for @ocrOtherReadings.
  ///
  /// In en, this message translates to:
  /// **'Other readings'**
  String get ocrOtherReadings;

  /// No description provided for @ocrPickHint.
  ///
  /// In en, this message translates to:
  /// **'Not sure which text is the email or the password. Tap a piece of text below to use it, or type it in.'**
  String get ocrPickHint;

  /// No description provided for @ocrWhatWasRead.
  ///
  /// In en, this message translates to:
  /// **'What was read'**
  String get ocrWhatWasRead;

  /// No description provided for @ocrWhatWasReadNote.
  ///
  /// In en, this message translates to:
  /// **'The text the scanner recognised, kept in memory only. It can show why a login was missed.'**
  String get ocrWhatWasReadNote;

  /// No description provided for @ocrPassTitle.
  ///
  /// In en, this message translates to:
  /// **'Pass {n}: {name}'**
  String ocrPassTitle(int n, Object name);

  /// No description provided for @ocrPassNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing read'**
  String get ocrPassNothing;

  /// No description provided for @ocrPassFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed ({reason})'**
  String ocrPassFailed(Object reason);

  /// No description provided for @ocrTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get ocrTipsTitle;

  /// No description provided for @ocrTipCrop.
  ///
  /// In en, this message translates to:
  /// **'Copy a bigger area: leave a little space around the email and password.'**
  String get ocrTipCrop;

  /// No description provided for @ocrTipVisible.
  ///
  /// In en, this message translates to:
  /// **'Make sure the text is clearly visible on screen, not covered, blurred or very small.'**
  String get ocrTipVisible;

  /// No description provided for @ocrTipAgain.
  ///
  /// In en, this message translates to:
  /// **'Copy the image again, then try again. Copying the text itself instead of a screenshot also works.'**
  String get ocrTipAgain;

  /// No description provided for @ocrNoLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Windows has no OCR language installed'**
  String get ocrNoLanguageTitle;

  /// No description provided for @ocrNoLanguageBody.
  ///
  /// In en, this message translates to:
  /// **'Windows reads text in images with an OCR language pack, and none is installed. To add one:'**
  String get ocrNoLanguageBody;

  /// No description provided for @ocrNoLanguageStep1.
  ///
  /// In en, this message translates to:
  /// **'Open Settings > Time & language > Language & region.'**
  String get ocrNoLanguageStep1;

  /// No description provided for @ocrNoLanguageStep2.
  ///
  /// In en, this message translates to:
  /// **'Choose Add a language and pick one (English reads email addresses and passwords well).'**
  String get ocrNoLanguageStep2;

  /// No description provided for @ocrNoLanguageStep3.
  ///
  /// In en, this message translates to:
  /// **'Make sure Optical character recognition is ticked while it installs.'**
  String get ocrNoLanguageStep3;

  /// No description provided for @ocrNoLanguageStep4.
  ///
  /// In en, this message translates to:
  /// **'Come back here and paste again.'**
  String get ocrNoLanguageStep4;

  /// No description provided for @ocrTooLargeTitle.
  ///
  /// In en, this message translates to:
  /// **'The image is too large to scan'**
  String get ocrTooLargeTitle;

  /// No description provided for @ocrTooLargeBody.
  ///
  /// In en, this message translates to:
  /// **'Copy or crop a smaller area around the email and password, then try again.'**
  String get ocrTooLargeBody;

  /// No description provided for @ocrUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'This image can\'t be read'**
  String get ocrUnsupportedTitle;

  /// No description provided for @ocrUnsupportedBody.
  ///
  /// In en, this message translates to:
  /// **'Copy it again as a normal screenshot (PNG or JPEG) and try again.'**
  String get ocrUnsupportedBody;

  /// No description provided for @ocrUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'The image file couldn\'t be opened'**
  String get ocrUnreadableTitle;

  /// No description provided for @ocrUnreadableBody.
  ///
  /// In en, this message translates to:
  /// **'The file may have been moved or deleted. Copy the image again and try again.'**
  String get ocrUnreadableBody;

  /// No description provided for @ocrTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Scanning took too long'**
  String get ocrTimeoutTitle;

  /// No description provided for @ocrTimeoutBody.
  ///
  /// In en, this message translates to:
  /// **'Scanning was stopped. Copy a smaller area around the email and password and try again.'**
  String get ocrTimeoutBody;

  /// No description provided for @ocrFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Text recognition failed'**
  String get ocrFailedTitle;

  /// No description provided for @ocrFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while reading the image. Try again, or copy a bigger area.'**
  String get ocrFailedBody;

  /// No description provided for @ocrPasteAgain.
  ///
  /// In en, this message translates to:
  /// **'Paste again'**
  String get ocrPasteAgain;

  /// No description provided for @ocrFillByHand.
  ///
  /// In en, this message translates to:
  /// **'Fill in by hand'**
  String get ocrFillByHand;

  /// No description provided for @deleteSourceImage.
  ///
  /// In en, this message translates to:
  /// **'Delete the source image?'**
  String get deleteSourceImage;

  /// No description provided for @deleteSourceImageBody.
  ///
  /// In en, this message translates to:
  /// **'The screenshot contains your password in plain text. Cloud photo backups may already have a copy.'**
  String get deleteSourceImageBody;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @imageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Image deleted'**
  String get imageDeleted;

  /// No description provided for @securityDashboard.
  ///
  /// In en, this message translates to:
  /// **'Security dashboard'**
  String get securityDashboard;

  /// No description provided for @weakPasswords.
  ///
  /// In en, this message translates to:
  /// **'Weak passwords'**
  String get weakPasswords;

  /// No description provided for @reusedPasswords.
  ///
  /// In en, this message translates to:
  /// **'Reused passwords'**
  String get reusedPasswords;

  /// No description provided for @oldPasswords.
  ///
  /// In en, this message translates to:
  /// **'Old passwords (> 1 year)'**
  String get oldPasswords;

  /// No description provided for @breachedPasswords.
  ///
  /// In en, this message translates to:
  /// **'Found in data breaches'**
  String get breachedPasswords;

  /// No description provided for @checkBreaches.
  ///
  /// In en, this message translates to:
  /// **'Check for breaches'**
  String get checkBreaches;

  /// No description provided for @hibpExplain.
  ///
  /// In en, this message translates to:
  /// **'Only the first 5 characters of each password\'s SHA-1 hash are sent to Have I Been Pwned. Your passwords never leave the device.'**
  String get hibpExplain;

  /// No description provided for @allGood.
  ///
  /// In en, this message translates to:
  /// **'Nothing to fix'**
  String get allGood;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @enableSync.
  ///
  /// In en, this message translates to:
  /// **'Enable sync'**
  String get enableSync;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @syncEnabled.
  ///
  /// In en, this message translates to:
  /// **'Synced as {email}'**
  String syncEnabled(Object email);

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncFailed;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {time}'**
  String lastSynced(Object time);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out of sync'**
  String get signOut;

  /// No description provided for @quickSearch.
  ///
  /// In en, this message translates to:
  /// **'Quick search'**
  String get quickSearch;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get error;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @pasteLogin.
  ///
  /// In en, this message translates to:
  /// **'Paste login'**
  String get pasteLogin;

  /// No description provided for @pasteNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No login found on the clipboard. Copy a screenshot or text with the email and password first.'**
  String get pasteNothingFound;

  /// No description provided for @saveLogin.
  ///
  /// In en, this message translates to:
  /// **'Save login'**
  String get saveLogin;

  /// No description provided for @quickMode.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get quickMode;

  /// No description provided for @advancedMode.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedMode;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @whereFrom.
  ///
  /// In en, this message translates to:
  /// **'Where is it from? (link)'**
  String get whereFrom;

  /// No description provided for @whyNotes.
  ///
  /// In en, this message translates to:
  /// **'Why / notes'**
  String get whyNotes;

  /// No description provided for @clearScreenshotTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the screenshot from your clipboard?'**
  String get clearScreenshotTitle;

  /// No description provided for @clearTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the copied text from your clipboard?'**
  String get clearTextTitle;

  /// No description provided for @clearClipboardBody.
  ///
  /// In en, this message translates to:
  /// **'It still shows this password, and other apps can read it. Copies already saved in a clipboard history (Windows + V, your keyboard app) are not removed; delete them there.'**
  String get clearClipboardBody;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clipboardCleared.
  ///
  /// In en, this message translates to:
  /// **'Clipboard cleared'**
  String get clipboardCleared;

  /// No description provided for @fetchIcons.
  ///
  /// In en, this message translates to:
  /// **'Fetch website icons'**
  String get fetchIcons;

  /// No description provided for @fetchIconsNote.
  ///
  /// In en, this message translates to:
  /// **'Icons are downloaded directly from each site, so the site sees your IP address.'**
  String get fetchIconsNote;

  /// No description provided for @reviewImport.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get reviewImport;

  /// No description provided for @importFound.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 login in the file} other{{n} logins in the file}}'**
  String importFound(int n);

  /// No description provided for @importSkippedRows.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 row skipped (empty or not a login)} other{{n} rows skipped (empty or not logins)}}'**
  String importSkippedRows(int n);

  /// No description provided for @importReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Ticked logins are imported. Tap a login to fix it.'**
  String get importReviewHint;

  /// No description provided for @importN.
  ///
  /// In en, this message translates to:
  /// **'Import {n}'**
  String importN(int n);

  /// No description provided for @noWebsite.
  ///
  /// In en, this message translates to:
  /// **'No website'**
  String get noWebsite;

  /// No description provided for @noUsername.
  ///
  /// In en, this message translates to:
  /// **'(no username)'**
  String get noUsername;

  /// No description provided for @reviewNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get reviewNew;

  /// No description provided for @reviewUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get reviewUpdate;

  /// No description provided for @reviewMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged duplicates'**
  String get reviewMerged;

  /// No description provided for @reviewSkip.
  ///
  /// In en, this message translates to:
  /// **'Already saved'**
  String get reviewSkip;

  /// No description provided for @reviewAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get reviewAttention;

  /// No description provided for @reviewUpdates.
  ///
  /// In en, this message translates to:
  /// **'Replaces the password of “{title}”; the old one stays in its history'**
  String reviewUpdates(Object title);

  /// No description provided for @issueMissingPassword.
  ///
  /// In en, this message translates to:
  /// **'No password'**
  String get issueMissingPassword;

  /// No description provided for @issueMissingUsername.
  ///
  /// In en, this message translates to:
  /// **'No username'**
  String get issueMissingUsername;

  /// No description provided for @issueInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Email looks wrong'**
  String get issueInvalidEmail;

  /// No description provided for @issueUsernameIsUrl.
  ///
  /// In en, this message translates to:
  /// **'Username is a link'**
  String get issueUsernameIsUrl;

  /// No description provided for @issuePasswordLooksLikeEmail.
  ///
  /// In en, this message translates to:
  /// **'Password looks like an email'**
  String get issuePasswordLooksLikeEmail;

  /// No description provided for @issueUsernameLooksLikePassword.
  ///
  /// In en, this message translates to:
  /// **'Username looks like a password'**
  String get issueUsernameLooksLikePassword;

  /// No description provided for @issueInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'No valid website'**
  String get issueInvalidUrl;

  /// No description provided for @issueInsecureHttp.
  ///
  /// In en, this message translates to:
  /// **'Not secure (http)'**
  String get issueInsecureHttp;

  /// No description provided for @issueDuplicateInFile.
  ///
  /// In en, this message translates to:
  /// **'Duplicate in file'**
  String get issueDuplicateInFile;

  /// No description provided for @issueExistsWithDifferentPassword.
  ///
  /// In en, this message translates to:
  /// **'Saved with another password'**
  String get issueExistsWithDifferentPassword;

  /// No description provided for @editLogin.
  ///
  /// In en, this message translates to:
  /// **'Edit login'**
  String get editLogin;

  /// No description provided for @swapUserPassword.
  ///
  /// In en, this message translates to:
  /// **'Swap username and password'**
  String get swapUserPassword;

  /// No description provided for @deleteCsvTitle.
  ///
  /// In en, this message translates to:
  /// **'Now delete the CSV file'**
  String get deleteCsvTitle;

  /// No description provided for @deleteCsvBody.
  ///
  /// In en, this message translates to:
  /// **'It holds all your passwords in plain text. Delete it from Downloads, empty the trash or recycle bin, and remove any copy in cloud storage or email.'**
  String get deleteCsvBody;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot your master password?'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody can recover it, not even the VaultSnap developer. It is never stored or sent anywhere, and your vault is encrypted with it.'**
  String get forgotPasswordBody;

  /// No description provided for @useRecoveryKeyExplain.
  ///
  /// In en, this message translates to:
  /// **'Unlock with the recovery key you saved when you created the vault, then choose a new password.'**
  String get useRecoveryKeyExplain;

  /// No description provided for @resetVault.
  ///
  /// In en, this message translates to:
  /// **'Reset vault — erase everything'**
  String get resetVault;

  /// No description provided for @resetVaultExplain.
  ///
  /// In en, this message translates to:
  /// **'Start over with an empty vault. Everything stored in this vault is lost.'**
  String get resetVaultExplain;

  /// No description provided for @resetVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase this vault?'**
  String get resetVaultTitle;

  /// No description provided for @resetVaultBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes every password and note in the vault on this device. It cannot be undone.'**
  String get resetVaultBody;

  /// No description provided for @resetConfirmWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get resetConfirmWord;

  /// No description provided for @resetTypeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String resetTypeToConfirm(Object word);

  /// No description provided for @eraseVault.
  ///
  /// In en, this message translates to:
  /// **'Erase vault'**
  String get eraseVault;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
