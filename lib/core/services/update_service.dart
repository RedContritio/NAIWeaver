import 'package:dio/dio.dart';

/// A single downloadable asset attached to a GitHub release.
class UpdateAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });
}

class UpdateCheckResult {
  final bool updateAvailable;
  final String? latestVersion;
  final String? releaseUrl;
  final String? error;

  /// All assets attached to the latest release (empty if the check failed or no
  /// update is available). Used by the downloader to pick the right APK/ZIP.
  final List<UpdateAsset> assets;

  const UpdateCheckResult({
    required this.updateAvailable,
    this.latestVersion,
    this.releaseUrl,
    this.error,
    this.assets = const [],
  });
}

class UpdateService {
  static const _repoApiUrl =
      'https://api.github.com/repos/ststoryweaver/NAIWeaver/releases/latest';

  static Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        _repoApiUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final assets = _parseAssets(data['assets']);

      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (_isNewerVersion(currentVersion, latestVersion)) {
        return UpdateCheckResult(
          updateAvailable: true,
          latestVersion: latestVersion,
          releaseUrl: htmlUrl,
          assets: assets,
        );
      }

      return const UpdateCheckResult(updateAvailable: false);
    } on DioException catch (e) {
      return UpdateCheckResult(
        updateAvailable: false,
        error: e.message ?? 'Network error',
      );
    } catch (e) {
      return UpdateCheckResult(
        updateAvailable: false,
        error: e.toString(),
      );
    }
  }

  static List<UpdateAsset> _parseAssets(dynamic raw) {
    if (raw is! List) return const [];
    final result = <UpdateAsset>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name'] as String?;
      final url = entry['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      result.add(UpdateAsset(
        name: name,
        downloadUrl: url,
        size: (entry['size'] as num?)?.toInt() ?? 0,
        contentType: entry['content_type'] as String? ?? '',
      ));
    }
    return result;
  }

  /// Picks the release asset matching this platform + locale.
  ///
  /// Release assets follow `NAIWeaver[-<locale>]<suffix>`, where the EN build
  /// carries no locale token (e.g. `NAIWeaver.apk`, `NAIWeaver-ja.apk`,
  /// `NAIWeaver-zh.zip`). Selection order:
  ///   1. Keep only assets ending in [platformSuffix] (e.g. `.apk`, `.zip`).
  ///   2. Prefer an asset whose locale token equals [localeCode]. The absence of
  ///      a token counts as `en`.
  ///   3. If the requested locale isn't `en` and has no asset, fall back to the
  ///      untagged (EN/default) asset.
  ///   4. Last resort: the first platform-matching asset.
  /// Returns null if no asset matches the platform at all (caller should then
  /// fall back to opening the release page in a browser).
  static UpdateAsset? selectAsset(
    List<UpdateAsset> assets, {
    required String platformSuffix,
    required String localeCode,
  }) {
    final suffix = platformSuffix.toLowerCase();
    final platformAssets = assets
        .where((a) => a.name.toLowerCase().endsWith(suffix))
        .toList();
    if (platformAssets.isEmpty) return null;

    final wantLocale = localeCode.toLowerCase();

    UpdateAsset? exactLocale;
    UpdateAsset? defaultLocale;
    for (final asset in platformAssets) {
      final loc = _localeTokenOf(asset.name, suffix); // '' == default (en)
      if (loc == wantLocale || (loc.isEmpty && wantLocale == 'en')) {
        exactLocale = asset;
      }
      if (loc.isEmpty) {
        defaultLocale = asset;
      }
    }

    return exactLocale ?? defaultLocale ?? platformAssets.first;
  }

  /// Extracts the 2-letter locale token from an asset name, or '' if the asset
  /// is the untagged default build. e.g. `NAIWeaver-ja.apk` -> `ja`,
  /// `NAIWeaver.apk` -> ``.
  static String _localeTokenOf(String name, String suffix) {
    final lower = name.toLowerCase();
    // Strip the platform suffix, then look for a trailing `-xx` token.
    final base = lower.substring(0, lower.length - suffix.length);
    final match = RegExp(r'-([a-z]{2})$').firstMatch(base);
    return match?.group(1) ?? '';
  }

  static bool _isNewerVersion(String current, String latest) {
    final currentParts = _parseVersion(current);
    final latestParts = _parseVersion(latest);

    for (var i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) {
      if (i < parts.length) {
        return int.tryParse(parts[i]) ?? 0;
      }
      return 0;
    });
  }
}
