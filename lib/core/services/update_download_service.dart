import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

/// Phases of an in-flight update, surfaced to the progress UI.
enum UpdatePhase { downloading, extracting, installing, done, error }

/// Progress callback: [fraction] is 0..1 (or null when indeterminate), with the
/// raw byte counts for a human-readable "X / Y MB" readout.
typedef UpdateProgress = void Function(
    UpdatePhase phase, double? fraction, int received, int total);

class UpdateDownloadException implements Exception {
  final String message;
  UpdateDownloadException(this.message);
  @override
  String toString() => message;
}

/// Downloads a release asset and applies it per-platform:
///  - Android: download the APK to app-external storage, then hand it to the
///    system package-installer (the user taps Install).
///  - Windows: download the ZIP, then launch a detached PowerShell helper that
///    waits for this app to exit, extracts over the install dir, and relaunches.
///
/// Pure service (no Flutter imports) so it stays unit-testable and platform code
/// is isolated behind [Platform] checks.
class UpdateDownloadService {
  final Dio _dio;
  UpdateDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// The file-extension suffix to match against release assets for the current
  /// platform, or null if auto-update isn't supported here.
  static String? get platformAssetSuffix {
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '.zip';
    return null;
  }

  /// Whether the in-app updater can apply (not just point at) an update here.
  static bool get isSupported => platformAssetSuffix != null;

  /// Downloads [asset] to a platform-appropriate location, reporting progress.
  /// Throws [UpdateDownloadException] on failure or [DioException] on cancel.
  Future<File> downloadAsset(
    UpdateAsset asset, {
    required UpdateProgress onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _downloadDir();
    final dest = File(p.join(dir.path, asset.name));
    // Clear any stale partial from a previous attempt.
    if (await dest.exists()) {
      try {
        await dest.delete();
      } catch (_) {}
    }

    onProgress(UpdatePhase.downloading, asset.size > 0 ? 0 : null, 0, asset.size);
    try {
      await _dio.download(
        asset.downloadUrl,
        dest.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final t = total > 0 ? total : asset.size;
          final frac = t > 0 ? received / t : null;
          onProgress(UpdatePhase.downloading, frac, received, t);
        },
      );
    } on DioException {
      await _safeDelete(dest);
      rethrow;
    } catch (e) {
      await _safeDelete(dest);
      throw UpdateDownloadException(e.toString());
    }

    // Sanity-check the size if the API gave us one — a truncated download would
    // otherwise fail confusingly at install time.
    if (asset.size > 0) {
      final got = await dest.length();
      if (got != asset.size) {
        await _safeDelete(dest);
        throw UpdateDownloadException(
            'Downloaded size ($got) does not match expected (${asset.size}).');
      }
    }
    return dest;
  }

  /// Android: launch the system installer for [apk]. The OS shows the
  /// "install / allow from this source" flow; we don't block on the result.
  Future<void> installAndroidApk(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw UpdateDownloadException(
          'Could not launch the installer: ${result.message}');
    }
  }

  /// Windows: stage a detached helper that waits for this process to exit, swaps
  /// the install dir's files with the contents of [zip], and relaunches. The
  /// caller must then close the app (e.g. via window_manager) so the helper can
  /// proceed. Returns once the helper is launched.
  Future<void> launchWindowsUpdater(File zip) async {
    final installDir = p.dirname(Platform.resolvedExecutable);
    final exeName = p.basename(Platform.resolvedExecutable);
    final procId = pid; // dart:io current process id

    final tmp = await getTemporaryDirectory();
    final scriptPath = p.join(tmp.path, 'naiweaver_update.ps1');
    await File(scriptPath).writeAsString(_windowsUpdaterScript());

    final result = await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', scriptPath,
        '-ZipPath', zip.path,
        '-InstallDir', installDir,
        '-ExeName', exeName,
        '-ProcId', '$procId',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    // Detached: we don't await the process. Touch it so the analyzer is happy
    // and to surface an obvious launch failure.
    if (result.pid <= 0) {
      throw UpdateDownloadException('Failed to launch the Windows updater.');
    }
  }

  Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      // App-external files dir is always writable (incl. Android 11+ scoped
      // storage) and is covered by open_filex's bundled FileProvider, so the
      // installer can read the APK without a custom provider.
      final ext = await getExternalStorageDirectory();
      final base = ext ?? await getApplicationSupportDirectory();
      final updates = Directory(p.join(base.path, 'updates'));
      await updates.create(recursive: true);
      return updates;
    }
    // Windows: temp dir is fine; the helper copies out of the extracted zip.
    return getTemporaryDirectory();
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// The self-replace helper. Runs independently of the dying app: waits for the
  /// app's PID to exit, extracts the zip, copies over the install dir, relaunches,
  /// and cleans up. Logs to %TEMP%\naiweaver-update.log for post-mortem since the
  /// app is gone by the time it runs. Elevates if the install dir isn't writable
  /// (e.g. a Program Files install).
  String _windowsUpdaterScript() => r'''
param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$ExeName,
  [Parameter(Mandatory=$true)][int]$ProcId
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'naiweaver-update.log'
function Log($m) { ("[{0}] {1}" -f (Get-Date -Format o), $m) | Out-File -FilePath $log -Append -Encoding utf8 }

try {
  Log "Updater started. Zip=$ZipPath InstallDir=$InstallDir Exe=$ExeName Pid=$ProcId"

  # 1. Wait for the app to fully exit and release its file locks.
  try { Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue } catch {}
  for ($i = 0; $i -lt 50; $i++) {
    if (-not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 200
  }
  Start-Sleep -Milliseconds 500  # grace for child handles (onnx/audio) to release

  # 2. If the install dir isn't writable, re-launch elevated and exit.
  $probe = Join-Path $InstallDir ('.upd_' + [System.Guid]::NewGuid().ToString('N'))
  $writable = $true
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item $probe -Force }
  catch { $writable = $false }
  if (-not $writable) {
    Log "Install dir not writable; relaunching elevated."
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$PSCommandPath,
              '-ZipPath',$ZipPath,'-InstallDir',$InstallDir,'-ExeName',$ExeName,'-ProcId',$ProcId)
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    return
  }

  # 3. Extract to a staging dir.
  $stage = Join-Path $env:TEMP ('naiweaver-update-' + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  Log "Extracting to $stage"
  Expand-Archive -Path $ZipPath -DestinationPath $stage -Force

  # 4. Find the payload root. The release zip wraps the build output in a single
  #    top-level folder; if there's exactly one dir and no exe at the top, descend.
  $payload = $stage
  $topExe = Join-Path $stage $ExeName
  if (-not (Test-Path $topExe)) {
    $dirs = @(Get-ChildItem -Path $stage -Directory)
    $files = @(Get-ChildItem -Path $stage -File)
    if ($dirs.Count -eq 1 -and $files.Count -eq 0) { $payload = $dirs[0].FullName }
  }
  Log "Payload root: $payload"

  # 5. Copy over the install dir, retrying on transient locks. Not /MIR so we
  #    never delete anything the user keeps alongside the app.
  Log "Copying into $InstallDir"
  robocopy $payload $InstallDir /E /IS /IT /R:5 /W:1 | Out-Null
  $rc = $LASTEXITCODE
  Log "robocopy exit code $rc"
  if ($rc -ge 8) { throw "robocopy failed with code $rc" }

  # 6. Relaunch the updated app.
  $exePath = Join-Path $InstallDir $ExeName
  Log "Relaunching $exePath"
  Start-Process -FilePath $exePath -WorkingDirectory $InstallDir

  # 7. Clean up.
  try { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  Log "Update complete."
}
catch {
  Log ("ERROR: " + $_.Exception.Message)
}
finally {
  try { Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue } catch {}
}
''';
}
