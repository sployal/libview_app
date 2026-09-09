import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'upload_service.dart';

class AnalyticsException implements Exception {
  final String message;
  AnalyticsException(this.message);

  @override
  String toString() => message;
}

class AnalyticsCount {
  final int uploads;
  final int downloads;
  final int streams;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int bytesStreamed;
  final int activeUsers;

  const AnalyticsCount({
    this.uploads = 0,
    this.downloads = 0,
    this.streams = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    this.bytesStreamed = 0,
    this.activeUsers = 0,
  });

  factory AnalyticsCount.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    return AnalyticsCount(
      uploads: _int(data['uploads']),
      downloads: _int(data['downloads']),
      streams: _int(data['streams']),
      bytesUploaded: _int(data['bytesUploaded']),
      bytesDownloaded: _int(data['bytesDownloaded']),
      bytesStreamed: _int(data['bytesStreamed']),
      activeUsers: _int(data['activeUsers']),
    );
  }

  int get totalBytes => bytesUploaded + bytesDownloaded;
}

class AnalyticsNamedCount {
  final String id;
  final String name;
  final String kind;
  final int users;
  final int newUsers;
  final int uploads;
  final int downloads;
  final int streams;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int bytesStreamed;

  const AnalyticsNamedCount({
    required this.id,
    required this.name,
    this.kind = '',
    this.users = 0,
    this.newUsers = 0,
    this.uploads = 0,
    this.downloads = 0,
    this.streams = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    this.bytesStreamed = 0,
  });

  factory AnalyticsNamedCount.fromJson(Map<String, dynamic> json) {
    return AnalyticsNamedCount(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      users: _int(json['users']),
      newUsers: _int(json['newUsers']),
      uploads: _int(json['uploads']),
      downloads: _int(json['downloads']),
      streams: _int(json['streams']),
      bytesUploaded: _int(json['bytesUploaded']),
      bytesDownloaded: _int(json['bytesDownloaded']),
      bytesStreamed: _int(json['bytesStreamed']),
    );
  }

  int get totalBytes => bytesUploaded + bytesDownloaded;
}

class AnalyticsFileType {
  final String id;
  final String name;
  final String group;
  final int uploads;
  final int downloads;
  final int streams;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int bytesStreamed;

  const AnalyticsFileType({
    required this.id,
    required this.name,
    this.group = '',
    this.uploads = 0,
    this.downloads = 0,
    this.streams = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    this.bytesStreamed = 0,
  });

  factory AnalyticsFileType.fromJson(Map<String, dynamic> json) {
    return AnalyticsFileType(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      uploads: _int(json['uploads']),
      downloads: _int(json['downloads']),
      streams: _int(json['streams']),
      bytesUploaded: _int(json['bytesUploaded']),
      bytesDownloaded: _int(json['bytesDownloaded']),
      bytesStreamed: _int(json['bytesStreamed']),
    );
  }

  int get totalCount => uploads + downloads;
  int get playCount => streams;
  int get playBytes => bytesStreamed > 0 ? bytesStreamed : bytesDownloaded;
  int get totalBytes => bytesUploaded + bytesDownloaded;
}

class AnalyticsSeriesPoint {
  final String label;
  final int uploads;
  final int downloads;
  final int streams;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int bytesStreamed;
  final int activeUsers;

  const AnalyticsSeriesPoint({
    required this.label,
    this.uploads = 0,
    this.downloads = 0,
    this.streams = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    this.bytesStreamed = 0,
    this.activeUsers = 0,
  });

  factory AnalyticsSeriesPoint.fromJson(Map<String, dynamic> json) {
    return AnalyticsSeriesPoint(
      label: json['label']?.toString() ?? '',
      uploads: _int(json['uploads']),
      downloads: _int(json['downloads']),
      streams: _int(json['streams']),
      bytesUploaded: _int(json['bytesUploaded']),
      bytesDownloaded: _int(json['bytesDownloaded']),
      bytesStreamed: _int(json['bytesStreamed']),
      activeUsers: _int(json['activeUsers']),
    );
  }
}

class AnalyticsTopUser {
  final String uid;
  final String name;
  final String courseName;
  final int count;
  final int bytes;
  final int video;
  final int audio;
  final Map<String, int> types;

  const AnalyticsTopUser({
    required this.uid,
    required this.name,
    this.courseName = '',
    this.count = 0,
    this.bytes = 0,
    this.video = 0,
    this.audio = 0,
    this.types = const {},
  });

  factory AnalyticsTopUser.fromJson(Map<String, dynamic> json) {
    return AnalyticsTopUser(
      uid: json['uid']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      courseName: json['courseName']?.toString() ?? '',
      count: _int(json['count']),
      bytes: _int(json['bytes']),
      video: _int(json['video']),
      audio: _int(json['audio']),
      types: _intMap(json['types']),
    );
  }
}

class AnalyticsAiOwner {
  final String id;
  final String name;
  final String kind;
  final int requests;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const AnalyticsAiOwner({
    required this.id,
    required this.name,
    this.kind = '',
    this.requests = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  factory AnalyticsAiOwner.fromJson(Map<String, dynamic> json) {
    return AnalyticsAiOwner(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      requests: _int(json['requests']),
      promptTokens: _int(json['promptTokens']),
      completionTokens: _int(json['completionTokens']),
      totalTokens: _int(json['totalTokens']),
    );
  }
}

class AnalyticsAiStats {
  final int requests;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const AnalyticsAiStats({
    this.requests = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  factory AnalyticsAiStats.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    return AnalyticsAiStats(
      requests: _int(data['requests']),
      promptTokens: _int(data['promptTokens']),
      completionTokens: _int(data['completionTokens']),
      totalTokens: _int(data['totalTokens']),
    );
  }

  bool get isEmpty => requests <= 0 && totalTokens <= 0;
}

class AnalyticsAiUsage {
  final int requests;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final AnalyticsAiStats chats;
  final AnalyticsAiStats imageScans;
  final List<AnalyticsAiOwner> byOwner;

  const AnalyticsAiUsage({
    this.requests = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.chats = const AnalyticsAiStats(),
    this.imageScans = const AnalyticsAiStats(),
    this.byOwner = const [],
  });

  factory AnalyticsAiUsage.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    final chats = AnalyticsAiStats.fromJson(_map(data['chats']));
    final imageScans = AnalyticsAiStats.fromJson(_map(data['imageScans']));
    final requests = _int(data['requests']);
    final promptTokens = _int(data['promptTokens']);
    final completionTokens = _int(data['completionTokens']);
    final totalTokens = _int(data['totalTokens']);
    final hasKinds = !chats.isEmpty || !imageScans.isEmpty;
    return AnalyticsAiUsage(
      requests: requests,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      chats: hasKinds
          ? chats
          : AnalyticsAiStats(
              requests: requests,
              promptTokens: promptTokens,
              completionTokens: completionTokens,
              totalTokens: totalTokens,
            ),
      imageScans: imageScans,
      byOwner: _list(data['byOwner']).map(AnalyticsAiOwner.fromJson).toList(),
    );
  }

  bool get isEmpty =>
      requests <= 0 &&
      totalTokens <= 0 &&
      chats.isEmpty &&
      imageScans.isEmpty &&
      byOwner.isEmpty;
}

class AnalyticsSnapshot {
  final String periodKind;
  final int year;
  final int? month;
  final int? week;
  final String periodLabel;
  final String platform;
  final List<int> availableYears;
  final int activeUsers;
  final int newUsers;
  final int uploads;
  final int downloads;
  final int streams;
  final int bytesUploaded;
  final int bytesDownloaded;
  final int bytesStreamed;
  final int avgUploadBytes;
  final int avgDownloadBytes;
  final AnalyticsCount mobile;
  final AnalyticsCount web;
  final List<AnalyticsNamedCount> activeUsersByCourse;
  final List<AnalyticsNamedCount> activeUsersByRole;
  final List<AnalyticsNamedCount> bandwidthByCourse;
  final List<AnalyticsFileType> fileTypes;
  final List<AnalyticsFileType> documents;
  final List<AnalyticsFileType> media;
  final List<AnalyticsSeriesPoint> series;
  final List<AnalyticsTopUser> topUploaders;
  final List<AnalyticsTopUser> topDownloaders;
  final List<AnalyticsTopUser> topPlayers;
  final AnalyticsAiUsage ai;

  const AnalyticsSnapshot({
    required this.periodKind,
    required this.year,
    required this.periodLabel,
    required this.platform,
    this.month,
    this.week,
    this.availableYears = const [],
    this.activeUsers = 0,
    this.newUsers = 0,
    this.uploads = 0,
    this.downloads = 0,
    this.streams = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    this.bytesStreamed = 0,
    this.avgUploadBytes = 0,
    this.avgDownloadBytes = 0,
    this.mobile = const AnalyticsCount(),
    this.web = const AnalyticsCount(),
    this.activeUsersByCourse = const [],
    this.activeUsersByRole = const [],
    this.bandwidthByCourse = const [],
    this.fileTypes = const [],
    this.documents = const [],
    this.media = const [],
    this.series = const [],
    this.topUploaders = const [],
    this.topDownloaders = const [],
    this.topPlayers = const [],
    this.ai = const AnalyticsAiUsage(),
  });

  factory AnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    final period = _map(json['period']);
    final summary = _map(json['summary']);
    final platforms = _map(json['platforms']);
    final fileTypes =
        _list(json['fileTypes']).map(AnalyticsFileType.fromJson).toList();
    final media = _list(json['media']).map(AnalyticsFileType.fromJson).toList();
    return AnalyticsSnapshot(
      periodKind: period['kind']?.toString() ?? 'month',
      year: _int(period['year'], DateTime.now().year),
      month: period['month'] == null ? null : _int(period['month']),
      week: period['week'] == null ? null : _int(period['week']),
      periodLabel: period['label']?.toString() ?? 'Analytics',
      platform: json['platform']?.toString() ?? 'all',
      availableYears: _intList(json['availableYears']),
      activeUsers: _int(summary['activeUsers']),
      newUsers: _int(summary['newUsers']),
      uploads: _int(summary['uploads']),
      downloads: _int(summary['downloads']),
      streams: _int(summary['streams']),
      bytesUploaded: _int(summary['bytesUploaded']),
      bytesDownloaded: _int(summary['bytesDownloaded']),
      bytesStreamed: _int(summary['bytesStreamed']),
      avgUploadBytes: _int(summary['avgUploadBytes']),
      avgDownloadBytes: _int(summary['avgDownloadBytes']),
      mobile: AnalyticsCount.fromJson(_map(platforms['mobile'])),
      web: AnalyticsCount.fromJson(_map(platforms['web'])),
      activeUsersByCourse: _list(json['activeUsersByCourse'])
          .map(AnalyticsNamedCount.fromJson)
          .toList(),
      activeUsersByRole: _list(json['activeUsersByRole'])
          .map(AnalyticsNamedCount.fromJson)
          .toList(),
      bandwidthByCourse: _list(json['bandwidthByCourse'])
          .map(AnalyticsNamedCount.fromJson)
          .toList(),
      fileTypes: fileTypes,
      documents:
          _list(json['documents']).map(AnalyticsFileType.fromJson).toList(),
      media: media.isNotEmpty
          ? media
          : fileTypes
              .where((row) => row.id == 'video' || row.id == 'audio')
              .toList(),
      series:
          _list(json['series']).map(AnalyticsSeriesPoint.fromJson).toList(),
      topUploaders:
          _list(json['topUploaders']).map(AnalyticsTopUser.fromJson).toList(),
      topDownloaders:
          _list(json['topDownloaders']).map(AnalyticsTopUser.fromJson).toList(),
      topPlayers:
          _list(json['topPlayers']).map(AnalyticsTopUser.fromJson).toList(),
      ai: AnalyticsAiUsage.fromJson(_map(json['ai'])),
    );
  }

  List<AnalyticsFileType> get mediaRows => media.isNotEmpty
      ? media
      : fileTypes.where((row) => row.id == 'video' || row.id == 'audio').toList();

  int get playBytes {
    if (bytesStreamed > 0) return bytesStreamed;
    return mediaRows.fold<int>(0, (sum, row) => sum + row.playBytes);
  }

  int get transferDownloadBytes {
    if (bytesStreamed > 0) return bytesDownloaded;
    final mediaDown = mediaRows.fold<int>(0, (sum, row) {
      if (row.playCount > 0 && row.bytesStreamed == 0) {
        return sum + row.bytesDownloaded;
      }
      return sum;
    });
    final next = bytesDownloaded - mediaDown;
    return next < 0 ? 0 : next;
  }

  int get transferBytes => bytesUploaded + transferDownloadBytes;
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<int> _intList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => _int(item)).where((item) => item > 0).toList();
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Map<String, int> _intMap(dynamic value) {
  if (value is! Map) return const {};
  final out = <String, int>{};
  value.forEach((key, item) {
    final count = _int(item);
    if (count > 0) out[key.toString()] = count;
  });
  return out;
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) {
    return item is Map<String, dynamic>
        ? item
        : Map<String, dynamic>.from(item);
  }).toList();
}

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();
  static const String clientPlatform = 'mobile';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'X-Client-Platform': clientPlatform},
    ),
  );

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AnalyticsException('Please sign in to continue');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw AnalyticsException('Could not get auth token. Please sign in again.');
    }
    return token;
  }

  Future<Options> _options() async {
    return Options(
      headers: {
        'Authorization': 'Bearer ${await _idToken()}',
        'X-Client-Platform': clientPlatform,
      },
    );
  }

  Future<AnalyticsSnapshot> fetch({
    required String period,
    required String platform,
    int? year,
    int? month,
    int? week,
  }) async {
    try {
      final response = await _dio.get(
        '/analytics',
        queryParameters: {
          'period': period,
          'platform': platform,
          if (year != null) 'year': year,
          if (month != null) 'month': month,
          if (week != null) 'week': week,
        },
        options: await _options(),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return AnalyticsSnapshot.fromJson(data);
      }
      if (data is Map) {
        return AnalyticsSnapshot.fromJson(Map<String, dynamic>.from(data));
      }
      throw AnalyticsException('Unexpected analytics response');
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? (error.response!.data['error']?.toString() ?? '')
          : '';
      throw AnalyticsException(
        message.isNotEmpty ? message : 'Could not load analytics',
      );
    }
  }

  Future<void> ping() async {
    try {
      await _dio.post('/events/presence', options: await _options());
    } catch (_) {
      // Presence is best-effort and should never block the app.
    }
  }

  Future<void> recordDownload({
    required String fileId,
    required String fileName,
    String? mimeType,
    int? sizeBytes,
    String? folderId,
  }) async {
    try {
      await _dio.post(
        '/events/download',
        data: {
          'fileId': fileId,
          'fileName': fileName,
          if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
          if (sizeBytes != null && sizeBytes > 0) 'sizeBytes': sizeBytes,
          if (folderId != null && folderId.isNotEmpty) 'folderId': folderId,
          'platform': clientPlatform,
        },
        options: await _options(),
      );
    } catch (_) {
      // Download analytics must not fail the file save.
    }
  }
}
