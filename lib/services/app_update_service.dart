import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'google_drive_service.dart';

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.fileId,
    required this.fileName,
    required this.versionLabel,
    required this.versionParts,
    this.sizeBytes,
  });

  final String fileId;
  final String fileName;
  final String versionLabel;
  final List<int> versionParts;
  final int? sizeBytes;
}

class AppUpdateService {
  AppUpdateService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  static const _apkMime = 'application/vnd.android.package-archive';
  static final RegExp _apkNamePattern = RegExp(
    r'^edupal\s+v(\d+(?:\.\d+)*)\.apk$',
    caseSensitive: false,
  );

  static String get _downloadApiKey {
    final key = dotenv.env['GOOGLE_DRIVE_DOWNLOAD_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw StateError('GOOGLE_DRIVE_DOWNLOAD_API_KEY is missing from .env');
    }
    return key;
  }

  static List<int>? parseVersionParts(String name) {
    final trimmed = name.trim();
    final apkMatch = _apkNamePattern.firstMatch(trimmed);
    final versionText = apkMatch?.group(1);
    if (versionText != null) {
      return _splitVersion(versionText);
    }

    final labelMatch = RegExp(
      r'^edupal\s+v(\d+(?:\.\d+)*)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (labelMatch != null) {
      return _splitVersion(labelMatch.group(1)!);
    }
    return null;
  }

  static List<int> _splitVersion(String versionText) {
    return versionText.split('.').map(int.parse).toList();
  }

  static int compareVersions(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  /// Returns the newest Drive APK that is newer than this build, or null.
  /// Network / missing-folder failures return null so the app stays usable.
  static Future<AppUpdateRelease?> findRequiredUpdate(String currentLabel) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final currentParts = parseVersionParts(currentLabel);
    if (currentParts == null) {
      debugPrint('App update: invalid hardcoded version "$currentLabel"');
      return null;
    }

    try {
      final folderId = await _updatesFolderId();
      if (folderId == null || folderId.isEmpty) return null;

      final items = await GoogleDriveService.getFolderContents(folderId);
      AppUpdateRelease? newest;
      for (final item in items) {
        if (item.isFolder) continue;
        final parts = parseVersionParts(item.name);
        if (parts == null) continue;

        final release = AppUpdateRelease(
          fileId: item.id,
          fileName: item.name,
          versionLabel: _labelFromApkName(item.name),
          versionParts: parts,
          sizeBytes: int.tryParse(item.size ?? ''),
        );
        if (newest == null ||
            compareVersions(release.versionParts, newest.versionParts) > 0) {
          newest = release;
        }
      }

      if (newest == null) return null;
      if (compareVersions(newest.versionParts, currentParts) <= 0) return null;
      return newest;
    } catch (e) {
      debugPrint('App update check failed: $e');
      return null;
    }
  }

  static String _labelFromApkName(String fileName) {
    final withoutExt = fileName.replaceAll(RegExp(r'\.apk$', caseSensitive: false), '');
    return withoutExt.trim();
  }

  static Future<String?> _updatesFolderId() async {
    final firestore = FirebaseFirestore.instance;
    final refs = [
      firestore.collection('config').doc('googleDriveFolders'),
      firestore.collection('courses').doc('engineering'),
    ];
    for (final ref in refs) {
      try {
        final doc = await ref.get();
        final id = doc.data()?['updatesFolderId'];
        if (id is String && id.trim().isNotEmpty) return id.trim();
      } catch (e) {
        debugPrint('App update: could not read ${ref.path}: $e');
      }
    }
    return null;
  }

  static Future<File> downloadApk(
    AppUpdateRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = release.fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final dest = File('${dir.path}/$safeName');
    if (await dest.exists()) {
      await dest.delete();
    }

    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${release.fileId}',
      {
        'alt': 'media',
        'key': _downloadApiKey,
        'supportsAllDrives': 'true',
      },
    );

    await _dio.download(
      uri.toString(),
      dest.path,
      onReceiveProgress: (received, total) {
        if (onProgress == null) return;
        if (total > 0) {
          onProgress(received / total);
        } else {
          onProgress(0);
        }
      },
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) => status == 200,
        headers: const {'Accept': '*/*'},
      ),
    );

    if (!await dest.exists() || await dest.length() < 1024) {
      if (await dest.exists()) await dest.delete();
      throw Exception('The APK download was incomplete. Try again.');
    }

    return dest;
  }

  static Future<void> installApk(File apkFile) async {
    if (!Platform.isAndroid) {
      throw Exception('APK updates are only supported on Android.');
    }

    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) {
      throw Exception(
        'Allow Edupal to install apps, then tap Update again.',
      );
    }

    final result = await OpenFile.open(apkFile.path, type: _apkMime);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
