import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/phone_document_service.dart';
import '../ui/adaptive_layout.dart';
import '../ui/file_sort.dart';

class PhonePdfScreen extends StatefulWidget {
  const PhonePdfScreen({super.key});

  @override
  State<PhonePdfScreen> createState() => _PhonePdfScreenState();
}

class _PhonePdfScreenState extends State<PhonePdfScreen>
    with WidgetsBindingObserver {
  static const int _maxSelection = 5;
  static const _kinds = ['All', 'PDF', 'Word', 'Excel', 'PowerPoint'];
  static const _filesViewPrefKey = 'phone_pdf_view_large_icons';
  static const _filesSortPrefKey = 'phone_pdf_sort_mode';

  final TextEditingController _searchController = TextEditingController();
  final Map<String, PhoneDocument> _selected = {};
  List<PhoneDocument> _documents = [];
  bool _isLoading = true;
  bool _isPreparing = false;
  bool _useLargeIcons = false;
  FileSortMode _fileSort = FileSortMode.nameAz;
  String? _errorMessage;
  String _query = '';
  String _kindFilter = 'All';
  String? _preparingName;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFilesViewPreference();
    _loadDocuments();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isLoading &&
        !_selectionMode &&
        !_isPreparing) {
      _loadDocuments(requestPermission: false);
    }
  }

  Future<void> _loadDocuments({bool requestPermission = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (requestPermission) {
        await PhoneDocumentService.instance.requestAccess();
      }
      final documents = await PhoneDocumentService.instance.listDocuments();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load documents from this phone.';
      });
    }
  }

  List<PhoneDocument> get _filtered {
    final query = _query.trim().toLowerCase();
    final filtered = _documents.where((doc) {
      if (_kindFilter != 'All' && doc.kind != _kindFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return doc.name.toLowerCase().contains(query) ||
          doc.kind.toLowerCase().contains(query) ||
          doc.extension.contains(query);
    });
    return FileSort.apply(
      filtered,
      mode: _fileSort,
      nameOf: (doc) => doc.name,
      typeOf: (doc) => doc.kind,
      sizeOf: (doc) => doc.sizeBytes,
      dateOf: (doc) => DateTime.fromMillisecondsSinceEpoch(doc.modifiedMs),
    );
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  void _onLongPress(PhoneDocument document) {
    if (_isPreparing) return;
    _toggleSelected(document);
  }

  void _onTap(PhoneDocument document) {
    if (_isPreparing) return;
    if (_selectionMode) {
      _toggleSelected(document);
      return;
    }
    _uploadDocuments([document]);
  }

  void _toggleSelected(PhoneDocument document) {
    final key = document.key;
    final atLimit =
        !_selected.containsKey(key) && _selected.length >= _maxSelection;

    if (atLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can upload up to 5 documents at a time'),
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
        _selected[key] = document;
      }
    });
  }

  Future<void> _uploadDocuments(List<PhoneDocument> documents) async {
    if (_isPreparing || documents.isEmpty) return;

    setState(() {
      _isPreparing = true;
      _preparingName = documents.first.name;
    });

    try {
      final picked = <PhonePickedDocument>[];
      for (final document in documents) {
        if (!mounted) return;
        setState(() => _preparingName = document.name);
        picked.add(
          await PhoneDocumentService.instance.prepareForUpload(document),
        );
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
    if (Platform.isAndroid) {
      final safPicked = await PhoneDocumentService.instance.pickForUpload(
        mimeTypes: PhoneDocumentService.documentUploadMimeTypes,
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
        'pdf',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'txt',
        'rtf',
        'odt',
        'ods',
        'odp',
        'csv',
      ],
      withData: false,
      dialogTitle: 'Select a document to upload',
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
          content: Text('Could not open the selected document'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(context, picked);
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'Word':
        return Icons.description_rounded;
      case 'Excel':
        return Icons.table_chart_rounded;
      case 'PowerPoint':
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _colorFor(String kind) {
    switch (kind) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'Word':
        return const Color(0xFF3B82F6);
      case 'Excel':
        return const Color(0xFF10B981);
      case 'PowerPoint':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
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

  BoxDecoration _docCardDecoration({
    required bool isDark,
    required bool selected,
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

  Widget _buildDetailsList(
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
        final doc = filtered[index];
        final color = _colorFor(doc.kind);
        final selected = _selected.containsKey(doc.key);
        final preparing = _preparingName == doc.name;
        final size = _formatSize(doc.sizeBytes);
        final when = _formatDate(doc.modifiedMs);
        final meta = [
          doc.kind,
          if (size.isNotEmpty) size,
          if (when.isNotEmpty) when,
        ].join(' · ');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: _docCardDecoration(isDark: isDark, selected: selected),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isPreparing ? null : () => _onTap(doc),
              onLongPress: _isPreparing ? null : () => _onLongPress(doc),
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
                            : color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        selected ? Icons.check_rounded : _iconFor(doc.kind),
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
                            doc.name,
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
                    if (preparing)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.upload_rounded,
                        color: selected ? const Color(0xFF6366F1) : muted,
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

  Widget _buildLargeIconsGrid(
    List<PhoneDocument> filtered, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = AdaptiveLayout.gridCount(constraints.maxWidth);
        return GridView.builder(
          padding: AdaptiveLayout.pagePadding(context).copyWith(
            top: 4,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final doc = filtered[index];
            final color = _colorFor(doc.kind);
            final selected = _selected.containsKey(doc.key);
            final preparing = _preparingName == doc.name;

            return Container(
              decoration: _docCardDecoration(isDark: isDark, selected: selected),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isPreparing ? null : () => _onTap(doc),
                  onLongPress: _isPreparing ? null : () => _onLongPress(doc),
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
                              child: _LocalDocPreview(
                                key: ValueKey(doc.key),
                                document: doc,
                                color: color,
                                icon: _iconFor(doc.kind),
                                selected: selected,
                              ),
                            ),
                            if (preparing)
                              ColoredBox(
                                color: Colors.black.withValues(alpha: 0.35),
                                child: const Center(
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
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
                                    ? const Color(0xFF6366F1)
                                    : muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                        child: Text(
                          doc.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
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
    final filtered = _filtered;
    final totalCount = _documents.length;
    final matchCount = filtered.length;
    final filesNoun = totalCount == 1 ? 'file' : 'files';
    final isFiltering =
        _query.trim().isNotEmpty || _kindFilter != 'All';
    final countLabel = _isLoading
        ? 'Looking for documents…'
        : isFiltering
            ? '$matchCount of $totalCount $filesNoun'
            : '$totalCount $filesNoun';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    const accent = Color(0xFF6366F1);
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
                : 'PDFs & documents',
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
                onPressed: _isLoading ? null : () => _loadDocuments(),
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
                        : () => _uploadDocuments(_selected.values.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
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
                          : 'Upload ${_selected.length} document${_selected.length == 1 ? '' : 's'}',
                    ),
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: AdaptiveLayout.pagePadding(context).copyWith(top: 12),
              child: DecoratedBox(
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
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search PDFs, Word, Excel, PowerPoint…',
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
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? accent : card,
                        borderRadius: BorderRadius.circular(20),
                        border: selected
                            ? null
                            : Border.all(
                                color: isDark
                                    ? const Color(0xFF374151)
                                    : const Color(0xFFE5E7EB),
                              ),
                      ),
                      child: Text(
                        kind,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : (isDark
                                  ? const Color(0xFFE5E7EB)
                                  : const Color(0xFF374151)),
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
              child: Text(
                countLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: muted,
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Looking for documents…',
                            style: TextStyle(
                              color: muted,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? _EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: _errorMessage!,
                          titleColor: titleColor,
                          muted: muted,
                          actionLabel: 'Try again',
                          onAction: _loadDocuments,
                        )
                      : filtered.isEmpty
                          ? _EmptyState(
                              icon: Icons.insert_drive_file_outlined,
                              title: _query.isEmpty
                                  ? 'No documents found on this phone'
                                  : 'No documents match “$_query”',
                              subtitle:
                                  'Tap browse to pick a file from Files or Drive.',
                              titleColor: titleColor,
                              muted: muted,
                              actionLabel: 'Browse files',
                              onAction: _browseWithPicker,
                            )
                          : RefreshIndicator(
                              color: accent,
                              onRefresh: _selectionMode
                                  ? () async {}
                                  : () => _loadDocuments(),
                              child: _useLargeIcons
                                  ? _buildLargeIconsGrid(
                                      filtered,
                                      isDark: isDark,
                                      titleColor: titleColor,
                                      muted: muted,
                                    )
                                  : _buildDetailsList(
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
}

class _LocalDocPreview extends StatefulWidget {
  final PhoneDocument document;
  final Color color;
  final IconData icon;
  final bool selected;

  const _LocalDocPreview({
    super.key,
    required this.document,
    required this.color,
    required this.icon,
    required this.selected,
  });

  @override
  State<_LocalDocPreview> createState() => _LocalDocPreviewState();
}

class _LocalDocPreviewState extends State<_LocalDocPreview> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _LocalDocPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.key != widget.document.key) {
      _thumbnailPath = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final path =
        await PhoneDocumentService.instance.thumbnailPath(widget.document);
    if (!mounted) return;
    setState(() => _thumbnailPath = path);
  }

  Widget _fallback() {
    return ColoredBox(
      color: widget.selected
          ? const Color(0xFF6366F1).withValues(alpha: 0.12)
          : widget.color.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          widget.selected ? Icons.check_rounded : widget.icon,
          color: widget.selected ? const Color(0xFF6366F1) : widget.color,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color titleColor;
  final Color muted;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.titleColor,
    required this.muted,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: muted),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
