import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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

  const PhonePickedDocument({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });
}

class PhoneDocumentService {
  PhoneDocumentService._();

  static final PhoneDocumentService instance = PhoneDocumentService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.libview/phone_documents');

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
    );
  }
}
