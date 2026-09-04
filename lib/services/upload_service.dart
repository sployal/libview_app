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

class UploadCancelledException implements Exception {
  @override
  String toString() => 'Upload cancelled';
}

class UploadResult {
  final String id;
  final String name;
  final String? webViewLink;
  final String? size;
  final String? createdTime;
  final String? modifiedTime;
  final String? uploadedAt;

  UploadResult({
    required this.id,
    required this.name,
    this.webViewLink,
    this.size,
    this.createdTime,
    this.modifiedTime,
    this.uploadedAt,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      webViewLink: json['webViewLink']?.toString(),
      size: json['size']?.toString(),
      createdTime: json['createdTime']?.toString(),
      modifiedTime: json['modifiedTime']?.toString(),
      uploadedAt: json['uploadedAt']?.toString() ??
          (json['properties'] is Map
              ? (json['properties'] as Map)['uploadedAt']?.toString()
              : null),
    );
  }

  DateTime? get createdAt =>
      DateTime.tryParse(uploadedAt ?? '') ?? DateTime.tryParse(createdTime ?? '');

  DateTime? get modifiedAt => DateTime.tryParse(modifiedTime ?? '');
}

class UploadService {
  UploadService._();

  static final UploadService instance = UploadService._();

  static const String baseUrl = 'https://edupal-backend.onrender.com';
  static const int maxUploadBytes = 200 * 1024 * 1024;

  static String get maxUploadLabel {
    final mb = maxUploadBytes / (1024 * 1024);
    if (mb >= 1 && mb == mb.roundToDouble()) {
      return '${mb.round()} MB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 20),
      sendTimeout: const Duration(minutes: 20),
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

  static String? rfc3339(DateTime? date) {
    if (date == null) return null;
    return date.toUtc().toIso8601String();
  }

  Future<UploadResult> uploadFile({
    required String folderId,
    required String fileName,
    String? filePath,
    List<int>? bytes,
    DateTime? modifiedAt,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    void Function(int sent, int total)? onBytes,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No target folder selected');
    }
    if (cancelToken?.isCancelled == true) {
      throw UploadCancelledException();
    }

    final multipart = await _buildMultipart(
      fileName: fileName,
      filePath: filePath,
      bytes: bytes,
    );

    final token = await _idToken();
    final modifiedMs = modifiedAt?.millisecondsSinceEpoch;
    final form = FormData.fromMap({
      'folderId': folderId,
      'file': multipart,
      if (modifiedMs != null && modifiedMs > 0) 'modifiedMs': '$modifiedMs',
    });
    final knownLength = bytes?.length ??
        (filePath != null && filePath.isNotEmpty
            ? await File(filePath).length()
            : 0);
    onProgress?.call(0);
    onBytes?.call(0, knownLength);

    try {
      final response = await _dio.post(
        '/upload',
        data: form,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
        onSendProgress: (sent, total) {
          final bodyTotal = total > 0 ? total : knownLength;
          onBytes?.call(
            sent,
            knownLength > 0 ? knownLength : bodyTotal,
          );
          if (bodyTotal > 0) {
            onProgress?.call((sent / bodyTotal).clamp(0.0, 1.0));
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
      if (e.type == DioExceptionType.cancel || CancelToken.isCancel(e)) {
        throw UploadCancelledException();
      }
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

  Future<Set<String>> fetchLockedFolderIds(String workspaceFolderId) async {
    if (workspaceFolderId.isEmpty) return {};
    final token = await _idToken();
    try {
      final response = await _dio.get(
        '/client-folder-locks',
        queryParameters: {'workspaceFolderId': workspaceFolderId},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      final data = response.data;
      final ids = data is Map ? data['folderIds'] : null;
      if (ids is! List) return {};
      return ids.map((id) => id.toString()).where((id) => id.isNotEmpty).toSet();
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'folder'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> lockClientFolder({
    required String folderId,
    required String password,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No folder selected');
    }
    final token = await _idToken();
    try {
      await _dio.post(
        '/client-folders/${Uri.encodeComponent(folderId)}/lock',
        data: {'password': password},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'folder'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> verifyClientFolderPassword({
    required String folderId,
    required String password,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No folder selected');
    }
    final token = await _idToken();
    try {
      await _dio.post(
        '/client-folders/${Uri.encodeComponent(folderId)}/unlock',
        data: {'password': password},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'folder'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> unlockClientFolder({
    required String folderId,
    required String password,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No folder selected');
    }
    final token = await _idToken();
    try {
      await _dio.post(
        '/client-folders/${Uri.encodeComponent(folderId)}/unlock',
        data: {
          'password': password,
          'remove': true,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'folder'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<DriveOAuthStatus> fetchDriveOAuthStatus() async {
    final token = await _idToken();

    try {
      final response = await _dio.get(
        '/drive-oauth-status',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return DriveOAuthStatus.fromJson(data);
      }
      if (data is Map) {
        return DriveOAuthStatus.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'oauth'),
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

  Future<ClientWorkspaceResult> createClientWorkspace({
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      throw UploadException('Client name is required');
    }

    final token = await _idToken();

    try {
      final response = await _dio.post(
        '/client-workspace',
        data: {'name': name.trim()},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return ClientWorkspaceResult.fromJson(data);
      }
      if (data is Map) {
        return ClientWorkspaceResult.fromJson(Map<String, dynamic>.from(data));
      }
      throw UploadException('Unexpected response from server');
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'client'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<UploadResult> renameClientWorkspace({
    required String folderId,
    required String name,
  }) async {
    if (folderId.isEmpty) {
      throw UploadException('No client folder to rename');
    }
    if (name.trim().isEmpty) {
      throw UploadException('Client name is required');
    }

    final token = await _idToken();

    try {
      final response = await _dio.patch(
        '/client-workspace/${Uri.encodeComponent(folderId)}',
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
        _messageFromDio(e, action: 'client'),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClientWorkspace(String folderId) async {
    if (folderId.isEmpty) {
      throw UploadException('No client folder to delete');
    }

    final token = await _idToken();

    try {
      await _dio.delete(
        '/client-workspace/${Uri.encodeComponent(folderId)}',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw UploadException(
        _messageFromDio(e, action: 'client'),
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
        throw UploadException(
          'File is too large. Maximum size is $maxUploadLabel.',
        );
      }
      return MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: contentType,
      );
    }

    if (bytes != null) {
      if (bytes.length > maxUploadBytes) {
        throw UploadException(
          'File is too large. Maximum size is $maxUploadLabel.',
        );
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
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      case '3g2':
        return 'video/3gpp2';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'flv':
        return 'video/x-flv';
      case 'mpeg':
      case 'mpg':
        return 'video/mpeg';
      case 'ts':
      case 'm2ts':
      case 'mts':
        return 'video/mp2t';
      case 'ogv':
        return 'video/ogg';
      case 'asf':
        return 'video/x-ms-asf';
      case 'vob':
        return 'video/dvd';
      case 'f4v':
        return 'video/x-f4v';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'aiff':
      case 'aif':
        return 'audio/aiff';
      case 'amr':
        return 'audio/amr';
      case 'mid':
      case 'midi':
        return 'audio/midi';
      case 'caf':
        return 'audio/x-caf';
      case 'weba':
        return 'audio/webm';
      default:
        return 'application/octet-stream';
    }
  }

  String _messageFromDio(DioException error, {String action = 'upload'}) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error']?.toString().trim() ?? '';
      if (message == 'Storage limit exceeded') {
        return 'Storage limit exceeded. Delete files or ask the admin to raise the limit.';
      }
      if (message.isNotEmpty && message != 'File upload failed') {
        return message;
      }
    }

    if (error.response?.statusCode == 401) {
      return 'Please sign in again.';
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Please try again.';
    }

    if (error.type == DioExceptionType.connectionError) {
      return 'Check your connection and try again.';
    }

    switch (action) {
      case 'delete':
        return 'Delete failed.';
      case 'rename':
        return 'Rename failed.';
      case 'folder':
        return 'Could not create the folder.';
      case 'course':
        return 'Could not update the course.';
      case 'client':
        return 'Could not update the client workspace.';
      case 'storage':
        return 'Could not load storage.';
      case 'oauth':
        return 'Could not load token status.';
      default:
        return 'File upload failed.';
    }
  }
}

class DriveOAuthStatus {
  final bool stored;
  final bool expired;
  final int? daysLeft;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final int ttlDays;

  DriveOAuthStatus({
    required this.stored,
    required this.expired,
    required this.daysLeft,
    required this.updatedAt,
    required this.expiresAt,
    required this.ttlDays,
  });

  factory DriveOAuthStatus.fromJson(Map<String, dynamic> json) {
    return DriveOAuthStatus(
      stored: json['stored'] == true,
      expired: json['expired'] == true,
      daysLeft: json['daysLeft'] is num
          ? (json['daysLeft'] as num).round()
          : int.tryParse(json['daysLeft']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      ttlDays: json['ttlDays'] is num
          ? (json['ttlDays'] as num).round()
          : int.tryParse(json['ttlDays']?.toString() ?? '') ?? 7,
    );
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

class ClientWorkspaceResult {
  final String folderId;
  final String name;
  final bool created;
  final String clientsRootId;

  ClientWorkspaceResult({
    required this.folderId,
    required this.name,
    required this.created,
    required this.clientsRootId,
  });

  factory ClientWorkspaceResult.fromJson(Map<String, dynamic> json) {
    return ClientWorkspaceResult(
      folderId: json['folderId']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      created: json['created'] == true,
      clientsRootId: json['clientsRootId']?.toString() ?? '',
    );
  }
}
