import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_service.dart';
import '../services/phone_document_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _filesViewPrefKey = 'downloads_view_large_icons';

  List<DownloadItem> downloads = [];
  final Map<String, DownloadItem> _selected = {};
  bool isLoading = true;
  bool _useLargeIcons = false;

  bool get _selectionMode => _selected.isNotEmpty;

  String _keyFor(DownloadItem item) {
    if (item.filePath.isNotEmpty) return item.filePath;
    return item.contentUri ?? item.name;
  }

  @override
  void initState() {
    super.initState();
    DownloadService.listVersion.addListener(_onDownloadsChanged);
    _loadFilesViewPreference();
    _loadDownloads(showSpinner: true);
  }

  Future<void> _loadFilesViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _useLargeIcons = prefs.getBool(_filesViewPrefKey) ?? false;
    });
  }

  Future<void> _toggleFilesView() async {
    setState(() {
      _useLargeIcons = !_useLargeIcons;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filesViewPrefKey, _useLargeIcons);
  }

  @override
  void dispose() {
    DownloadService.listVersion.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    _loadDownloads();
  }

  Future<void> _loadDownloads({bool showSpinner = false}) async {
    if (showSpinner && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    final loadedDownloads = await DownloadService.getDownloads();
    if (!mounted) return;

    setState(() {
      downloads = loadedDownloads;
      isLoading = false;
      final keys = loadedDownloads.map(_keyFor).toSet();
      _selected.removeWhere((key, _) => !keys.contains(key));
    });
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  void _toggleSelected(DownloadItem download) {
    final key = _keyFor(download);
    setState(() {
      if (_selected.containsKey(key)) {
        _selected.remove(key);
      } else {
        _selected[key] = download;
      }
    });
  }

  void _onTap(DownloadItem download) {
    if (_selectionMode) {
      _toggleSelected(download);
      return;
    }
    _openFile(download);
  }

  void _onLongPress(DownloadItem download) {
    _toggleSelected(download);
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == downloads.length) {
        _selected.clear();
        return;
      }
      for (final download in downloads) {
        _selected[_keyFor(download)] = download;
      }
    });
  }

  Future<void> _openFile(DownloadItem download) async {
    try {
      await DownloadService.openDownloadedFile(download);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _shareFiles(List<DownloadItem> items) async {
    if (items.isEmpty) return;
    try {
      await DownloadService.shareDownloads(items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _shareFile(DownloadItem download) => _shareFiles([download]);

  Future<void> _shareSelected() async {
    await _shareFiles(_selected.values.toList());
  }

  Future<void> _deleteDownload(DownloadItem download) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text('Are you sure you want to delete "${download.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteItems([download], snackbar: 'Deleted ${download.name}');
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selected.values.toList();
    if (items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(items.length == 1 ? 'Delete Download' : 'Delete Downloads'),
        content: Text(
          items.length == 1
              ? 'Are you sure you want to delete "${items.first.name}"?'
              : 'Are you sure you want to delete ${items.length} files?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final label = items.length == 1
          ? 'Deleted ${items.first.name}'
          : 'Deleted ${items.length} files';
      await _deleteItems(items, snackbar: label);
    }
  }

  Future<void> _deleteItems(
    List<DownloadItem> items, {
    required String snackbar,
  }) async {
    final deleted = await DownloadService.deleteDownloads(items);
    if (deleted > 0) {
      _clearSelection();
      await _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackbar),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Color _getFileColor(String type) {
    switch (type) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'DOC':
        return const Color(0xFF3B82F6);
      case 'PPT':
        return const Color(0xFFF59E0B);
      case 'XLS':
        return const Color(0xFF10B981);
      case 'IMG':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'DOC':
        return Icons.description_rounded;
      case 'PPT':
        return Icons.slideshow_rounded;
      case 'XLS':
        return Icons.table_chart_rounded;
      case 'IMG':
        return Icons.image_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  BoxDecoration _fileCardDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? const Color(0xFFEEF2FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: selected ? Border.all(color: const Color(0xFF6366F1)) : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _overflowMenu(DownloadItem download) {
    return PopupMenuButton<String>(
      tooltip: 'File options',
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_vert_rounded,
        color: Color(0xFF9CA3AF),
      ),
      onSelected: (value) {
        switch (value) {
          case 'open':
            _openFile(download);
            break;
          case 'share':
            _shareFile(download);
            break;
          case 'delete':
            _deleteDownload(download);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 18),
              SizedBox(width: 12),
              Text('Open'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Text(
                'Share',
                style: TextStyle(color: Color(0xFF6366F1)),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red),
              SizedBox(width: 12),
              Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: downloads.length,
      itemBuilder: (context, index) {
        final download = downloads[index];
        final fileColor = _getFileColor(download.type);
        final fileIcon = _getFileIcon(download.type);
        final selected = _selected.containsKey(_keyFor(download));

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: _fileCardDecoration(selected: selected),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onTap(download),
              onLongPress: () => _onLongPress(download),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF6366F1)
                            : fileColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        selected ? Icons.check_rounded : fileIcon,
                        color: selected ? Colors.white : fileColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            download.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${download.subject} • ${DownloadService.formatFileSize(download.size)} • ${DownloadService.formatDate(download.date)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_selectionMode) _overflowMenu(download),
                    if (_selectionMode)
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF9CA3AF),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLargeIconsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: downloads.length,
          itemBuilder: (context, index) {
            final download = downloads[index];
            final fileColor = _getFileColor(download.type);
            final fileIcon = _getFileIcon(download.type);
            final selected = _selected.containsKey(_keyFor(download));

            return Container(
              decoration: _fileCardDecoration(selected: selected),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onTap(download),
                  onLongPress: () => _onLongPress(download),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: _DownloadPreview(
                                key: ValueKey(
                                  '${download.filePath}:${download.contentUri}',
                                ),
                                download: download,
                                color: fileColor,
                                icon: fileIcon,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: _selectionMode
                                  ? Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.circle_outlined,
                                        color: selected
                                            ? const Color(0xFF6366F1)
                                            : Colors.white,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black26,
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    )
                                  : _overflowMenu(download),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                        child: Column(
                          children: [
                            Text(
                              download.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DownloadService.formatFileSize(download.size),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.length;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel',
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _selectionMode ? '$selectedCount selected' : 'Downloads',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              tooltip: selectedCount == downloads.length
                  ? 'Deselect all'
                  : 'Select all',
              icon: Icon(
                selectedCount == downloads.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: _selectAll,
            ),
          ] else ...[
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
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadDownloads,
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _shareSelected,
                        icon: const Icon(Icons.share_rounded),
                        label: Text(
                          selectedCount == 1 ? 'Share' : 'Share $selectedCount',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_rounded),
                        label: Text(
                          selectedCount == 1
                              ? 'Delete'
                              : 'Delete $selectedCount',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : downloads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No downloads yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloaded files will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : _selectionMode
                  ? (_useLargeIcons
                      ? _buildLargeIconsGrid()
                      : _buildDetailsList())
                  : RefreshIndicator(
                      onRefresh: _loadDownloads,
                      color: const Color(0xFF6366F1),
                      child: _useLargeIcons
                          ? _buildLargeIconsGrid()
                          : _buildDetailsList(),
                    ),
      ),
    );
  }
}

class _DownloadPreview extends StatefulWidget {
  final DownloadItem download;
  final Color color;
  final IconData icon;

  const _DownloadPreview({
    super.key,
    required this.download,
    required this.color,
    required this.icon,
  });

  @override
  State<_DownloadPreview> createState() => _DownloadPreviewState();
}

class _DownloadPreviewState extends State<_DownloadPreview> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _DownloadPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.download.filePath != widget.download.filePath ||
        oldWidget.download.contentUri != widget.download.contentUri) {
      _thumbnailPath = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final download = widget.download;
    final localPath = download.filePath;
    if (download.type == 'IMG' &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      if (!mounted) return;
      setState(() => _thumbnailPath = localPath);
      return;
    }

    final path = await PhoneDocumentService.instance.thumbnailPathFor(
      key: '${download.filePath}:${download.contentUri}:${download.date}',
      fileName: download.name,
      path: localPath.isEmpty ? null : localPath,
      uri: download.contentUri,
      modifiedMs: DateTime.tryParse(download.date)?.millisecondsSinceEpoch ?? 0,
    );
    if (!mounted) return;
    setState(() => _thumbnailPath = path);
  }

  Widget _fallback() {
    return ColoredBox(
      color: widget.color.withOpacity(0.1),
      child: Center(
        child: Icon(
          widget.icon,
          color: widget.color,
          size: 56,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _thumbnailPath;
    if (path == null || path.isEmpty) {
      return _fallback();
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }
}