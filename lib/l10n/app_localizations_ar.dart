// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'VaultSnap';

  @override
  String get createVault => 'أنشئ خزنتك';

  @override
  String get masterPassword => 'كلمة المرور الرئيسية';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور الرئيسية';

  @override
  String get passwordsDontMatch => 'كلمتا المرور غير متطابقتين';

  @override
  String get passwordTooWeak => 'اختر كلمة مرور أقوى (على الأقل \"قوية\")';

  @override
  String get masterPasswordHint =>
      'لا تُرسل كلمة المرور هذه إلى أي مكان ولا يمكن إعادة تعيينها. إذا نسيتها، فلن يفتح الخزنة إلا مفتاح الاسترداد.';

  @override
  String get create => 'إنشاء';

  @override
  String get signInExisting => 'تسجيل الدخول إلى خزنة موجودة';

  @override
  String get recoveryKeyTitle => 'مفتاح الاسترداد الخاص بك';

  @override
  String get recoveryKeyExplain =>
      'اكتب هذا المفتاح واحفظه في مكان آمن. يظهر مرة واحدة فقط وهو الطريقة الوحيدة للدخول إذا نسيت كلمة المرور الرئيسية.';

  @override
  String recoveryKeyConfirm(Object group) {
    return 'اكتب المجموعة الأخيرة ($group) لتأكيد أنك حفظته';
  }

  @override
  String get iSavedIt => 'لقد حفظته';

  @override
  String get unlock => 'فتح';

  @override
  String get unlockWithBiometrics => 'الفتح بالبصمة';

  @override
  String get useRecoveryKey => 'استخدام مفتاح الاسترداد';

  @override
  String get recoveryKey => 'مفتاح الاسترداد';

  @override
  String get wrongPassword => 'كلمة مرور خاطئة';

  @override
  String get invalidRecoveryKey => 'مفتاح استرداد غير صالح';

  @override
  String tryAgainIn(Object seconds) {
    return 'محاولات كثيرة. حاول مرة أخرى بعد $seconds ثانية';
  }

  @override
  String get search => 'بحث';

  @override
  String get favorites => 'المفضلة';

  @override
  String get allItems => 'كل العناصر';

  @override
  String get noEntries => 'لا توجد عناصر بعد';

  @override
  String get addEntry => 'إضافة عنصر';

  @override
  String get editEntry => 'تعديل العنصر';

  @override
  String get title => 'العنوان';

  @override
  String get username => 'البريد / اسم المستخدم';

  @override
  String get password => 'كلمة المرور';

  @override
  String get url => 'الموقع';

  @override
  String get notes => 'ملاحظات';

  @override
  String get tags => 'الوسوم (مفصولة بفواصل)';

  @override
  String get favorite => 'مفضل';

  @override
  String get totpSecret => 'مفتاح TOTP أو رابط otpauth://';

  @override
  String get invalidTotp => 'مفتاح TOTP غير صالح';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'إلغاء';

  @override
  String deleteConfirm(Object title) {
    return 'حذف \"$title\"؟';
  }

  @override
  String copied(Object seconds) {
    return 'تم النسخ. سيُمسح خلال $seconds ثانية';
  }

  @override
  String get copy => 'نسخ';

  @override
  String get show => 'إظهار';

  @override
  String get hide => 'إخفاء';

  @override
  String get passwordHistory => 'سجل كلمات المرور';

  @override
  String get oneTimeCode => 'رمز لمرة واحدة';

  @override
  String get generator => 'مولد كلمات المرور';

  @override
  String get generate => 'توليد';

  @override
  String length(Object n) {
    return 'الطول: $n';
  }

  @override
  String get lowercase => 'أحرف صغيرة (a-z)';

  @override
  String get uppercase => 'أحرف كبيرة (A-Z)';

  @override
  String get digits => 'أرقام (0-9)';

  @override
  String get symbols => 'رموز';

  @override
  String get excludeAmbiguous => 'تجنب المتشابهات (0/O, l/I/1)';

  @override
  String get passphrase => 'عبارة مرور';

  @override
  String words(Object n) {
    return 'الكلمات: $n';
  }

  @override
  String get useThis => 'استخدم كلمة المرور هذه';

  @override
  String get strength0 => 'ضعيفة جدًا';

  @override
  String get strength1 => 'ضعيفة';

  @override
  String get strength2 => 'مقبولة';

  @override
  String get strength3 => 'قوية';

  @override
  String get strength4 => 'قوية جدًا';

  @override
  String get settings => 'الإعدادات';

  @override
  String get theme => 'المظهر';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get language => 'اللغة';

  @override
  String get autoLock => 'القفل التلقائي بعد عدم النشاط';

  @override
  String minutes(Object n) {
    return '$n دقيقة';
  }

  @override
  String get lockOnBackground => 'القفل عند الانتقال للخلفية';

  @override
  String get clipboardClear => 'مسح الحافظة بعد';

  @override
  String seconds(Object n) {
    return '$n ث';
  }

  @override
  String get biometrics => 'الفتح بالبصمة';

  @override
  String get changePassword => 'تغيير كلمة المرور الرئيسية';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get newPassword => 'كلمة المرور الجديدة';

  @override
  String get passwordChanged => 'تم تغيير كلمة المرور الرئيسية';

  @override
  String get lock => 'قفل';

  @override
  String get importExport => 'استيراد / تصدير';

  @override
  String get exportEncrypted => 'تصدير نسخة احتياطية مشفرة';

  @override
  String get importEncrypted => 'استيراد نسخة احتياطية مشفرة';

  @override
  String get importCsv => 'استيراد CSV (كروم / Bitwarden)';

  @override
  String get exportPassword => 'كلمة مرور التصدير';

  @override
  String imported(Object n, Object skipped) {
    return 'تم استيراد $n عنصر (تخطي $skipped)';
  }

  @override
  String get exported => 'تم حفظ النسخة الاحتياطية';

  @override
  String get csvWarning =>
      'احذف ملف CSV بعد الاستيراد: فهو يحتوي على كلمات المرور كنص واضح.';

  @override
  String get scanScreenshot => 'استيراد من لقطة شاشة';

  @override
  String get pickImage => 'اختيار صورة';

  @override
  String get takePhoto => 'التقاط صورة';

  @override
  String get ocrNoText => 'لم يُعثر على نص في الصورة';

  @override
  String get ocrTapChip =>
      'اضغط على أي جزء من النص لاستخدامه كاسم مستخدم أو كلمة مرور أو رابط أو اسم.';

  @override
  String get ocrUseAs => 'استخدم كـ…';

  @override
  String get ocrReview => 'راجع القيم المكتشفة قبل الحفظ';

  @override
  String get ocrAmbiguous => 'الأحرف المميزة سهلة الالتباس (0/O, l/I/1)';

  @override
  String get ocrChipsTitle => 'النص المكتشف';

  @override
  String ocrShowAll(int n) {
    return 'عرض الكل ($n)';
  }

  @override
  String get ocrAsUsername => 'اسم المستخدم';

  @override
  String get ocrAsPassword => 'كلمة المرور';

  @override
  String get ocrAsLink => 'رابط';

  @override
  String get ocrAsName => 'الاسم';

  @override
  String get ocrOtherReadings => 'قراءات أخرى';

  @override
  String get ocrPickHint =>
      'لم نتأكد أي نص هو البريد أو كلمة المرور. اضغط على جزء من النص أدناه لاستخدامه، أو اكتبه بنفسك.';

  @override
  String get ocrWhatWasRead => 'ما تمت قراءته';

  @override
  String get ocrWhatWasReadNote =>
      'النص الذي تعرّف عليه الماسح، محفوظ في الذاكرة فقط. يساعد على معرفة سبب فوات بيانات الدخول.';

  @override
  String ocrPassTitle(int n, Object name) {
    return 'المحاولة $n: $name';
  }

  @override
  String get ocrPassNothing => 'لم تتم قراءة شيء';

  @override
  String ocrPassFailed(Object reason) {
    return 'فشلت ($reason)';
  }

  @override
  String get ocrTipsTitle => 'نصائح';

  @override
  String get ocrTipCrop =>
      'انسخ مساحة أكبر: اترك بعض الفراغ حول البريد وكلمة المرور.';

  @override
  String get ocrTipVisible =>
      'تأكد أن النص واضح على الشاشة وغير مغطى أو ضبابي أو صغير جدًا.';

  @override
  String get ocrTipAgain =>
      'انسخ الصورة مرة أخرى ثم حاول من جديد. ويمكنك أيضًا نسخ النص نفسه بدل لقطة الشاشة.';

  @override
  String get ocrNoLanguageTitle => 'لا توجد لغة للتعرّف على النص في Windows';

  @override
  String get ocrNoLanguageBody =>
      'يقرأ Windows النص داخل الصور بحزمة لغة للتعرّف الضوئي على الحروف، ولا توجد أي حزمة مثبتة. لإضافة واحدة:';

  @override
  String get ocrNoLanguageStep1 =>
      'افتح الإعدادات > الوقت واللغة > اللغة والمنطقة.';

  @override
  String get ocrNoLanguageStep2 =>
      'اختر إضافة لغة ثم اختر واحدة (الإنجليزية تقرأ عناوين البريد وكلمات المرور جيدًا).';

  @override
  String get ocrNoLanguageStep3 =>
      'تأكد من تفعيل التعرّف الضوئي على الحروف (Optical character recognition) أثناء التثبيت.';

  @override
  String get ocrNoLanguageStep4 => 'ارجع إلى هنا والصق من جديد.';

  @override
  String get ocrTooLargeTitle => 'الصورة أكبر من أن تُفحص';

  @override
  String get ocrTooLargeBody =>
      'انسخ أو اقتص مساحة أصغر حول البريد وكلمة المرور ثم حاول من جديد.';

  @override
  String get ocrUnsupportedTitle => 'تعذرت قراءة هذه الصورة';

  @override
  String get ocrUnsupportedBody =>
      'انسخها مرة أخرى كلقطة شاشة عادية (PNG أو JPEG) وحاول من جديد.';

  @override
  String get ocrUnreadableTitle => 'تعذر فتح ملف الصورة';

  @override
  String get ocrUnreadableBody =>
      'ربما نُقل الملف أو حُذف. انسخ الصورة مرة أخرى وحاول من جديد.';

  @override
  String get ocrTimeoutTitle => 'استغرق الفحص وقتًا طويلًا';

  @override
  String get ocrTimeoutBody =>
      'تم إيقاف الفحص. انسخ مساحة أصغر حول البريد وكلمة المرور وحاول من جديد.';

  @override
  String get ocrFailedTitle => 'فشل التعرّف على النص';

  @override
  String get ocrFailedBody =>
      'حدث خطأ أثناء قراءة الصورة. حاول من جديد، أو انسخ مساحة أكبر.';

  @override
  String get ocrPasteAgain => 'لصق من جديد';

  @override
  String get ocrFillByHand => 'ملء يدويًا';

  @override
  String get deleteSourceImage => 'حذف الصورة الأصلية؟';

  @override
  String get deleteSourceImageBody =>
      'تحتوي لقطة الشاشة على كلمة المرور كنص واضح. قد تكون النسخ الاحتياطية السحابية قد حفظت نسخة بالفعل.';

  @override
  String get keep => 'إبقاء';

  @override
  String get imageDeleted => 'تم حذف الصورة';

  @override
  String get securityDashboard => 'لوحة الأمان';

  @override
  String get weakPasswords => 'كلمات مرور ضعيفة';

  @override
  String get reusedPasswords => 'كلمات مرور مكررة';

  @override
  String get oldPasswords => 'كلمات مرور قديمة (> سنة)';

  @override
  String get breachedPasswords => 'موجودة في تسريبات';

  @override
  String get checkBreaches => 'فحص التسريبات';

  @override
  String get hibpExplain =>
      'يُرسل فقط أول 5 أحرف من بصمة SHA-1 لكل كلمة مرور إلى Have I Been Pwned. لا تغادر كلمات المرور جهازك أبدًا.';

  @override
  String get allGood => 'لا شيء يحتاج إصلاح';

  @override
  String get sync => 'المزامنة';

  @override
  String get syncNow => 'زامن الآن';

  @override
  String get enableSync => 'تفعيل المزامنة';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String syncEnabled(Object email) {
    return 'متزامن كـ $email';
  }

  @override
  String get syncFailed => 'فشلت المزامنة';

  @override
  String lastSynced(Object time) {
    return 'آخر مزامنة $time';
  }

  @override
  String get signOut => 'الخروج من المزامنة';

  @override
  String get quickSearch => 'بحث سريع';

  @override
  String get error => 'حدث خطأ ما';

  @override
  String get close => 'إغلاق';

  @override
  String get ok => 'حسنًا';

  @override
  String get pasteLogin => 'لصق بيانات دخول';

  @override
  String get pasteNothingFound =>
      'لم يُعثر على بيانات دخول في الحافظة. انسخ أولًا لقطة شاشة أو نصًا يحتوي على البريد وكلمة المرور.';

  @override
  String get saveLogin => 'حفظ بيانات الدخول';

  @override
  String get quickMode => 'سريع';

  @override
  String get advancedMode => 'متقدم';

  @override
  String get name => 'الاسم';

  @override
  String get whereFrom => 'من أين هو؟ (رابط)';

  @override
  String get whyNotes => 'لماذا / ملاحظات';

  @override
  String get clearScreenshotTitle => 'مسح لقطة الشاشة من الحافظة؟';

  @override
  String get clearTextTitle => 'مسح النص المنسوخ من الحافظة؟';

  @override
  String get clearClipboardBody =>
      'ما زالت تُظهر كلمة المرور هذه، ويمكن للتطبيقات الأخرى قراءتها. المسح لا يحذف النسخ المحفوظة مسبقًا في سجل الحافظة (Windows + V أو تطبيق لوحة المفاتيح)؛ احذفها من هناك.';

  @override
  String get clear => 'مسح';

  @override
  String get clipboardCleared => 'تم مسح الحافظة';

  @override
  String get fetchIcons => 'جلب أيقونات المواقع';

  @override
  String get fetchIconsNote =>
      'تُنزَّل الأيقونات مباشرةً من كل موقع، لذا يرى الموقع عنوان IP الخاص بك.';

  @override
  String get reviewImport => 'مراجعة الاستيراد';

  @override
  String importFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n حساب في الملف',
      many: '$n حسابًا في الملف',
      few: '$n حسابات في الملف',
      two: 'حسابان في الملف',
      one: 'حساب واحد في الملف',
      zero: 'لا توجد حسابات في الملف',
    );
    return '$_temp0';
  }

  @override
  String importSkippedRows(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'تم تخطي $n صف (فارغة أو ليست بيانات دخول)',
      many: 'تم تخطي $n صفًا (فارغة أو ليست بيانات دخول)',
      few: 'تم تخطي $n صفوف (فارغة أو ليست بيانات دخول)',
      two: 'تم تخطي صفين (فارغين أو ليسا بيانات دخول)',
      one: 'تم تخطي صف واحد (فارغ أو ليس بيانات دخول)',
    );
    return '$_temp0';
  }

  @override
  String get importReviewHint =>
      'تُستورد الحسابات المحددة فقط. اضغط على أي حساب لتصحيحه.';

  @override
  String importN(int n) {
    return 'استيراد $n';
  }

  @override
  String get noWebsite => 'بدون موقع';

  @override
  String get noUsername => '(بدون اسم مستخدم)';

  @override
  String get reviewNew => 'جديد';

  @override
  String get reviewUpdate => 'تحديث';

  @override
  String get reviewMerged => 'تكرارات مدمجة';

  @override
  String get reviewSkip => 'محفوظ مسبقًا';

  @override
  String get reviewAttention => 'يحتاج إلى مراجعة';

  @override
  String reviewUpdates(Object title) {
    return 'يستبدل كلمة مرور «$title»، وتبقى القديمة في سجله';
  }

  @override
  String get issueMissingPassword => 'بدون كلمة مرور';

  @override
  String get issueMissingUsername => 'بدون اسم مستخدم';

  @override
  String get issueInvalidEmail => 'البريد يبدو غير صحيح';

  @override
  String get issueUsernameIsUrl => 'اسم المستخدم رابط';

  @override
  String get issuePasswordLooksLikeEmail =>
      'كلمة المرور تشبه بريدًا إلكترونيًا';

  @override
  String get issueUsernameLooksLikePassword => 'اسم المستخدم يشبه كلمة مرور';

  @override
  String get issueInvalidUrl => 'لا يوجد موقع صالح';

  @override
  String get issueInsecureHttp => 'غير آمن (http)';

  @override
  String get issueDuplicateInFile => 'مكرر في الملف';

  @override
  String get issueExistsWithDifferentPassword => 'محفوظ بكلمة مرور أخرى';

  @override
  String get editLogin => 'تعديل بيانات الدخول';

  @override
  String get swapUserPassword => 'تبديل اسم المستخدم وكلمة المرور';

  @override
  String get deleteCsvTitle => 'احذف ملف CSV الآن';

  @override
  String get deleteCsvBody =>
      'يحتوي على جميع كلمات المرور كنص واضح. احذفه من مجلد التنزيلات، وأفرغ سلة المحذوفات، واحذف أي نسخة منه في التخزين السحابي أو البريد.';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get forgotPasswordTitle => 'نسيت كلمة المرور الرئيسية؟';

  @override
  String get forgotPasswordBody =>
      'لا يمكن لأحد استعادتها، ولا حتى مطوّر VaultSnap. فهي لا تُحفظ ولا تُرسل إلى أي مكان، وخزنتك مشفرة بها.';

  @override
  String get useRecoveryKeyExplain =>
      'افتح الخزنة بمفتاح الاسترداد الذي حفظته عند إنشائها، ثم اختر كلمة مرور جديدة.';

  @override
  String get resetVault => 'إعادة تعيين الخزنة — مسح كل شيء';

  @override
  String get resetVaultExplain =>
      'ابدأ من جديد بخزنة فارغة. سيضيع كل ما هو محفوظ في هذه الخزنة.';

  @override
  String get resetVaultTitle => 'مسح هذه الخزنة؟';

  @override
  String get resetVaultBody =>
      'سيؤدي هذا إلى حذف كل كلمات المرور والملاحظات في الخزنة على هذا الجهاز نهائيًا. لا يمكن التراجع عن ذلك.';

  @override
  String get resetConfirmWord => 'حذف';

  @override
  String resetTypeToConfirm(Object word) {
    return 'اكتب «$word» للتأكيد';
  }

  @override
  String get eraseVault => 'مسح الخزنة';
}
