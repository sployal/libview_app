import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../services/phone_document_service.dart';
import '../ui/adaptive_layout.dart';
import '../ui/file_sort.dart';

class PhoneAudioScreen extends StatefulWidget {
  const PhoneAudioScreen({super.key});

  @override
  State<PhoneAudioScreen> createState() => _PhoneAudioScreenState();
}

class _PhoneAudioScreenState extends State<PhoneAudioScreen>
    with WidgetsBindingObserver {
  static const int _maxSelection = 10;
  static const _kinds = ['All', 'MP3', 'WAV', 'M4A', 'FLAC', 'OGG'];
  static const _filesViewPrefKey = 'phone_audio_view_large_icons';
  static const _filesSortPrefKey = 'phone_audio_sort_mode';

  final TextEditingController _searchController = TextEditingController();
  final Map<String, PhoneDocument> _selected = {};
  List<PhoneDocument> _files = [];
  bool _isLoading = true;
  bool _isPreparing = false;
  bool _useLargeIcons = false;
  FileSortMode _fileSort = FileSortMode.nameAz;
  String? _errorMessage;
  String _query = '';
  String _kindFilter = 'All';
  String? _preparingName;
  VideoPlayerController? _preview;
  String? _previewKey;
  bool _previewLoading = false;
  bool _previewSeeking = false;
  double _previewSeekMs = 0;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFilesViewPreference();
    _loadAudio();
  }

  Future<void> _loadFilesViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _useLargeIcons = prefs.getBool(_filesViewPrefKey) ?? false;
      _fileSort = FileSortModeX.fromStorage(prefs.getString(_filesSortPrefKey));
    });
  }

  Future<void> _toggleFilesView() async {
    setState(() {
      _useLargeIcons = !_useLargeIcons;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filesViewPrefKey, _useLargeIcons);
  }

  Future<void> _openFileSort() async {
    final next = await showFileSortSheet(
      context: context,
      selected: _fileSort,
      includeUploaded: false,
    );
    if (next == null || !mounted || next == _fileSort) return;
    setState(() {
      _fileSort = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filesSortPrefKey, next.storageValue);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _disposePreview();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _preview?.pause();
    }
    if (state == AppLifecycleState.resumed &&
        !_isLoading &&
        !_selectionMode &&
        !_isPreparing) {
      _loadAudio(requestPermission: false);
    }
  }

  Future<void> _loadAudio({bool requestPermission = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (requestPermission) {
        await PhoneDocumentService.instance.requestAudioAccess();
      }
      final files = await PhoneDocumentService.instance.listAudio();
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load audio from this phone.';
      });
    }
  }

  List<PhoneDocument> get _filtered {
    final query = _query.trim().toLowerCase();
    final filtered = _files.where((file) {
      if (_kindFilter != 'All' && file.kind != _kindFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return file.name.toLowerCase().contains(query) ||
          file.kind.toLowerCase().contains(query) ||
          file.extension.contains(query);
    });
    return FileSort.apply(
      filtered,
      mode: _fileSort,
      nameOf: (file) => file.name,
      typeOf: (file) => file.kind,
      sizeOf: (file) => file.sizeBytes,
      dateOf: (file) => DateTime.fromMillisecondsSinceEpoch(file.modifiedMs),
    );
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  void _onLongPress(PhoneDocument file) {
    if (_isPreparing) return;
    _toggleSelected(file);
  }

  void _onTap(PhoneDocument file) {
    if (_isPreparing) return;
    if (_selectionMode) {
      _toggleSelected(file);
      return;
    }
    _prepareFiles([file]);
  }

  void _toggleSelected(PhoneDocument file) {
    final key = file.key;
    final atLimit =
        !_selected.containsKey(key) && _selected.length >= _maxSelection;
    if (atLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can upload up to 10 audio files at a time'),
          backgroundColor: Color(0xFF111827),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      if (_selected.containsKey(key)) {
        _selected.remove(key);
      } else {
        _selected[key] = file;
      }
    });
  }

  void _onPreviewTick() {
    if (!mounted || _previewSeeking) return;
    setState(() {});
    final controller = _preview;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero &&
        !controller.value.isPlaying) {
      controller.seekTo(Duration.zero);
    }
  }

  Future<void> _disposePreview() async {
    final controller = _preview;
    _preview = null;
    _previewKey = null;
    _previewLoading = false;
    _previewSeeking = false;
    if (controller == null) return;
    controller.removeListener(_onPreviewTick);
    await controller.pause();
    await controller.dispose();
  }

  Future<void> _togglePreview(PhoneDocument file) async {
    if (_isPreparing) return;
    if (_previewKey == file.key && _preview != null) {
      if (_preview!.value.isPlaying) {
        await _preview!.pause();
      } else {
        await _preview!.play();
      }
      if (mounted) setState(() {});
      return;
    }

    await _disposePreview();
    if (!mounted) return;
    setState(() {
      _previewKey = file.key;
      _previewLoading = true;
    });

    try {
      final path = await PhoneDocumentService.instance.copyToReadablePath(
        fileName: file.name,
        path: file.path,
        uri: file.uri,
      );
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      controller.addListener(_onPreviewTick);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _preview = controller;
        _previewLoading = false;
      });
    } catch (_) {
      await _disposePreview();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not play this audio'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _isPreviewing(PhoneDocument file) => _previewKey == file.key;

  bool _isPreviewPlaying(PhoneDocument file) =>
      _isPreviewing(file) && (_preview?.value.isPlaying ?? false);

  String _formatClock(Duration value) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(value.inMinutes.remainder(60))}:${two(value.inSeconds.remainder(60))}';
  }

  Widget _previewSlider({required Color accent, required Color muted}) {
    final controller = _preview;
    final ready = controller != null && controller.value.isInitialized;
    final duration = ready ? controller.value.duration : Duration.zero;
    final maxMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final position = !ready
        ? 0.0
        : (_previewSeeking
              ? _previewSeekMs
              : controller.value.position.inMilliseconds
                    .clamp(0, maxMs)
                    .toDouble());
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: position,
            max: maxMs.toDouble(),
            activeColor: accent,
            inactiveColor: muted.withValues(alpha: 0.28),
            onChanged: !ready
                ? null
                : (value) {
                    setState(() {
                      _previewSeeking = true;
                      _previewSeekMs = value;
                    });
                  },
            onChangeEnd: !ready
                ? null
                : (value) async {
                    await controller.seekTo(
                      Duration(milliseconds: value.round()),
                    );
                    if (!mounted) return;
                    setState(() => _previewSeeking = false);
                  },
          ),
        ),
        Row(
          children: [
            Text(
              _formatClock(
                Duration(milliseconds: position.round()),
              ),
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              _formatClock(duration),
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playButton(PhoneDocument file, {required Color color}) {
    final loading = _isPreviewing(file) && _previewLoading;
    final playing = _isPreviewPlaying(file);
    return IconButton(
      tooltip: playing ? 'Pause' : 'Listen',
      onPressed: _isPreparing ? null : () => _togglePreview(file),
      icon: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              color: color,
              size: 34,
            ),
    );
  }

  Future<void> _prepareFiles(List<PhoneDocument> files) async {
    if (_isPreparing || files.isEmpty) return;
    await _disposePreview();
    setState(() {
      _isPreparing = true;
      _preparingName = files.first.name;
    });
    try {
      final picked = <PhonePickedDocument>[];
      for (final file in files) {
        if (!mounted) return;
        setState(() => _preparingName = file.name);
        picked.add(await PhoneDocumentService.instance.prepareForUpload(file));
      }
      if (!mounted) return;
      Navigator.pop(context, picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
          _preparingName = null;
        });
      }
    }
  }

  Future<void> _browseWithPicker() async {
    if (_isPreparing) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final safPicked = await PhoneDocumentService.instance.pickForUpload(
        mimeTypes: PhoneDocumentService.audioUploadMimeTypes,
      );
      if (!mounted) return;
      if (safPicked.isEmpty) return;
      Navigator.pop(context, safPicked.take(_maxSelection).toList());
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: const [
        'mp3',
        'wav',
        'aac',
        'm4a',
        'flac',
        'ogg',
        'oga',
        'opus',
        'wma',
        'amr',
        'aiff',
        'aif',
      ],
      withData: false,
      dialogTitle: 'Select audio to upload',
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = <PhonePickedDocument>[];
    for (final file in result.files.take(_maxSelection)) {
      final path = file.path;
      if (path == null || path.isEmpty) continue;
      picked.add(
        await PhonePickedDocument.fromFile(
          name: file.name,
          path: path,
          sizeBytes: file.size,
        ),
      );
    }
    if (picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the selected audio'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, picked);
  }

  Color _colorFor(String kind) {
    switch (kind) {
      case 'MP3':
        return const Color(0xFFEC4899);
      case 'WAV':
        return const Color(0xFF0EA5E9);
      case 'M4A':
        return const Color(0xFF8B5CF6);
      case 'FLAC':
        return const Color(0xFF10B981);
      case 'OGG':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEC4899);
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int modifiedMs) {
    if (modifiedMs <= 0) return '';
    return timeago.format(DateTime.fromMillisecondsSinceEpoch(modifiedMs));
  }

  BoxDecoration _cardDecoration({
    required bool isDark,
    required bool selected,
  }) {
    return BoxDecoration(
      color: selected
          ? (isDark
              ? const Color(0xFF831843).withValues(alpha: 0.35)
              : const Color(0xFFFDF2F8))
          : (isDark ? const Color(0xFF1F2937) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      border: selected
          ? Border.all(color: const Color(0xFFEC4899), width: 1.5)
          : null,
      boxShadow: [
        if (!isDark)
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalCount = _files.length;
    final matchCount = filtered.length;
    final filesNoun = totalCount == 1 ? 'file' : 'files';
    final isFiltering = _query.trim().isNotEmpty || _kindFilter != 'All';
    final countLabel = _isLoading
        ? 'Looking for audio…'
        : isFiltering
            ? '$matchCount of $totalCount $filesNoun'
            : '$totalCount $filesNoun';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    const accent = Color(0xFFEC4899);
    final fieldFill = isDark ? const Color(0xFF1F2937) : Colors.white;
    final borderColor = _query.isNotEmpty
        ? accent
        : (isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB));

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          foregroundColor: titleColor,
          elevation: 0,
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSelection,
                )
              : null,
          title: Text(
            _selectionMode
                ? '${_selected.length} of $_maxSelection selected'
                : 'Audio on this phone',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          actions: [
            if (!_selectionMode) ...[
              IconButton(
                tooltip: 'Sort · ${_fileSort.label}',
                icon: const Icon(Icons.sort_rounded),
                onPressed: _openFileSort,
              ),
              IconButton(
                tooltip: _useLargeIcons ? 'Details view' : 'Large icons',
                icon: Icon(
                  _useLargeIcons
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
                onPressed: _toggleFilesView,
              ),
              IconButton(
                tooltip: 'Browse files',
                onPressed: _isPreparing ? null : _browseWithPicker,
                icon: const Icon(Icons.folder_open_rounded),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _isLoading ? null : () => _loadAudio(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _selectionMode
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _isPreparing
                        ? null
                        : () => _prepareFiles(_selected.values.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: _isPreparing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.upload_rounded),
                    label: Text(
                      _isPreparing
                          ? 'Preparing…'
                          : 'Upload ${_selected.length} file${_selected.length == 1 ? '' : 's'}',
                    ),
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: AdaptiveLayout.pagePadding(context).copyWith(top: 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                style: TextStyle(color: titleColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search music, recordings, voice notes…',
                  hintStyle: TextStyle(color: muted, fontSize: 15),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _query.isNotEmpty ? accent : muted,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.close_rounded, color: muted),
                        ),
                  filled: true,
                  fillColor: fieldFill,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: AdaptiveLayout.pagePadding(context),
                scrollDirection: Axis.horizontal,
                itemCount: _kinds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final kind = _kinds[index];
                  final selected = _kindFilter == kind;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _kindFilter = kind);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? accent : fieldFill,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? accent
                              : (isDark
                                  ? const Color(0xFF4B5563)
                                  : const Color(0xFFD1D5DB)),
                        ),
                      ),
                      child: Text(
                        kind,
                        style: TextStyle(
                          color: selected ? Colors.white : muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: AdaptiveLayout.pagePadding(context).copyWith(
                top: 10,
                bottom: 4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Looking for audio…',
                            style: TextStyle(color: muted, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? _AudioEmptyState(
                          icon: Icons.error_outline_rounded,
                          title: _errorMessage!,
                          titleColor: titleColor,
                          muted: muted,
                          actionLabel: 'Try again',
                          onAction: _loadAudio,
                        )
                      : filtered.isEmpty
                          ? _AudioEmptyState(
                              icon: Icons.audiotrack_rounded,
                              title: _query.isEmpty
                                  ? 'No audio found on this phone'
                                  : 'No audio matches “$_query”',
                              subtitle:
                                  'Grant audio access, or tap browse to pick a file.',
                              titleColor: titleColor,
                              muted: muted,
                              actionLabel: 'Browse files',
                              onAction: _browseWithPicker,
                            )
                          : RefreshIndicator(
                              color: accent,
                              onRefresh: _selectionMode
                                  ? () async {}
                                  : () => _loadAudio(),
                              child: _useLargeIcons
                                  ? _buildGrid(
                                      filtered,
                                      isDark: isDark,
                                      titleColor: titleColor,
                                      muted: muted,
                                    )
                                  : _buildList(
                                      filtered,
                                      isDark: isDark,
                                      titleColor: titleColor,
                                      muted: muted,
                                    ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<PhoneDocument> filtered, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
  }) {
    final pagePad = AdaptiveLayout.pagePadding(context);
    return ListView.builder(
      padding: pagePad.copyWith(
        top: 4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final file = filtered[index];
        final color = _colorFor(file.kind);
        final selected = _selected.containsKey(file.key);
        final preparing = _preparingName == file.name;
        final size = _formatSize(file.sizeBytes);
        final when = _formatDate(file.modifiedMs);
        final meta = [
          file.kind,
          if (size.isNotEmpty) size,
          if (when.isNotEmpty) when,
        ].join(' · ');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: _cardDecoration(isDark: isDark, selected: selected),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isPreparing ? null : () => _onTap(file),
              onLongPress: _isPreparing ? null : () => _onLongPress(file),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFFEC4899)
                                : color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: preparing
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFEC4899),
                                  ),
                                )
                              : Icon(
                                  selected
                                      ? Icons.check_rounded
                                      : Icons.audiotrack_rounded,
                                  color: selected ? Colors.white : color,
                                  size: 24,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                            ],
                          ),
                        ),
                        _playButton(file, color: color),
                      ],
                    ),
                    if (_isPreviewing(file)) ...[
                      const SizedBox(height: 4),
                      _previewSlider(accent: color, muted: muted),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    List<PhoneDocument> filtered, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
  }) {
    return GridView.builder(
      padding: AdaptiveLayout.pagePadding(context).copyWith(
        top: 4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final file = filtered[index];
        final color = _colorFor(file.kind);
        final selected = _selected.containsKey(file.key);
        final preparing = _preparingName == file.name;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isPreparing ? null : () => _onTap(file),
            onLongPress: _isPreparing ? null : () => _onLongPress(file),
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: _cardDecoration(isDark: isDark, selected: selected),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: color.withValues(alpha: 0.12),
                          child: Center(
                            child: preparing
                                ? const CircularProgressIndicator(
                                    color: Color(0xFFEC4899),
                                  )
                                : Icon(
                                    Icons.audiotrack_rounded,
                                    color: color,
                                    size: 40,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.upload_rounded,
                            color: selected
                                ? const Color(0xFFEC4899)
                                : muted,
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          right: 4,
                          child: Center(
                            child: _playButton(file, color: color),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      children: [
                        Text(
                          file.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        if (_isPreviewing(file))
                          _previewSlider(accent: color, muted: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AudioEmptyState extends StatelessWidget {
  const _AudioEmptyState({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.muted,
    required this.actionLabel,
    required this.onAction,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color titleColor;
  final Color muted;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: titleColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.4),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEC4899),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
