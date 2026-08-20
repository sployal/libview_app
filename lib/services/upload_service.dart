import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http_parser/http_parser.dart';

class UploadException implements Exception {
  final String message;
  final int? statusCode;

  UploadException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class UploadResult {
  final String id;
  final String name;
  final String? webViewLink;
  final String? size;
  final String? createdTime;

  UploadResult({
    required this.id,
    required this.name,
    this.webViewLink,
    this.size,
    this.createdTime,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      webViewLink: json['webViewLink']?.toString(),
      size: json['size']?.toString(),
      createdTime: json['createdTime']?.toString(),
    );
  }
}

class UploadService {
  UploadService._();

  static final UploadService instance = UploadService._();

  static const String baseUrl = 'https://edupal-backend.onrender.com';
  static const int maxUploadBytes = 20 * 1024 * 1024;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
        throw UploadException('Please sign in to continue');
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw UploadException('Could not get auth token. Please sign in again.');
    }
    return token;
  }

  Future<UploadResult> uploadFile({
    required String folderId,
    required String fileName,
    String? filePath,
    List<int>? bytes,
    void Function(double progress)? onProgress,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No target folder selected');
    }

    final multipart = await _buildMultipart(
      fileName: fileName,
      filePath: filePath,
      bytes: bytes,
    );

    final token = await _idToken();
    final form = FormData.fromMap({
      'folderId': folderId,
      'file': multipart,
    });

    try {
      final response = await _dio.post(
        '/upload',
        data: form,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total);
          }
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return UploadResult.fromJson(data);
      }
      if (data is Map) {
        return UploadResult.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<UploadResult> createFolder({
    required String parentFolderId,
    required String name,
  }) async {
    if (parentFolderId.isEmpty) {
      throw UploadException('No target folder selected');
    }
    if (name.trim().isEmpty) {
      throw UploadException('Folder name is required');
    }

    final token = await _idToken();

    try {
      final response = await _dio.post(
        '/folders',
        data: {
          'parentFolderId': parentFolderId,
          'name': name.trim(),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return UploadResult.fromJson(data);
      }
      if (data is Map) {
        return UploadResult.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'folder'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<UploadResult> renameFile({
    required String fileId,
    required String name,
  }) async {
    if (fileId.isEmpty) {
      throw UploadException('No folder selected');
    }
    if (name.trim().isEmpty) {
      throw UploadException('Folder name is required');
    }

    final token = await _idToken();

    try {
      final response = await _dio.patch(
        '/files/${Uri.encodeComponent(fileId)}',
        data: {'name': name.trim()},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return UploadResult.fromJson(data);
      }
      if (data is Map) {
        return UploadResult.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'rename'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteFile(String fileId) async {
    if (fileId.isEmpty) {
      throw UploadException('No file selected');
    }

    final token = await _idToken();

    try {
      await _dio.delete(
        '/files/${Uri.encodeComponent(fileId)}',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'delete'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<MultipartFile> _buildMultipart({
    required String fileName,
    String? filePath,
    List<int>? bytes,
  }) async {
    final contentType = MediaType.parse(_mimeFromFileName(fileName));

    if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw UploadException('Selected file could not be found');
      }
      final length = await file.length();
      if (length > maxUploadBytes) {
        throw UploadException('File is too large. Maximum size is 20 MB.');
      }
      return MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: contentType,
      );
    }

    if (bytes != null) {
      if (bytes.length > maxUploadBytes) {
        throw UploadException('File is too large. Maximum size is 20 MB.');
      }
      return MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: contentType,
      );
    }

    throw UploadException('Failed to read the selected file');
  }

  String _mimeFromFileName(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
      case 'pps':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'svg':
        return 'image/svg+xml';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'txt':
        return 'text/plain';
      case 'rtf':
        return 'application/rtf';
      default:
        return 'application/octet-stream';
    }
  }

  String _messageFromDio(DioException error, {String action = 'upload'}) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }

    switch (error.response?.statusCode) {
      case 401:
        return 'Session expired. Please sign in again.';
      case 403:
        if (action == 'delete') {
          return 'You do not have permission to delete this file.';
        }
        if (action == 'rename' || action == 'folder') {
          return 'You do not have permission to change folders here.';
        }
        return 'You cannot upload to this folder.';
      case 400:
        if (action == 'delete') {
          return 'Delete was rejected.';
        }
        if (action == 'rename' || action == 'folder') {
          return 'That folder name is not allowed.';
        }
        return 'Upload was rejected. Use a file under 20 MB.';
      default:
        break;
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      if (action == 'delete') {
        return 'Delete timed out. The server may be waking up — try again.';
      }
      if (action == 'rename' || action == 'folder') {
        return 'Request timed out. The server may be waking up — try again.';
      }
      return 'Upload timed out. The server may be waking up — try again.';
    }

    if (error.type == DioExceptionType.connectionError) {
      return 'Could not reach the upload server. Check your connection.';
    }

    if (action == 'delete') {
      return 'Delete failed. Please try again.';
    }
    if (action == 'rename') {
      return 'Rename failed. Please try again.';
    }
    if (action == 'folder') {
      return 'Could not create the folder. Please try again.';
    }
    return 'Upload failed. Please try again.';
  }
}
