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

  group('UpdateService.isTrustedDownloadHost', () {
    test('accepts GitHub release + CDN hosts over https', () {
      expect(UpdateService.isTrustedDownloadHost(
          'https://github.com/ststoryweaver/NAIWeaver/releases/download/v1/NAIWeaver.apk'),
          isTrue);
      expect(UpdateService.isTrustedDownloadHost(
          'https://objects.githubusercontent.com/abc/NAIWeaver.zip'),
          isTrue);
      expect(UpdateService.isTrustedDownloadHost(
          'https://api.github.com/foo'),
          isTrue);
    });

    test('rejects non-GitHub hosts, http, and lookalike domains', () {
      // Off-domain host — the core anti-redirect protection.
      expect(UpdateService.isTrustedDownloadHost('https://evil.com/NAIWeaver.apk'), isFalse);
      // Plain http (no TLS).
      expect(UpdateService.isTrustedDownloadHost('http://github.com/x.apk'), isFalse);
      // Lookalike that merely contains the trusted host as a substring.
      expect(UpdateService.isTrustedDownloadHost('https://github.com.evil.com/x.apk'), isFalse);
      expect(UpdateService.isTrustedDownloadHost('https://notgithub.com/x.apk'), isFalse);
      expect(UpdateService.isTrustedDownloadHost('not a url'), isFalse);
    });
  });

  group('UpdateService.parseSha256', () {
    test('extracts the lower-cased hex from a sha256: digest', () {
      final hex = 'A' * 64;
      expect(UpdateService.parseSha256('sha256:$hex'), 'a' * 64);
    });

    test('returns null for absent, wrong-algorithm, or malformed digests', () {
      expect(UpdateService.parseSha256(null), isNull);
      expect(UpdateService.parseSha256(123), isNull);
      expect(UpdateService.parseSha256('sha1:${'a' * 40}'), isNull);
      expect(UpdateService.parseSha256('sha256:tooshort'), isNull);
      expect(UpdateService.parseSha256('sha256:${'g' * 64}'), isNull); // non-hex
      expect(UpdateService.parseSha256('a' * 64), isNull); // no prefix
    });
  });
}
