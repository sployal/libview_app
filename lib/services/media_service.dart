import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http_parser/http_parser.dart';

import 'upload_service.dart';

class MediaUploadResult {
  final String url;
  final String publicId;

  const MediaUploadResult({required this.url, required this.publicId});
}

class MediaService {
  MediaService._();

  static final MediaService instance = MediaService._();

  static const folderSupport = 'support';
  static const folderNotifications = 'notifications';
  static const folderProfiles = 'profiles';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  Future<MediaUploadResult> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String folder,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to continue');
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not get auth token. Please sign in again.');
    }

    final parts = mimeType.split('/');
    final formData = FormData.fromMap({
      'folder': folder,
      'image': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: MediaType(
          parts.first,
          parts.length > 1 ? parts[1] : 'jpeg',
        ),
      ),
    });

    try {
      final response = await _dio.post(
        '/media/upload',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final data = response.data as Map<String, dynamic>;
      final url = data['url']?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('Image upload did not return a URL');
      }
      return MediaUploadResult(
        url: url,
        publicId: data['publicId']?.toString() ?? '',
      );
    } on DioException catch (e) {
      final message = e.response?.data is Map
          ? (e.response!.data['error']?.toString() ?? e.message)
          : e.message;
      throw Exception(message ?? 'Image upload failed');
    }
  }

  static String mimeFromName(String name, String? extension) {
    final ext = (extension ?? name.split('.').last).toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
