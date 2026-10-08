import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/l10n/app_localizations_ar.dart';
import 'package:hisn/l10n/app_localizations_en.dart';
import 'package:hisn/services/update/update_failure.dart';
import 'package:hisn/ui/update/update_format.dart';
import 'package:hisn/ui/update/update_messages.dart';

/// What the update UI writes: sizes, dates, percentages, and the plain-language
/// text for every kind of failure, in both languages.
void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  group('formatting', () {
    test('sizes: KB below a megabyte, one decimal up to 100 MB', () {
      expect(formatUpdateSize(en, 1), '1 KB');
      expect(formatUpdateSize(en, 500 * 1024), '500 KB');
      expect(formatUpdateSize(en, 1024 * 1024), '1.0 MB');
      expect(formatUpdateSize(en, (42.04 * 1024 * 1024).round()), '42.0 MB');
      expect(formatUpdateSize(en, 150 * 1024 * 1024), '150 MB');
    });

    test('sizes in Arabic: the unit changes, the digits stay Western', () {
      expect(formatUpdateSize(ar, 42 * 1024 * 1024), '42.0 ميغابايت');
      expect(formatUpdateSize(ar, 900 * 1024), '900 كيلوبايت');
    });

    test('percent rounds down and stays in 0..100', () {
      expect(updatePercent(0.499), 49);
      expect(updatePercent(1), 100);
      expect(updatePercent(null), 0);
      expect(updatePercent(2), 100);
      expect(updatePercent(-1), 0);
    });

    test('dates and times: the same order in both languages', () {
      expect(formatUpdateDate(DateTime.utc(2026, 1, 5)), '2026-01-05');
      expect(formatUpdateStamp(DateTime(2026, 1, 5, 7, 3)), '2026-01-05 07:03');
    });

    test('values are isolated left to right', () {
      expect(isolateLtr('1.2.3'), '\u{2066}1.2.3\u{2069}');
      expect(
        formatUpdateVersion(en, '0.2.0', 2000),
        '\u{2066}0.2.0\u{2069} (build \u{2066}2000\u{2069})',
      );
    });
  });

  group('failure texts', () {
    for (final reason in UpdateFailure.values) {
      test('$reason has a message in both languages', () {
        for (final l in [en, ar]) {
          final t = describeUpdateFailure(l, reason);
          expect(t.title, isNotEmpty);
          expect(t.body.length, greaterThan(20));
          // Plain language only: no enum name, URL, path or code.
          expect(t.body, isNot(contains(reason.name)));
          expect(t.body, isNot(contains('http')));
          expect(t.body, isNot(contains('/')));
          expect(t.body, isNot(contains('0x')));
        }
      });
    }

    test('a bad signature is "rejected for your safety" and not retryable', () {
      final t = describeUpdateFailure(en, UpdateFailure.signatureInvalid);
      expect(t.title, 'Update rejected for your safety');
      expect(t.rejected, isTrue);
      expect(t.canRetry, isFalse);
      final a = describeUpdateFailure(ar, UpdateFailure.signatureInvalid);
      expect(a.title, 'رُفض التحديث حفاظًا على سلامتك');
    });

    test('a replayed older release is rejected too', () {
      final t = describeUpdateFailure(en, UpdateFailure.rollback);
      expect(t.rejected, isTrue);
      expect(t.canRetry, isFalse);
    });

    test('connection problems can be retried', () {
      for (final r in [
        UpdateFailure.network,
        UpdateFailure.timeout,
        UpdateFailure.badStatus,
        UpdateFailure.storage,
        UpdateFailure.hashMismatch,
        UpdateFailure.truncated,
      ]) {
        expect(describeUpdateFailure(en, r).canRetry, isTrue, reason: '$r');
      }
    });

    test('blocked downloads are never retried blindly', () {
      for (final r in [
        UpdateFailure.hostNotAllowed,
        UpdateFailure.insecureUrl,
        UpdateFailure.tooManyRedirects,
      ]) {
        final t = describeUpdateFailure(en, r);
        expect(t.canRetry, isFalse, reason: '$r');
        expect(t.rejected, isTrue, reason: '$r');
      }
    });

    test('an unreadable release points to the release page', () {
      expect(
        describeUpdateFailure(
          en,
          UpdateFailure.unsupportedSchema,
        ).offerReleasePage,
        isTrue,
      );
    });
  });
}
