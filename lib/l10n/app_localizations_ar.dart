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
      'اضغط على أي عنصر لنسخه؛ اضغط مطولاً لاستخدامه في حقل';

  @override
  String get ocrUseAs => 'استخدم كـ…';

  @override
  String get ocrReview => 'راجع القيم المكتشفة قبل الحفظ';

  @override
  String get ocrAmbiguous => 'الأحرف المميزة سهلة الالتباس (0/O, l/I/1)';

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
}
