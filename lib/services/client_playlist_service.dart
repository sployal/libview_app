import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ClientAudioTrack {
  const ClientAudioTrack({
    required this.fileId,
    required this.title,
    this.folderName = '',
  });

  final String fileId;
  final String title;
  final String folderName;

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'title': title,
        'folderName': folderName,
      };

  factory ClientAudioTrack.fromJson(Map<String, dynamic> json) {
    return ClientAudioTrack(
      fileId: json['fileId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Audio',
      folderName: json['folderName']?.toString() ?? '',
    );
  }
}

class ClientAudioPlaylist {
  const ClientAudioPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<ClientAudioTrack> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get length => tracks.length;

  String get countLabel {
    if (tracks.isEmpty) return 'Empty';
    return tracks.length == 1 ? '1 track' : '${tracks.length} tracks';
  }

  ClientAudioPlaylist copyWith({
    String? name,
    List<ClientAudioTrack>? tracks,
    DateTime? updatedAt,
  }) {
    return ClientAudioPlaylist(
      id: id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((track) => track.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ClientAudioPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks = <ClientAudioTrack>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map) {
          final track = ClientAudioTrack.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (track.fileId.isNotEmpty) tracks.add(track);
        }
      }
    }
    return ClientAudioPlaylist(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Playlist',
      tracks: tracks,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ClientAudioPlaylists {
  ClientAudioPlaylists._();

  static String _key(String clientId) => 'client_audio_playlists_$clientId';

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static Future<List<ClientAudioPlaylist>> load(String clientId) async {
    if (clientId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(clientId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final playlists = decoded
          .whereType<Map>()
          .map(
            (item) => ClientAudioPlaylist.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((playlist) => playlist.id.isNotEmpty)
          .toList();
      playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return playlists;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(
    String clientId,
    List<ClientAudioPlaylist> playlists,
  ) async {
    if (clientId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(clientId),
      jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
    );
  }

  static Future<ClientAudioPlaylist> create({
    required String clientId,
    required String name,
    List<ClientAudioTrack> tracks = const [],
  }) async {
    final trimmed = name.trim();
    final now = DateTime.now();
    final playlist = ClientAudioPlaylist(
      id: newId(),
      name: trimmed.isEmpty ? 'New playlist' : trimmed,
      tracks: List<ClientAudioTrack>.of(tracks),
      createdAt: now,
      updatedAt: now,
    );
    final current = await load(clientId);
    await save(clientId, [playlist, ...current]);
    return playlist;
  }

  static Future<ClientAudioPlaylist?> upsert({
    required String clientId,
    required ClientAudioPlaylist playlist,
  }) async {
    if (clientId.isEmpty || playlist.id.isEmpty) return null;
    final current = await load(clientId);
    final next = [
      playlist.copyWith(updatedAt: DateTime.now()),
      ...current.where((item) => item.id != playlist.id),
    ];
    await save(clientId, next);
    return next.first;
  }

  static Future<void> delete({
    required String clientId,
    required String playlistId,
  }) async {
    if (clientId.isEmpty || playlistId.isEmpty) return;
    final current = await load(clientId);
    await save(
      clientId,
      current.where((item) => item.id != playlistId).toList(),
    );
  }

  static Future<ClientAudioPlaylist?> addTracks({
    required String clientId,
    required String playlistId,
    required List<ClientAudioTrack> tracks,
  }) async {
    if (tracks.isEmpty) return null;
    final current = await load(clientId);
    final index = current.indexWhere((item) => item.id == playlistId);
    if (index < 0) return null;
    final playlist = current[index];
    final seen = playlist.tracks.map((track) => track.fileId).toSet();
    final merged = [...playlist.tracks];
    for (final track in tracks) {
      if (track.fileId.isEmpty || seen.contains(track.fileId)) continue;
      seen.add(track.fileId);
      merged.add(track);
    }
    return upsert(
      clientId: clientId,
      playlist: playlist.copyWith(tracks: merged),
    );
  }
}
