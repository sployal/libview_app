import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http_parser/http_parser.dart';

import 'upload_service.dart';

class SupportMessage {
  final String id;
  final String userId;
  final String userEmail;
  final String userName;
  final String heading;
  final String description;
  final String? screenshotUrl;
  final String? screenshotPublicId;
  final bool isRead;
  final DateTime? createdAt;

  const SupportMessage({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.heading,
    required this.description,
    this.screenshotUrl,
    this.screenshotPublicId,
    this.isRead = false,
    this.createdAt,
  });

  factory SupportMessage.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return SupportMessage(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      userEmail: data['userEmail'] as String? ?? '',
      userName: data['userName'] as String? ?? 'User',
      heading: data['heading'] as String? ?? '',
      description: data['description'] as String? ?? '',
      screenshotUrl: data['screenshotUrl'] as String?,
      screenshotPublicId: data['screenshotPublicId'] as String?,
      isRead: data['isRead'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();

  static const _collection = 'support_messages';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to continue');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not get auth token. Please sign in again.');
    }
    return token;
  }

  Future<Map<String, String>> uploadScreenshot({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final token = await _idToken();
    final parts = mimeType.split('/');
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg'),
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
      return {
        'url': data['url']?.toString() ?? '',
        'publicId': data['publicId']?.toString() ?? '',
      };
    } on DioException catch (e) {
      final message = e.response?.data is Map
          ? (e.response!.data['error']?.toString() ?? e.message)
          : e.message;
      throw Exception(message ?? 'Screenshot upload failed');
    }
  }

  Future<void> submitMessage({
    required String heading,
    required String description,
    String? screenshotUrl,
    String? screenshotPublicId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to send a message');
    }

    String userName = user.displayName ?? 'User';
    final profile = await _firestore.collection('profiles').doc(user.uid).get();
    final profileName = profile.data()?['full_name'] as String?;
    if (profileName != null && profileName.trim().isNotEmpty) {
      userName = profileName.trim();
    }

    await _firestore.collection(_collection).add({
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'userName': userName,
      'heading': heading.trim(),
      'description': description.trim(),
      'screenshotUrl': screenshotUrl,
      'screenshotPublicId': screenshotPublicId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<SupportMessage>> watchMessages() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SupportMessage.fromDoc(doc))
              .toList(),
        );
  }

  Future<void> markAsRead(String id) async {
    await _firestore.collection(_collection).doc(id).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage(SupportMessage message) async {
    final publicId = message.screenshotPublicId;
    if (publicId != null && publicId.isNotEmpty) {
      try {
        final token = await _idToken();
        await _dio.post(
          '/media/delete',
          data: {'publicId': publicId},
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
      } catch (_) {
        // Still remove the ticket if Cloudinary cleanup fails.
      }
    }

    await _firestore.collection(_collection).doc(message.id).delete();
  }
}
