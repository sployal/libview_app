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

  Future<DriveStorageSnapshot> fetchDriveStorage({bool refresh = false}) async {
    final token = await _idToken();

    try {
      final response = await _dio.get(
        '/drive-storage',
        queryParameters: refresh ? {'refresh': '1'} : null,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return DriveStorageSnapshot.fromJson(data);
      }
      if (data is Map) {
        return DriveStorageSnapshot.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'storage'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<CourseStructureResult> createCourseStructure({
    required String courseName,
    required int years,
  }) async {
    if (courseName.trim().isEmpty) {
      throw UploadException('Course name is required');
    }
    if (years < 1 || years > 10) {
      throw UploadException('Number of years must be between 1 and 10');
    }

    final token = await _idToken();

    try {
      final response = await _dio.post(
        '/course-structure',
        data: {
          'name': courseName.trim(),
          'years': years,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return CourseStructureResult.fromJson(data);
      }
      if (data is Map) {
        return CourseStructureResult.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'course'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<UploadResult> renameCourseFolder({
    required String folderId,
    required String name,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No course folder to rename');
    }
    if (name.trim().isEmpty) {
      throw UploadException('Course name is required');
    }

    final token = await _idToken();

    try {
      final response = await _dio.patch(
        '/course-folder/${Uri.encodeComponent(folderId)}',
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
        _messageFromDio(e, action: 'course'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteCourseFolder(String folderId) async {
    if (folderId.isEmpty) {
      throw UploadException('No course folder to delete');
    }

    final token = await _idToken();

    try {
      await _dio.delete(
        '/course-folder/${Uri.encodeComponent(folderId)}',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'course'),
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
          contentType: Headers.jsonContentType,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
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
        if (action == 'storage') {
          return 'You do not have permission to view Drive storage.';
        }
        if (action == 'rename' || action == 'folder' || action == 'course') {
          return 'You do not have permission to rename this item.';
        }
        return 'You cannot upload to this folder.';
      case 400:
        if (action == 'delete') {
          return 'Delete was rejected.';
        }
        if (action == 'rename') {
          return 'That file name is not allowed.';
        }
        if (action == 'folder' || action == 'course') {
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
      if (action == 'rename' ||
          action == 'folder' ||
          action == 'course' ||
          action == 'storage') {
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
    if (action == 'course') {
      return 'Could not update the course Drive folders. Please try again.';
    }
    if (action == 'storage') {
      return 'Could not load Drive storage. Please try again.';
    }
    return 'Upload failed. Please try again.';
  }
}

class DriveCourseUsage {
  final String folderId;
  final String name;
  final int bytes;

  DriveCourseUsage({
    required this.folderId,
    required this.name,
    required this.bytes,
  });

  factory DriveCourseUsage.fromJson(Map<String, dynamic> json) {
    return DriveCourseUsage(
      folderId: json['folderId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Course',
      bytes: _parseByteCount(json['bytes']),
    );
  }
}

class DriveStorageSnapshot {
  final String accountEmail;
  final String accountName;
  final int? limitBytes;
  final int usageBytes;
  final String? rootName;
  final int rootBytes;
  final int rootOtherBytes;
  final int otherAccountBytes;
  final List<DriveCourseUsage> courses;
  final bool cached;

  DriveStorageSnapshot({
    required this.accountEmail,
    required this.accountName,
    required this.limitBytes,
    required this.usageBytes,
    required this.rootName,
    required this.rootBytes,
    required this.rootOtherBytes,
    required this.otherAccountBytes,
    required this.courses,
    required this.cached,
  });

  factory DriveStorageSnapshot.fromJson(Map<String, dynamic> json) {
    final account = json['account'] is Map
        ? Map<String, dynamic>.from(json['account'] as Map)
        : <String, dynamic>{};
    final root = json['root'] is Map
        ? Map<String, dynamic>.from(json['root'] as Map)
        : null;
    final courses = <DriveCourseUsage>[];
    final rawCourses = json['courses'];
    if (rawCourses is List) {
      for (final item in rawCourses) {
        if (item is Map) {
          courses.add(
            DriveCourseUsage.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return DriveStorageSnapshot(
      accountEmail: account['email']?.toString() ?? '',
      accountName: account['displayName']?.toString() ?? '',
      limitBytes: _parseOptionalByteCount(account['limitBytes']),
      usageBytes: _parseByteCount(account['usageBytes']),
      rootName: root?['name']?.toString(),
      rootBytes: _parseByteCount(root?['bytes']),
      rootOtherBytes: _parseByteCount(root?['otherBytes']),
      otherAccountBytes: _parseByteCount(json['otherAccountBytes']),
      courses: courses,
      cached: json['cached'] == true,
    );
  }
}

int _parseByteCount(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _parseOptionalByteCount(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

class CourseSemesterFolder {
  final String key;
  final String folderId;
  final String name;
  final String driveName;

  CourseSemesterFolder({
    required this.key,
    required this.folderId,
    required this.name,
    required this.driveName,
  });
}

class CourseStructureResult {
  final String courseFolderId;
  final String courseFolderName;
  final Map<String, CourseSemesterFolder> semesters;

  CourseStructureResult({
    required this.courseFolderId,
    required this.courseFolderName,
    required this.semesters,
  });

  factory CourseStructureResult.fromJson(Map<String, dynamic> json) {
    final rawSemesters = json['semesters'];
    final semesters = <String, CourseSemesterFolder>{};
    if (rawSemesters is Map) {
      rawSemesters.forEach((key, value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          semesters[key.toString()] = CourseSemesterFolder(
            key: key.toString(),
            folderId: map['folderId']?.toString() ?? map['id']?.toString() ?? '',
            name: map['name']?.toString() ?? key.toString(),
            driveName: map['driveName']?.toString() ?? '',
          );
        }
      });
    }

    return CourseStructureResult(
      courseFolderId: json['courseFolderId']?.toString() ??
          json['id']?.toString() ??
          '',
      courseFolderName: json['courseFolderName']?.toString() ??
          json['name']?.toString() ??
          '',
      semesters: semesters,
    );
  }
}
