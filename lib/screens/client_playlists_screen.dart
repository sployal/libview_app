import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/client_playlist_service.dart';
import '../ui/create_name_dialog.dart';
import '../services/google_drive_service.dart';
import '../services/media_session.dart';
import '../services/upload_service.dart';
import 'no_internet_screen.dart';

const _rose = Color(0xFFEC4899);
const _violet = Color(0xFF8B5CF6);
const _ink = Color(0xFF0B1220);

const _coverGradients = [
  [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  [Color(0xFFF43F5E), Color(0xFFFB7185)],
  [Color(0xFF6366F1), Color(0xFFEC4899)],
  [Color(0xFF0EA5E9), Color(0xFFA855F7)],
  [Color(0xFF14B8A6), Color(0xFF6366F1)],
  [Color(0xFFF59E0B), Color(0xFFEC4899)],
];

List<Color> playlistCoverColors(String seed) {
  var hash = 0;
  for (final code in seed.codeUnits) {
    hash = (hash + code) & 0x7fffffff;
  }
  return _coverGradients[hash % _coverGradients.length];
}

Future<bool> playClientAudioPlaylist(
  BuildContext context,
  ClientAudioPlaylist playlist, {
  required String clientId,
  required String rootFolderId,
  String workspaceName = '',
  int index = 0,
  bool shuffle = false,
}) async {
  if (playlist.tracks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a track to this playlist first')),
    );
    return false;
  }
  if (!await NoInternetScreen.ensureOnline(context)) return false;
  if (!context.mounted) return false;
  HapticFeedback.lightImpact();
  await MediaSession.instance.open(
    queue: [
      for (final track in playlist.tracks)
        MediaQueueItem(
          id: track.fileId,
          title: track.title,
          isAudio: true,
          hasVideoTrack: track.fromVideo,
          subject: track.folderName.isEmpty ? playlist.name : track.folderName,
        ),
    ],
    index: index.clamp(0, playlist.tracks.length - 1),
    origin: PlaylistPlaybackOrigin(
      playlistId: playlist.id,
      clientId: clientId,
      rootFolderId: rootFolderId,
      workspaceName: workspaceName,
      playlistName: playlist.name,
    ),
  );
  if (shuffle) {
    MediaSession.instance.setMode(PlaybackRepeatMode.shuffle);
  } else {
    MediaSession.instance.setMode(PlaybackRepeatMode.all);
  }
  return true;
}

Future<void> openPlayingClientPlaylist(BuildContext context) async {
  final origin = MediaSession.instance.playlistOrigin;
  if (origin == null) return;
  if (ClientPlaylistDetailScreen.visiblePlaylistId == origin.playlistId) {
    MediaSession.instance.popOut();
    return;
  }
  MediaSession.instance.popOut();
  final playlists = await ClientAudioPlaylists.load(origin.clientId);
  ClientAudioPlaylist? playlist;
  for (final item in playlists) {
    if (item.id == origin.playlistId) {
      playlist = item;
      break;
    }
  }
  if (!context.mounted) return;
  if (playlist == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That playlist is no longer available')),
    );
    return;
  }
  final selected = playlist;
  HapticFeedback.lightImpact();
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (context) => ClientPlaylistDetailScreen(
        clientId: origin.clientId,
        rootFolderId: origin.rootFolderId,
        playlist: selected,
      ),
    ),
  );
}

Future<void> showAddAudioToPlaylistSheet({
  required BuildContext context,
  required String clientId,
  required List<ClientAudioTrack> tracks,
}) async {
  if (clientId.isEmpty || tracks.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _AddToPlaylistSheet(
      clientId: clientId,
      tracks: tracks,
    ),
  );
}

class ClientPlaylistsScreen extends StatefulWidget {
  const ClientPlaylistsScreen({
    super.key,
    required this.clientId,
    required this.rootFolderId,
    required this.workspaceName,
  });

  final String clientId;
  final String rootFolderId;
  final String workspaceName;

  @override
  State<ClientPlaylistsScreen> createState() => _ClientPlaylistsScreenState();
}

class _ClientPlaylistsScreenState extends State<ClientPlaylistsScreen> {
  List<ClientAudioPlaylist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final playlists = await ClientAudioPlaylists.load(widget.clientId);
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = await promptPlaylistName(context);
    if (name == null || name.isEmpty || !mounted) return;
    final playlist = await ClientAudioPlaylists.create(
      clientId: widget.clientId,
      name: name,
    );
    if (!mounted) return;
    await _open(playlist);
    await _reload();
  }

  Future<void> _open(ClientAudioPlaylist playlist) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ClientPlaylistDetailScreen(
          clientId: widget.clientId,
          rootFolderId: widget.rootFolderId,
          playlist: playlist,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _ink : const Color(0xFFF4F1F6);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: _rose,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.queue_music_rounded),
        label: const Text(
          'New playlist',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Playlists',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: title,
                          ),
                        ),
                        Text(
                          'Mixes from ${widget.workspaceName}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _playlists.isEmpty
                      ? _EmptyPlaylists(onCreate: _create)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: _playlists.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final playlist = _playlists[index];
                            return _PlaylistRow(
                              playlist: playlist,
                              onOpen: () => _open(playlist),
                              onPlay: () => playClientAudioPlaylist(
                                context,
                                playlist,
                                clientId: widget.clientId,
                                rootFolderId: widget.rootFolderId,
                                workspaceName: widget.workspaceName,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientPlaylistDetailScreen extends StatefulWidget {
  const ClientPlaylistDetailScreen({
    super.key,
    required this.clientId,
    required this.rootFolderId,
    required this.playlist,
  });

  final String clientId;
  final String rootFolderId;
  final ClientAudioPlaylist playlist;

  static String? visiblePlaylistId;

  @override
  State<ClientPlaylistDetailScreen> createState() =>
      _ClientPlaylistDetailScreenState();
}

class _ClientPlaylistDetailScreenState
    extends State<ClientPlaylistDetailScreen> {
  late ClientAudioPlaylist _playlist;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    ClientPlaylistDetailScreen.visiblePlaylistId = _playlist.id;
    MediaSession.instance.addListener(_onSession);
    MediaSession.instance.playing.addListener(_onSession);
  }

  @override
  void dispose() {
    if (ClientPlaylistDetailScreen.visiblePlaylistId == _playlist.id) {
      ClientPlaylistDetailScreen.visiblePlaylistId = null;
    }
    if (MediaSession.instance.sourceId == _playlist.id &&
        MediaSession.instance.active) {
      MediaSession.instance.popOut();
    }
    MediaSession.instance.removeListener(_onSession);
    MediaSession.instance.playing.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _play({int index = 0, bool shuffle = false}) {
    return playClientAudioPlaylist(
      context,
      _playlist,
      clientId: widget.clientId,
      rootFolderId: widget.rootFolderId,
      index: index,
      shuffle: shuffle,
    );
  }

  bool get _isThisPlaylistPlaying {
    final session = MediaSession.instance;
    return session.active && session.sourceId == _playlist.id;
  }

  bool _isCurrentTrack(ClientAudioTrack track) {
    return _isThisPlaylistPlaying &&
        MediaSession.instance.current?.id == track.fileId;
  }

  ClientAudioTrack? get _nowPlayingTrack {
    if (!_isThisPlaylistPlaying) return null;
    final id = MediaSession.instance.current?.id;
    if (id == null) return null;
    for (final track in _playlist.tracks) {
      if (track.fileId == id) return track;
    }
    return null;
  }

  List<MediaQueueItem> _queueFor(ClientAudioPlaylist playlist) {
    return [
      for (final track in playlist.tracks)
        MediaQueueItem(
          id: track.fileId,
          title: track.title,
          isAudio: true,
          hasVideoTrack: track.fromVideo,
          subject: track.folderName.isEmpty ? playlist.name : track.folderName,
        ),
    ];
  }

  Future<void> _persist(ClientAudioPlaylist next) async {
    final saved = await ClientAudioPlaylists.upsert(
      clientId: widget.clientId,
      playlist: next,
    );
    if (!mounted) return;
    setState(() => _playlist = saved ?? next);
  }

  Future<void> _rename() async {
    final name = await promptPlaylistName(
      context,
      initial: _playlist.name,
      title: 'Rename playlist',
      confirmLabel: 'Save',
    );
    if (name == null || name.isEmpty || name == _playlist.name) return;
    await _persist(_playlist.copyWith(name: name));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Delete playlist?'),
          content: Text(
            '"${_playlist.name}" will be removed. Your audio files stay in Drive.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await ClientAudioPlaylists.delete(
      clientId: widget.clientId,
      playlistId: _playlist.id,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _addTracks() async {
    final picked = await Navigator.of(context).push<List<ClientAudioTrack>>(
      MaterialPageRoute(
        builder: (context) => ClientAudioTrackPickerScreen(
          rootFolderId: widget.rootFolderId,
          excludeIds: _playlist.tracks.map((track) => track.fileId).toSet(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final saved = await ClientAudioPlaylists.addTracks(
      clientId: widget.clientId,
      playlistId: _playlist.id,
      tracks: picked,
    );
    if (!mounted) return;
    if (saved != null) setState(() => _playlist = saved);
  }

  Future<void> _removeTrack(int index) async {
    final next = [..._playlist.tracks]..removeAt(index);
    final updated = _playlist.copyWith(tracks: next);
    await _persist(updated);
    if (_isThisPlaylistPlaying) {
      if (updated.tracks.isEmpty) {
        MediaSession.instance.close();
      } else {
        MediaSession.instance.replaceQueue(_queueFor(updated));
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    var insert = newIndex;
    if (insert > oldIndex) insert -= 1;
    final next = [..._playlist.tracks];
    final item = next.removeAt(oldIndex);
    next.insert(insert, item);
    final updated = _playlist.copyWith(tracks: next);
    await _persist(updated);
    if (_isThisPlaylistPlaying) {
      MediaSession.instance.replaceQueue(_queueFor(updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _ink : const Color(0xFFF4F1F6);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final card = isDark ? const Color(0xFF151B28) : Colors.white;
    final colors = playlistCoverColors(_playlist.id);

    return Scaffold(
      backgroundColor: bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: colors.first,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'Rename',
                onPressed: _rename,
                icon: const Icon(Icons.drive_file_rename_outline_rounded),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _PlaylistHero(
                name: _playlist.name,
                subtitle: _nowPlayingTrack == null
                    ? _playlist.countLabel
                    : 'Now playing · ${_nowPlayingTrack!.title}',
                colors: colors,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _PlayAction(
                      icon: Icons.play_arrow_rounded,
                      label: 'Play',
                      filled: true,
                      onTap: () => _play(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PlayAction(
                      icon: Icons.shuffle_rounded,
                      label: 'Shuffle',
                      filled: false,
                      onTap: () => _play(shuffle: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_nowPlayingTrack != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _NowPlayingBanner(
                  track: _nowPlayingTrack!,
                  playing: MediaSession.instance.playing.value,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Material(
                color: card,
                elevation: 0,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _addTracks,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _rose.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: _rose,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add tracks from files',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: title,
                                ),
                              ),
                              Text(
                                'Audio or video · video plays as audio',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: _playlist.tracks.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.library_music_outlined,
                      size: 42,
                      color: muted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This playlist is waiting for a first track.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Material(
                        elevation: 8 * animation.value,
                        color: Colors.transparent,
                        shadowColor: _rose.withValues(alpha: 0.35),
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                onReorder: _reorder,
                itemCount: _playlist.tracks.length,
                itemBuilder: (context, index) {
                  final track = _playlist.tracks[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(track.fileId),
                    index: index,
                    child: _TrackTile(
                      index: index,
                      track: track,
                      current: _isCurrentTrack(track),
                      onPlay: () => _play(index: index),
                      onRemove: () => _removeTrack(index),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class ClientAudioTrackPickerScreen extends StatefulWidget {
  const ClientAudioTrackPickerScreen({
    super.key,
    required this.rootFolderId,
    this.excludeIds = const {},
  });

  final String rootFolderId;
  final Set<String> excludeIds;

  @override
  State<ClientAudioTrackPickerScreen> createState() =>
      _ClientAudioTrackPickerScreenState();
}

class _ClientAudioTrackPickerScreenState
    extends State<ClientAudioTrackPickerScreen> {
  final List<Subject> _trail = [];
  final Map<String, ClientAudioTrack> _selected = {};
  List<StudyMaterial> _items = [];
  bool _loading = true;
  Set<String> _lockedIds = {};

  String get _folderId =>
      _trail.isEmpty ? widget.rootFolderId : _trail.last.folderId;

  String get _folderName =>
      _trail.isEmpty ? 'Files' : _trail.last.name;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _lockedIds = await UploadService.instance.fetchLockedFolderIds(
        widget.rootFolderId,
      );
    } catch (_) {
      _lockedIds = {};
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await GoogleDriveService.getSubjectFiles(
      _folderId,
      includeFolders: true,
    );
    if (!mounted) return;
    setState(() {
      _items = files
          .where(
            (item) =>
                item.isFolder ||
                UploadService.isPlayableMediaType(item.type),
          )
          .toList();
      _loading = false;
    });
  }

  Future<void> _openFolder(StudyMaterial folder) async {
    if (_lockedIds.contains(folder.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this folder in Files first')),
      );
      return;
    }
    _trail.add(
      GoogleDriveService.subjectFromFolder(
        id: folder.id,
        name: folder.name,
        colorIndex: _trail.length,
      ),
    );
    await _load();
  }

  Future<void> _back() async {
    if (_trail.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _trail.removeLast();
    await _load();
  }

  void _toggle(StudyMaterial file) {
    if (widget.excludeIds.contains(file.id)) return;
    setState(() {
      if (_selected.containsKey(file.id)) {
        _selected.remove(file.id);
      } else {
        _selected[file.id] = ClientAudioTrack(
          fileId: file.id,
          title: file.name,
          folderName: _folderName,
          fromVideo: file.type.toUpperCase() == 'VID',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _ink : const Color(0xFFF4F1F6);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final card = isDark ? const Color(0xFF151B28) : Colors.white;

    return PopScope(
      canPop: _trail.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: title,
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add tracks',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              _folderName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(
                context,
                _selected.values.toList(),
              ),
              backgroundColor: _rose,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.check_rounded),
              label: Text(
                'Add ${_selected.length}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'No folders, audio, or video here',
                    style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    if (item.isFolder) {
                      final locked = _lockedIds.contains(item.id);
                      return Material(
                        color: card,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          onTap: () => _openFolder(item),
                          leading: Icon(
                            locked
                                ? Icons.folder_off_rounded
                                : Icons.folder_rounded,
                            color: locked
                                ? muted
                                : const Color(0xFF6366F1),
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: title,
                            ),
                          ),
                          subtitle: Text(
                            locked ? 'Locked' : item.size,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: muted,
                          ),
                        ),
                      );
                    }
                    final already = widget.excludeIds.contains(item.id);
                    final selected = _selected.containsKey(item.id);
                    final video = item.type.toUpperCase() == 'VID';
                    return Material(
                      color: card,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        enabled: !already,
                        onTap: already ? null : () => _toggle(item),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: (video
                                    ? const Color(0xFF0EA5E9)
                                    : _rose)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            video
                                ? Icons.videocam_rounded
                                : Icons.audiotrack_rounded,
                            color: video
                                ? const Color(0xFF0EA5E9)
                                : _rose,
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: already ? muted : title,
                          ),
                        ),
                        subtitle: Text(
                          already
                              ? 'Already in playlist'
                              : video
                                  ? '${item.size} · plays as audio'
                                  : item.size,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        trailing: already
                            ? Icon(Icons.check_circle_rounded, color: muted)
                            : Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected ? _rose : muted,
                              ),
                      ),
                    );
                  },
                ),
    ),
    );
  }
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({
    required this.clientId,
    required this.tracks,
  });

  final String clientId;
  final List<ClientAudioTrack> tracks;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<ClientAudioPlaylist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlists = await ClientAudioPlaylists.load(widget.clientId);
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _createAndAdd() async {
    final name = await promptPlaylistName(context);
    if (name == null || name.isEmpty) return;
    await ClientAudioPlaylists.create(
      clientId: widget.clientId,
      name: name,
      tracks: widget.tracks,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to "$name"')),
    );
  }

  Future<void> _addTo(ClientAudioPlaylist playlist) async {
    await ClientAudioPlaylists.addTracks(
      clientId: widget.clientId,
      playlistId: playlist.id,
      tracks: widget.tracks,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to "${playlist.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF151B28) : Colors.white;
    final title = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);
    final count = widget.tracks.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_rose, _violet],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add to playlist',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: title,
                            ),
                          ),
                          Text(
                            count == 1
                                ? widget.tracks.first.title
                                : '$count files',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Material(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _createAndAdd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.add_rounded, color: _rose),
                          const SizedBox(width: 12),
                          Text(
                            'New playlist',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: title,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (_playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Create a playlist to start collecting tracks.',
                      style: TextStyle(color: muted),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final playlist = _playlists[index];
                        final colors = playlistCoverColors(playlist.id);
                        return Material(
                          color: card,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _addTo(playlist),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  _MiniCover(
                                    colors: colors,
                                    size: 46,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: title,
                                          ),
                                        ),
                                        Text(
                                          playlist.countLabel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlaylistHomeStrip extends StatelessWidget {
  const PlaylistHomeStrip({
    super.key,
    required this.playlists,
    required this.onSeeAll,
    required this.onCreate,
    required this.onOpen,
    required this.onPlay,
  });

  final List<ClientAudioPlaylist> playlists;
  final VoidCallback onSeeAll;
  final VoidCallback onCreate;
  final ValueChanged<ClientAudioPlaylist> onOpen;
  final ValueChanged<ClientAudioPlaylist> onPlay;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Playlists',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: title,
                ),
              ),
            ),
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  color: _rose,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (playlists.isEmpty)
          _CreatePlaylistCard(onCreate: onCreate)
        else
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: playlists.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _CreatePlaylistCard(onCreate: onCreate, compact: true);
                }
                final playlist = playlists[index - 1];
                return _PlaylistCoverCard(
                  playlist: playlist,
                  onOpen: () => onOpen(playlist),
                  onPlay: () => onPlay(playlist),
                );
              },
            ),
          ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Collect audio and video into a set you can play later.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

Future<String?> promptPlaylistName(
  BuildContext context, {
  String initial = '',
  String title = 'New playlist',
  String confirmLabel = 'Create',
}) {
  return showCreateNameDialog(
    context: context,
    kind: CreateNameKind.playlist,
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
    fieldHint: 'Evening mix',
  );
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_rose, _violet]),
              ),
              child: const Icon(
                Icons.library_music_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Make your first mix',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Gather audio or video from any folder. Video plays as audio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: _rose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Create playlist',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
  });

  final ClientAudioPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF151B28) : Colors.white;
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final colors = playlistCoverColors(playlist.id);

    return Material(
      color: card,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _MiniCover(colors: colors, size: 64, name: playlist.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      playlist.countLabel,
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: playlist.tracks.isEmpty ? null : onPlay,
                style: IconButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: muted.withValues(alpha: 0.2),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCoverCard extends StatelessWidget {
  const _PlaylistCoverCard({
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
  });

  final ClientAudioPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = playlistCoverColors(playlist.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: 148,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -22,
                child: Icon(
                  Icons.album_rounded,
                  size: 110,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton.filled(
                        onPressed: playlist.tracks.isEmpty ? null : onPlay,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      playlist.countLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatePlaylistCard extends StatelessWidget {
  const _CreatePlaylistCard({
    required this.onCreate,
    this.compact = false,
  });

  final VoidCallback onCreate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF151B28) : Colors.white;
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Material(
      color: card,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onCreate,
        child: compact
            ? SizedBox(
                width: 132,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _rose.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.add_rounded, color: _rose),
                      ),
                      const Spacer(),
                      Text(
                        'New playlist',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: title,
                        ),
                      ),
                      Text(
                        'Start a mix',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_rose, _violet],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create a playlist',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: title,
                            ),
                          ),
                          Text(
                            'Name it, then add audio from your files',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.name,
    required this.subtitle,
    required this.colors,
  });

  final String name;
  final String subtitle;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: const Alignment(0.9, 0.7),
            child: Icon(
              Icons.album_rounded,
              size: 220,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayAction extends StatelessWidget {
  const _PlayAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _rose : _rose.withValues(alpha: 0.12),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: filled ? Colors.white : _rose),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : _rose,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBanner extends StatelessWidget {
  const _NowPlayingBanner({
    required this.track,
    required this.playing,
  });

  final ClientAudioTrack track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playing ? 'Now playing' : 'Paused',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.index,
    required this.track,
    required this.onPlay,
    required this.onRemove,
    this.current = false,
  });

  final int index;
  final ClientAudioTrack track;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = current
        ? (isDark ? const Color(0xFF3B1D36) : const Color(0xFFFCE7F3))
        : (isDark ? const Color(0xFF151B28) : Colors.white);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final subtitle = [
      if (current) (MediaSession.instance.playing.value ? 'Now playing' : 'Paused'),
      if (track.fromVideo) 'Video · audio only',
      if (track.folderName.isNotEmpty) track.folderName,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onPlay,
          leading: CircleAvatar(
            backgroundColor: current
                ? _rose
                : _rose.withValues(alpha: 0.14),
            foregroundColor: current ? Colors.white : _rose,
            child: current
                ? Icon(
                    MediaSession.instance.playing.value
                        ? Icons.graphic_eq_rounded
                        : Icons.pause_rounded,
                    size: 20,
                  )
                : Text(
                    '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: current ? _rose : title,
            ),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: current ? _rose.withValues(alpha: 0.85) : muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: muted),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: muted,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({
    required this.colors,
    required this.size,
    this.name,
  });

  final List<Color> colors;
  final double size;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final letter = (name ?? '').trim().isEmpty
        ? null
        : name!.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: letter == null
          ? Icon(
              Icons.album_rounded,
              color: Colors.white.withValues(alpha: 0.92),
              size: size * 0.46,
            )
          : Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.38,
              ),
            ),
    );
  }
}
