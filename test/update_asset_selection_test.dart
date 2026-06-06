import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/update_service.dart';

/// The real asset set published on a NAIWeaver GitHub release (see v0.9.0):
/// per-locale Android APK, Windows ZIP, and Linux AppImage. EN carries no
/// locale token; ja/zh do.
List<UpdateAsset> _fullReleaseAssets() => const [
      UpdateAsset(name: 'NAIWeaver.apk', downloadUrl: 'u', size: 1, contentType: 'application/vnd.android.package-archive'),
      UpdateAsset(name: 'NAIWeaver-ja.apk', downloadUrl: 'u', size: 1, contentType: 'application/vnd.android.package-archive'),
      UpdateAsset(name: 'NAIWeaver-zh.apk', downloadUrl: 'u', size: 1, contentType: 'application/vnd.android.package-archive'),
      UpdateAsset(name: 'NAIWeaver.zip', downloadUrl: 'u', size: 1, contentType: 'application/zip'),
      UpdateAsset(name: 'NAIWeaver-ja.zip', downloadUrl: 'u', size: 1, contentType: 'application/zip'),
      UpdateAsset(name: 'NAIWeaver-zh.zip', downloadUrl: 'u', size: 1, contentType: 'application/zip'),
      UpdateAsset(name: 'NAIWeaver-x86_64.AppImage', downloadUrl: 'u', size: 1, contentType: 'application/octet-stream'),
      UpdateAsset(name: 'NAIWeaver-ja-x86_64.AppImage', downloadUrl: 'u', size: 1, contentType: 'application/octet-stream'),
      UpdateAsset(name: 'NAIWeaver-zh-x86_64.AppImage', downloadUrl: 'u', size: 1, contentType: 'application/octet-stream'),
    ];

void main() {
  group('UpdateService.selectAsset', () {
    test('Android picks the locale-correct APK', () {
      final assets = _fullReleaseAssets();
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'en')?.name,
        'NAIWeaver.apk',
      );
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'ja')?.name,
        'NAIWeaver-ja.apk',
      );
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'zh')?.name,
        'NAIWeaver-zh.apk',
      );
    });

    test('Windows picks the locale-correct ZIP', () {
      final assets = _fullReleaseAssets();
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.zip', localeCode: 'en')?.name,
        'NAIWeaver.zip',
      );
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.zip', localeCode: 'ja')?.name,
        'NAIWeaver-ja.zip',
      );
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.zip', localeCode: 'zh')?.name,
        'NAIWeaver-zh.zip',
      );
    });

    test('the .zip selector never returns an AppImage (suffix is exact)', () {
      final assets = _fullReleaseAssets();
      final picked = UpdateService.selectAsset(assets, platformSuffix: '.zip', localeCode: 'en');
      expect(picked, isNotNull);
      expect(picked!.name.endsWith('.zip'), isTrue);
    });

    test('falls back to the untagged (EN) asset when the locale build is absent', () {
      const assets = [
        UpdateAsset(name: 'NAIWeaver.apk', downloadUrl: 'u', size: 1, contentType: ''),
        UpdateAsset(name: 'NAIWeaver-ja.apk', downloadUrl: 'u', size: 1, contentType: ''),
      ];
      // zh has no dedicated APK -> fall back to the default NAIWeaver.apk.
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'zh')?.name,
        'NAIWeaver.apk',
      );
    });

    test('last-resort: returns a platform asset even with no default build', () {
      const assets = [
        UpdateAsset(name: 'NAIWeaver-ja.apk', downloadUrl: 'u', size: 1, contentType: ''),
        UpdateAsset(name: 'NAIWeaver-zh.apk', downloadUrl: 'u', size: 1, contentType: ''),
      ];
      // en requested, no untagged build, no -en build -> first platform asset.
      final picked = UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'en');
      expect(picked, isNotNull);
      expect(picked!.name.endsWith('.apk'), isTrue);
    });

    test('returns null when no asset matches the platform', () {
      const assets = [
        UpdateAsset(name: 'NAIWeaver.apk', downloadUrl: 'u', size: 1, contentType: ''),
      ];
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.zip', localeCode: 'en'),
        isNull,
      );
      expect(UpdateService.selectAsset(const [], platformSuffix: '.apk', localeCode: 'en'), isNull);
    });

    test('matching is case-insensitive on the suffix', () {
      const assets = [
        UpdateAsset(name: 'NAIWeaver.APK', downloadUrl: 'u', size: 1, contentType: ''),
      ];
      expect(
        UpdateService.selectAsset(assets, platformSuffix: '.apk', localeCode: 'en')?.name,
        'NAIWeaver.APK',
      );
    });
  });
}
