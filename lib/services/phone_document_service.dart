import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class PhoneDocument {
  final String name;
  final String? path;
  final String? uri;
  final String mime;
  final int sizeBytes;
  final int modifiedMs;

  const PhoneDocument({
    required this.name,
    required this.path,
    required this.uri,
    required this.mime,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  String get key => path ?? uri ?? '$name:$sizeBytes:$modifiedMs';

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get kind {
    switch (extension) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return 'Word';
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return 'Excel';
      case 'ppt':
      case 'pptx':
      case 'odp':
        return 'PowerPoint';
      default:
        return 'Document';
    }
  }

  factory PhoneDocument.fromMap(Map<dynamic, dynamic> map) {
    return PhoneDocument(
      name: (map['name'] as String?) ?? 'Document',
      path: map['path'] as String?,
      uri: map['uri'] as String?,
      mime: (map['mime'] as String?) ?? 'application/octet-stream',
      sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      modifiedMs: (map['modifiedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class PhonePickedDocument {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const PhonePickedDocument({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.modifiedAt,
  });

  static DateTime? modifiedAtFromMs(int modifiedMs) {
    if (modifiedMs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(modifiedMs);
  }

  static bool looksLikeCopyTime(DateTime date) {
    return DateTime.now().difference(date).abs().inMinutes < 2;
  }

  static Future<PhonePickedDocument> fromFile({
    required String name,
    required String path,
    required int sizeBytes,
    String? uri,
    DateTime? modifiedAt,
  }) async {
    return PhonePickedDocument(
      name: name,
      path: path,
      sizeBytes: sizeBytes,
      modifiedAt: await PhoneDocumentService.instance.resolveModifiedAt(
        name: name,
        path: path,
        uri: uri,
        sizeBytes: sizeBytes,
        hint: modifiedAt,
      ),
    );
  }
}

class PhoneDocumentService {
  PhoneDocumentService._();

  static final PhoneDocumentService instance = PhoneDocumentService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.libview/phone_documents');

  static const List<String> imageUploadMimeTypes = ['image/*'];
  static const List<String> documentUploadMimeTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/rtf',
    'application/rtf',
    'text/csv',
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.oasis.opendocument.presentation',
  ];

  Future<List<PhonePickedDocument>> pickForUpload({
    required List<String> mimeTypes,
  }) async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'pickUploadFiles',
        {'mimeTypes': mimeTypes},
      );
      if (raw == null || raw.isEmpty) return const [];
      final picked = <PhonePickedDocument>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final path = map['path']?.toString() ?? '';
        final name = map['name']?.toString() ?? 'file';
        if (path.isEmpty) continue;
        final size = (map['sizeBytes'] as num?)?.toInt() ?? 0;
        final modifiedMs = (map['modifiedMs'] as num?)?.toInt() ?? 0;
        picked.add(
          PhonePickedDocument(
            name: name,
            path: path,
            sizeBytes: size,
            modifiedAt: PhonePickedDocument.modifiedAtFromMs(modifiedMs) ??
                await resolveModifiedAt(
                  name: name,
                  path: path,
                  uri: map['uri']?.toString(),
                  sizeBytes: size,
                ),
          ),
        );
      }
      return picked;
    } on PlatformException {
      return const [];
    }
  }

  Future<DateTime?> resolveModifiedAt({
    String? name,
    String? path,
    String? uri,
    int sizeBytes = 0,
    DateTime? hint,
  }) async {
    if (hint != null && !PhonePickedDocument.looksLikeCopyTime(hint)) {
      return hint;
    }

    if (Platform.isAndroid) {
      try {
        final ms = await _channel.invokeMethod<int>('resolveModifiedMs', {
          'uri': uri,
          'path': path,
          'fileName': name,
          'sizeBytes': sizeBytes,
        });
        final parsed = PhonePickedDocument.modifiedAtFromMs(ms ?? 0);
        if (parsed != null) return parsed;
      } catch (_) {}
    } else if (path != null && path.isNotEmpty) {
      try {
        final fromFile = await File(path).lastModified();
        if (!PhonePickedDocument.looksLikeCopyTime(fromFile)) {
          return fromFile;
        }
      } catch (_) {}
    }

    if (hint != null && !PhonePickedDocument.looksLikeCopyTime(hint)) {
      return hint;
    }
    return null;
  }

  Future<bool> requestAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final storage = await Permission.storage.request();
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    final manage = await Permission.manageExternalStorage.request();
    return manage.isGranted || storage.isGranted;
  }

  Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return Permission.manageExternalStorage.isGranted;
  }

  Future<List<PhoneDocument>> listDocuments() async {
    if (!Platform.isAndroid) {
      return const [];
    }

    final raw = await _channel.invokeMethod<List<dynamic>>('listDocuments');
    if (raw == null) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map(PhoneDocument.fromMap)
        .toList(growable: false);
  }

  final Map<String, String?> _thumbnailCache = {};

  static const _thumbnailExtensions = {
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'docx',
    'docm',
    'xlsx',
    'xlsm',
    'pptx',
    'pptm',
    'ppsx',
    'ppsm',
  };

  Future<String?> thumbnailPath(PhoneDocument document) {
    return thumbnailPathFor(
      key: document.key,
      fileName: document.name,
      path: document.path,
      uri: document.uri,
      modifiedMs: document.modifiedMs,
    );
  }

  Future<String?> thumbnailPathFor({
    required String key,
    required String fileName,
    String? path,
    String? uri,
    int modifiedMs = 0,
  }) async {
    if (_thumbnailCache.containsKey(key)) {
      return _thumbnailCache[key];
    }
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : '';
    if (!Platform.isAndroid || !_thumbnailExtensions.contains(ext)) {
      return null;
    }

    try {
      final thumb = await _channel.invokeMethod<String>('documentThumbnail', {
        'uri': uri,
        'path': path,
        'fileName': fileName,
        'modifiedMs': modifiedMs,
      });
      if (thumb == null || thumb.isEmpty) {
        return null;
      }
      _thumbnailCache[key] = thumb;
      return thumb;
    } catch (_) {
      return null;
    }
  }

  Future<void> openDocument(PhoneDocument document) async {
    if (!Platform.isAndroid) {
      final path = document.path;
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        throw Exception('Could not open this document');
      }
      final result = await OpenFile.open(path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      return;
    }

    try {
      await _channel.invokeMethod<bool>('openDocument', {
        'uri': document.uri,
        'path': document.path,
        'fileName': document.name,
        'mimeType': document.mime,
      });
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Could not open this document');
    }
  }

  /// Returns a path Flutter widgets can read. Copies from a content URI when needed.
  Future<String> copyToReadablePath({
    required String fileName,
    String? path,
    String? uri,
  }) async {
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final handle = await file.open();
          await handle.close();
          return path;
        } catch (_) {}
      }
    }

    if (!Platform.isAndroid) {
      throw Exception('Could not open this document');
    }

    try {
      final copied = await _channel.invokeMethod<String>('copyDocument', {
        'uri': uri,
        'path': path,
        'fileName': fileName,
      });
      if (copied == null || copied.isEmpty) {
        throw Exception('Could not open this document');
      }
      return copied;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Could not open this document');
    }
  }

  Future<void> openPath(String path, {String? fileName}) async {
    if (path.isEmpty || !File(path).existsSync()) {
      throw Exception('Could not open this document');
    }
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('openDocument', {
          'path': path,
          'fileName': fileName ?? path.split(Platform.pathSeparator).last,
        });
        return;
      } on PlatformException catch (e) {
        throw Exception(e.message ?? 'Could not open this document');
      }
    }
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  Future<PhonePickedDocument> prepareForUpload(PhoneDocument document) async {
    if (!Platform.isAndroid) {
      final path = document.path;
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        throw Exception('Selected file could not be found');
      }
      return PhonePickedDocument(
        name: document.name,
        path: path,
        sizeBytes: document.sizeBytes,
        modifiedAt: await resolveModifiedAt(
          name: document.name,
          path: path,
          uri: document.uri,
          sizeBytes: document.sizeBytes,
          hint: PhonePickedDocument.modifiedAtFromMs(document.modifiedMs),
        ),
      );
    }

    final copied = await _channel.invokeMethod<String>('copyDocument', {
      'uri': document.uri,
      'path': document.path,
      'fileName': document.name,
    });
    if (copied == null || copied.isEmpty) {
      throw Exception('Could not open the selected document');
    }

    final file = File(copied);
    return PhonePickedDocument(
      name: document.name,
      path: copied,
      sizeBytes: await file.length(),
      modifiedAt: await resolveModifiedAt(
        name: document.name,
        path: document.path ?? copied,
        uri: document.uri,
        sizeBytes: document.sizeBytes,
        hint: PhonePickedDocument.modifiedAtFromMs(document.modifiedMs),
      ),
    );
  }

  Future<void> shareDocuments(List<PhoneDocument> documents) async {
    if (documents.isEmpty) return;

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>(
          'shareDocuments',
          {
            'items': documents
                .map(
                  (document) => {
                    'uri': document.uri,
                    'filePath': document.path,
                    'fileName': document.name,
                    'mimeType': document.mime,
                  },
                )
                .toList(),
          },
        );
      } on PlatformException catch (e) {
        throw Exception(e.message ?? 'Could not share these files');
      }
      return;
    }

    final files = <XFile>[];
    for (final document in documents) {
      final path = document.path;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        files.add(XFile(path, mimeType: document.mime, name: document.name));
      }
    }
    if (files.isEmpty) {
      throw Exception('Could not share these files');
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: documents.length == 1
            ? 'Sharing ${documents.first.name}'
            : 'Sharing ${documents.length} files',
      ),
    );
  }

  Future<int> deleteDocuments(List<PhoneDocument> documents) async {
    var deleted = 0;
    for (final document in documents) {
      try {
        if (Platform.isAndroid) {
          final ok = await _channel.invokeMethod<bool>(
            'deleteDocument',
            {
              'uri': document.uri,
              'path': document.path,
            },
          );
          if (ok == true) deleted++;
        } else {
          final path = document.path;
          if (path != null && path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
              deleted++;
            }
          }
        }
      } catch (_) {}
    }
    return deleted;
  }
}
