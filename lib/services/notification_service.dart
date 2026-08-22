import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';
import 'course_service.dart';
import 'media_service.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String audience;
  final String admissionPrefix;
  final String classSuffix;
  final String courseId;
  final String? imageUrl;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.audience,
    required this.admissionPrefix,
    required this.classSuffix,
    required this.courseId,
    this.imageUrl,
    required this.createdAt,
    required this.isRead,
  });

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final preview = message.trim();
    if (preview.isEmpty) return 'Notification';
    return preview.split('\n').first;
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      audience: audience,
      admissionPrefix: admissionPrefix,
      classSuffix: classSuffix,
      courseId: courseId,
      imageUrl: imageUrl,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  CollectionReference<Map<String, dynamic>> get _reads =>
      _firestore.collection('notification_reads');

  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots() {
    return _notifications.orderBy('created_at', descending: true).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> readSnapshots(String userId) {
    return _reads.where('user_id', isEqualTo: userId).snapshots();
  }

  Future<List<AppNotification>> listForCurrentUser() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return [];

    final profile = await _firestore.collection('profiles').doc(user.uid).get();
    final data = profile.data() ?? {};
    final registrationNumber =
        (data['registration_number'] as String?) ?? '';
    final courses = await CourseService.instance.listCourses();
    final userCourse =
        CourseService.instance.matchCourse(registrationNumber, courses);

    final notificationsSnap =
        await _notifications.orderBy('created_at', descending: true).get();
    final readsSnap = await _reads.where('user_id', isEqualTo: user.uid).get();
    final readIds = readsSnap.docs
        .map((doc) => doc.data()['notification_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    return notificationsSnap.docs
        .map((doc) => _fromDoc(doc, readIds.contains(doc.id)))
        .where(
          (item) => _isVisibleToUser(
            item: item,
            registrationNumber: registrationNumber,
            userCourse: userCourse,
          ),
        )
        .toList();
  }

  Future<int> unreadCountForCurrentUser() async {
    final items = await listForCurrentUser();
    return items.where((item) => !item.isRead).length;
  }

  Future<void> create({
    String title = '',
    required String message,
    required String type,
    required String audience,
    String? imageUrl,
    String? imagePublicId,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final profile = await _firestore.collection('profiles').doc(user.uid).get();
    final data = profile.data() ?? {};
    final role = ((data['role'] as String?) ?? 'student').toLowerCase();
    if (role == 'student') {
      throw Exception('Students cannot create notifications');
    }

    final registrationNumber =
        (data['registration_number'] as String?) ?? '';
    final prefix = Course.admissionPrefixFromSample(registrationNumber);
    final suffix = Course.classSuffixFromSample(registrationNumber);
    final courses = await CourseService.instance.listCourses();
    final course =
        CourseService.instance.matchCourse(registrationNumber, courses);

    final isClassLeadership =
        role == 'class_rep' || role == 'assistant_class_rep';
    var resolvedAudience = audience;
    if (isClassLeadership) {
      resolvedAudience = audience == 'course' ? 'course' : 'class';
      if (prefix.isEmpty || (resolvedAudience == 'class' && suffix.isEmpty)) {
        throw Exception(
          'Your registration number is needed to send a class or course notification.',
        );
      }
    } else {
      resolvedAudience = 'all';
    }

    await _notifications.add({
      'title': title.trim(),
      'message': message.trim(),
      'type': type,
      'sender_id': user.uid,
      'sender_name': (data['full_name'] as String?) ?? 'Unknown',
      'sender_role': role,
      'audience': resolvedAudience,
      'admission_prefix': prefix,
      'class_suffix': suffix,
      'course_id': course?.id ?? '',
      'image_url': imageUrl,
      'image_public_id': imagePublicId,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update({
    required String id,
    required String title,
    required String message,
    required String type,
  }) async {
    await _notifications.doc(id).update({
      'title': title.trim(),
      'message': message.trim(),
      'type': type,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    final doc = await _notifications.doc(id).get();
    final publicId = doc.data()?['image_public_id']?.toString() ?? '';
    if (publicId.isNotEmpty) {
      try {
        await MediaService.instance.deleteImage(publicId);
      } catch (_) {
        // Still remove the notification if Cloudinary cleanup fails.
      }
    }
    await _notifications.doc(id).delete();
  }

  Future<void> markAsRead(String notificationId) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    await _reads.doc('${user.uid}_$notificationId').set({
      'user_id': user.uid,
      'notification_id': notificationId,
      'read_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead(List<String> notificationIds) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    final batch = _firestore.batch();
    for (final id in notificationIds) {
      batch.set(_reads.doc('${user.uid}_$id'), {
        'user_id': user.uid,
        'notification_id': id,
        'read_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  bool _isVisibleToUser({
    required AppNotification item,
    required String registrationNumber,
    required Course? userCourse,
  }) {
    if (item.audience == 'all' || item.audience.isEmpty) return true;

    if (item.audience == 'course') {
      if (item.courseId.isNotEmpty && userCourse != null) {
        return userCourse.id == item.courseId;
      }
      final userPrefix = Course.admissionPrefixFromSample(registrationNumber);
      return userPrefix.isNotEmpty && userPrefix == item.admissionPrefix;
    }

    if (item.audience == 'class') {
      final userPrefix = Course.admissionPrefixFromSample(registrationNumber);
      final userSuffix = Course.classSuffixFromSample(registrationNumber);
      return userPrefix.isNotEmpty &&
          userSuffix.isNotEmpty &&
          userPrefix == item.admissionPrefix &&
          userSuffix == item.classSuffix;
    }

    return true;
  }

  AppNotification _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool isRead,
  ) {
    final data = doc.data();
    final createdAt = data['created_at'];
    return AppNotification(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'general',
      senderId: (data['sender_id'] as String?) ?? '',
      senderName: (data['sender_name'] as String?) ?? 'Unknown',
      senderRole: (data['sender_role'] as String?) ?? 'student',
      audience: (data['audience'] as String?) ?? 'all',
      admissionPrefix: (data['admission_prefix'] as String?) ?? '',
      classSuffix: (data['class_suffix'] as String?) ?? '',
      courseId: (data['course_id'] as String?) ?? '',
      imageUrl: data['image_url'] as String?,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      isRead: isRead,
    );
  }
}
