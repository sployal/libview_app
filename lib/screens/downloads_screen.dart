import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_service.dart';
import '../services/phone_document_service.dart';
import '../ui/adaptive_layout.dart';
import 'document_reader.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _filesViewPrefKey = 'downloads_view_large_icons';

  List<DownloadItem> downloads = [];
  final Map<String, DownloadItem> _selected = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool isLoading = true;
  bool _useLargeIcons = false;
  String _query = '';
  String _typeFilter = 'All';
  static const _typeFilters = ['All', 'PDF', 'DOC', 'PPT', 'IMG'];

  bool get _selectionMode => _selected.isNotEmpty;

  String _keyFor(DownloadItem item) {
    if (item.filePath.isNotEmpty) return item.filePath;
    return item.contentUri ?? item.name;
  }

  @override
  void initState() {
    super.initState();
    DownloadService.listVersion.addListener(_onDownloadsChanged);
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
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
    HapticFeedback.selectionClick();
    setState(() {
      _useLargeIcons = !_useLargeIcons;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filesViewPrefKey, _useLargeIcons);
  }

  @override
  void dispose() {
    DownloadService.listVersion.removeListener(_onDownloadsChanged);
    _searchController.dispose();
    _searchFocus.dispose();
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
    HapticFeedback.selectionClick();
    setState(_selected.clear);
  }

  void _toggleSelected(DownloadItem download) {
    HapticFeedback.selectionClick();
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
    HapticFeedback.lightImpact();
    _openFile(download);
  }

  void _onLongPress(DownloadItem download) {
    _toggleSelected(download);
  }

  void _selectAll(List<DownloadItem> items) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.length == items.length) {
        _selected.clear();
        return;
      }
      for (final download in items) {
        _selected[_keyFor(download)] = download;
      }
    });
  }

  List<DownloadItem> get _visibleDownloads {
    final query = _query.trim().toLowerCase();
    return downloads.where((item) {
      if (_typeFilter != 'All' && item.type != _typeFilter) return false;
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.subject.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openFile(DownloadItem download) async {
    try {
      await DocumentReaderScreen.open(
        context,
        fileName: download.name,
        path: download.filePath,
        uri: download.contentUri,
        openExternally: () => DownloadService.openDownloadedFile(download),
      );
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
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
        _showSnack(
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _shareFile(DownloadItem download) => _shareFiles([download]);

  Future<void> _shareSelected() async {
    await _shareFiles(_selected.values.toList());
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteDownload(DownloadItem download) async {
    final confirmed = await _confirmDelete(
      title: 'Delete Download',
      message: 'Are you sure you want to delete “${download.name}”?',
    );
    if (confirmed) {
      await _deleteItems([download], snackbar: 'Deleted ${download.name}');
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selected.values.toList();
    if (items.isEmpty) return;

    final confirmed = await _confirmDelete(
      title: items.length == 1 ? 'Delete Download' : 'Delete Downloads',
      message: items.length == 1
          ? 'Are you sure you want to delete “${items.first.name}”?'
          : 'Are you sure you want to delete ${items.length} files?',
    );

    if (confirmed) {
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
      if (mounted) _showSnack(snackbar);
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

  BoxDecoration _fileCardDecoration({
    required bool isDark,
    bool selected = false,
  }) {
    return BoxDecoration(
      color: selected
          ? (isDark
              ? const Color(0xFF312E81).withOpacity(0.45)
              : const Color(0xFFEEF2FF))
          : (isDark ? const Color(0xFF1F2937) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      border: selected
          ? Border.all(color: const Color(0xFF6366F1), width: 1.5)
          : null,
      boxShadow: [
        if (!isDark)
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
      ],
    );
  }

  Widget _overflowMenu(DownloadItem download, Color muted) {
    return PopupMenuButton<String>(
      tooltip: 'File options',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded, color: muted),
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
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new_rounded, size: 18),
              SizedBox(width: 12),
              Text('Open'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.ios_share_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Text('Share', style: TextStyle(color: Color(0xFF6366F1))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  DateTime? _parsedDate(DownloadItem item) => DateTime.tryParse(item.date);

  List<_DownloadSection> _sectionsFor(List<DownloadItem> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final buckets = <String, List<DownloadItem>>{
      'Today': [],
      'Yesterday': [],
      'This week': [],
      'Earlier': [],
    };

    for (final item in items) {
      final parsed = _parsedDate(item);
      if (parsed == null) {
        buckets['Earlier']!.add(item);
        continue;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day == today) {
        buckets['Today']!.add(item);
      } else if (day == yesterday) {
        buckets['Yesterday']!.add(item);
      } else if (!day.isBefore(weekAgo)) {
        buckets['This week']!.add(item);
      } else {
        buckets['Earlier']!.add(item);
      }
    }

    return buckets.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => _DownloadSection(entry.key, entry.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final visible = _visibleDownloads;
    final selectedCount = _selected.length;
    final pagePad = AdaptiveLayout.pagePadding(context);
    final bottomPad = AdaptiveLayout.bottomClearance(context);
    final sections = _sectionsFor(visible);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _clearSelection();
      },
      child: Scaffold(
        backgroundColor: background,
        bottomNavigationBar: _selectionMode
            ? _SelectionBar(
                isDark: isDark,
                count: selectedCount,
                onShare: _shareSelected,
                onDelete: _deleteSelected,
              )
            : null,
        body: RefreshIndicator(
          color: const Color(0xFF6366F1),
          onRefresh: _selectionMode ? () async {} : _loadDownloads,
          notificationPredicate: (_) => !_selectionMode,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              compactSliverAppBar(
                backgroundColor: background,
                foregroundColor: titleColor,
                leading: _selectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Cancel',
                        onPressed: _clearSelection,
                      )
                    : null,
                title: Text(
                  _selectionMode ? '$selectedCount selected' : 'Downloads',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AdaptiveLayout.isTablet(context) ? 22 : 20,
                    color: titleColor,
                  ),
                ),
                actions: [
                  if (_selectionMode)
                    IconButton(
                      tooltip: selectedCount == visible.length
                          ? 'Deselect all'
                          : 'Select all',
                      icon: Icon(
                        selectedCount == visible.length
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                      ),
                      onPressed: () => _selectAll(visible),
                    )
                  else ...[
                    if (downloads.isNotEmpty)
                      IconButton(
                        tooltip:
                            _useLargeIcons ? 'List view' : 'Large icons',
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
              SliverPadding(
                padding: pagePad.copyWith(top: 4, bottom: 8),
                sliver: SliverToBoxAdapter(
                  child: _buildIntro(
                    muted: muted,
                    card: card,
                    titleColor: titleColor,
                    isDark: isDark,
                  ),
                ),
              ),
              if (isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF6366F1),
                      ),
                    ),
                  ),
                )
              else if (downloads.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(muted: muted, titleColor: titleColor),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      _query.trim().isEmpty
                          ? 'Try a different filter'
                          : 'No files match your search',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                  ),
                )
              else if (_useLargeIcons)
                SliverPadding(
                  padding: pagePad.copyWith(top: 8, bottom: bottomPad),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          AdaptiveLayout.gridCount(constraints.crossAxisExtent);
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildGridTile(
                              visible[index],
                              isDark: isDark,
                              titleColor: titleColor,
                              muted: muted,
                            );
                          },
                          childCount: visible.length,
                        ),
                      );
                    },
                  ),
                )
              else
                ...sections.asMap().entries.expand((entry) {
                  final section = entry.value;
                  final isLast = entry.key == sections.length - 1;
                  return [
                    SliverPadding(
                      padding: pagePad.copyWith(top: 12, bottom: 6),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          section.title.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: pagePad.copyWith(
                        top: 0,
                        bottom: isLast ? bottomPad : 8,
                      ),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = AdaptiveLayout.listColumns(
                            constraints.crossAxisExtent,
                          );
                          Widget tile(int index, {required bool tight}) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: tight ? 0 : 10),
                              child: _buildListTile(
                                section.items[index],
                                isDark: isDark,
                                titleColor: titleColor,
                                muted: muted,
                              ),
                            );
                          }

                          if (columns == 1) {
                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) =>
                                    tile(index, tight: false),
                                childCount: section.items.length,
                              ),
                            );
                          }

                          return SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: 80,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => tile(index, tight: true),
                              childCount: section.items.length,
                            ),
                          );
                        },
                      ),
                    ),
                  ];
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro({
    required Color muted,
    required Color card,
    required Color titleColor,
    required bool isDark,
  }) {
    const accent = Color(0xFF6366F1);
    final highlighted = _searchFocus.hasFocus || _query.isNotEmpty;
    final fieldFill = isDark ? const Color(0xFF1F2937) : Colors.white;
    final borderColor = highlighted
        ? accent
        : (isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectionMode
              ? 'Tap files to add or remove them from the selection.'
              : isLoading
                  ? 'Loading files on this device'
                  : '${downloads.length} ${downloads.length == 1 ? 'file' : 'files'} saved on this device',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
        if (!_selectionMode && downloads.isNotEmpty) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: (value) => setState(() => _query = value),
              onTapOutside: (_) => _searchFocus.unfocus(),
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: titleColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search files',
                hintStyle: TextStyle(color: muted, fontSize: 15),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: highlighted ? accent : muted,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(Icons.close_rounded, color: muted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in _typeFilters)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _typeFilter = type);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: type == _typeFilter
                          ? const Color(0xFF7C83F8)
                          : card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: type == _typeFilter
                            ? const Color(0xFF7C83F8)
                            : (isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: type == _typeFilter
                            ? Colors.white
                            : muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildListTile(
    DownloadItem download, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
  }) {
    final fileColor = _getFileColor(download.type);
    final fileIcon = _getFileIcon(download.type);
    final selected = _selected.containsKey(_keyFor(download));

    return Container(
      decoration: _fileCardDecoration(isDark: isDark, selected: selected),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTap(download),
          onLongPress: () => _onLongPress(download),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF6366F1)
                        : fileColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : fileIcon,
                    color: selected ? Colors.white : fileColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${download.subject} · ${DownloadService.formatFileSize(download.size)} · ${DownloadService.formatDate(download.date)}',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                ),
                if (!_selectionMode) ...[
                  _overflowMenu(download, muted),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: muted,
                  ),
                ] else
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
  }

  Widget _buildGridTile(
    DownloadItem download, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
  }) {
    final fileColor = _getFileColor(download.type);
    final fileIcon = _getFileIcon(download.type);
    final selected = _selected.containsKey(_keyFor(download));

    return Container(
      decoration: _fileCardDecoration(isDark: isDark, selected: selected),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTap(download),
          onLongPress: () => _onLongPress(download),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
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
                          : _overflowMenu(download, muted),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DownloadService.formatFileSize(download.size),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
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

class _DownloadSection {
  const _DownloadSection(this.title, this.items);

  final String title;
  final List<DownloadItem> items;
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.isDark,
    required this.count,
    required this.onShare,
    required this.onDelete,
  });

  final bool isDark;
  final int count;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _barAction(
                  icon: Icons.ios_share_rounded,
                  label: count == 1 ? 'Share' : 'Share $count',
                  color: const Color(0xFF6366F1),
                  onTap: onShare,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
              ),
              Expanded(
                child: _barAction(
                  icon: Icons.delete_rounded,
                  label: count == 1 ? 'Delete' : 'Delete $count',
                  color: const Color(0xFFEF4444),
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.muted, required this.titleColor});

  final Color muted;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.download_rounded,
              size: 36,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No downloads yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Files you save from a unit will appear here, ready to open offline.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: muted),
          ),
        ],
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
  bool _loading = true;

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
      _loading = true;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final download = widget.download;
    final localPath = download.filePath;

    final path = await PhoneDocumentService.instance.thumbnailPathFor(
      key: '${download.filePath}:${download.contentUri}:${download.date}',
      fileName: download.name,
      path: localPath.isEmpty ? null : localPath,
      uri: download.contentUri,
      modifiedMs: DateTime.tryParse(download.date)?.millisecondsSinceEpoch ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _thumbnailPath = path;
      _loading = false;
    });
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
    if (_loading) {
      return ColoredBox(
        color: widget.color.withOpacity(0.08),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
            ),
          ),
        ),
      );
    }
    final path = _thumbnailPath;
    if (path == null || path.isEmpty) {
      return _fallback();
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }
}
