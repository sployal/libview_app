import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/phone_document_service.dart';
import 'document_reader.dart';

class BrowseDocumentsScreen extends StatefulWidget {
  const BrowseDocumentsScreen({super.key});

  @override
  State<BrowseDocumentsScreen> createState() => _BrowseDocumentsScreenState();
}

class _BrowseDocumentsScreenState extends State<BrowseDocumentsScreen>
    with WidgetsBindingObserver {
  static const _kinds = ['All', 'PDF', 'Word', 'Excel', 'PowerPoint'];
  static const _filesViewPrefKey = 'browse_documents_view_large_icons';

  final TextEditingController _searchController = TextEditingController();
  List<PhoneDocument> _documents = [];
  bool _isLoading = true;
  bool _hasAllFilesAccess = false;
  bool _isOpening = false;
  bool _useLargeIcons = false;
  String? _errorMessage;
  String _query = '';
  String _kindFilter = 'All';
  String? _openingKey;
  final Map<String, PhoneDocument> _selected = {};

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
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isLoading &&
        !_isOpening &&
        !_selectionMode) {
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
      final hasAll = await PhoneDocumentService.instance.hasAllFilesAccess();
      final documents = await PhoneDocumentService.instance.listDocuments();
      if (!mounted) return;
      setState(() {
        _hasAllFilesAccess = hasAll;
        _documents = documents;
        _isLoading = false;
        final keys = documents.map((doc) => doc.key).toSet();
        _selected.removeWhere((key, _) => !keys.contains(key));
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
    return _documents.where((doc) {
      if (_kindFilter != 'All' && doc.kind != _kindFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return doc.name.toLowerCase().contains(query) ||
          doc.kind.toLowerCase().contains(query) ||
          doc.extension.contains(query);
    }).toList(growable: false);
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  void _toggleSelected(PhoneDocument document) {
    final key = document.key;
    setState(() {
      if (_selected.containsKey(key)) {
        _selected.remove(key);
      } else {
        _selected[key] = document;
      }
    });
  }

  void _onTap(PhoneDocument document) {
    if (_isOpening) return;
    if (_selectionMode) {
      _toggleSelected(document);
      return;
    }
    _openDocument(document);
  }

  void _onLongPress(PhoneDocument document) {
    if (_isOpening) return;
    _toggleSelected(document);
  }

  void _selectAll() {
    final visible = _filtered;
    setState(() {
      if (_selected.length == visible.length && visible.isNotEmpty) {
        _selected.clear();
        return;
      }
      for (final document in visible) {
        _selected[document.key] = document;
      }
    });
  }

  Future<void> _shareDocuments(List<PhoneDocument> documents) async {
    if (documents.isEmpty) return;
    try {
      await PhoneDocumentService.instance.shareDocuments(documents);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareSelected() async {
    await _shareDocuments(_selected.values.toList());
  }

  Future<void> _deleteSelected() async {
    final items = _selected.values.toList();
    if (items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(items.length == 1 ? 'Delete file' : 'Delete files'),
        content: Text(
          items.length == 1
              ? 'Are you sure you want to delete "${items.first.name}" from this phone?'
              : 'Are you sure you want to delete ${items.length} files from this phone?',
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

    if (confirmed != true) return;

    final deleted =
        await PhoneDocumentService.instance.deleteDocuments(items);
    if (!mounted) return;
    if (deleted > 0) {
      _clearSelection();
      await _loadDocuments(requestPermission: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted == 1
                ? 'Deleted ${items.first.name}'
                : 'Deleted $deleted files',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete these files'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openDocument(PhoneDocument document) async {
    if (_isOpening) return;

    setState(() {
      _isOpening = true;
      _openingKey = document.key;
    });

    try {
      await DocumentReaderScreen.open(
        context,
        fileName: document.name,
        path: document.path,
        uri: document.uri,
        openExternally: () =>
            PhoneDocumentService.instance.openDocument(document),
      );
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
          _isOpening = false;
          _openingKey = null;
        });
      }
    }
  }

  Future<void> _browseWithPicker() async {
    if (_isOpening) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
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
      dialogTitle: 'Open a document',
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the selected document'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isOpening = true);
    try {
      await PhoneDocumentService.instance.openPath(path, fileName: file.name);
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
        setState(() => _isOpening = false);
      }
    }
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

  BoxDecoration _docCardDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? const Color(0xFFEEF2FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: selected ? Border.all(color: const Color(0xFF6366F1)) : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildDetailsList(List<PhoneDocument> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final color = _colorFor(doc.kind);
        final opening = _openingKey == doc.key;
        final selected = _selected.containsKey(doc.key);
        final size = _formatSize(doc.sizeBytes);
        final when = _formatDate(doc.modifiedMs);
        final meta = [
          doc.kind,
          if (size.isNotEmpty) size,
          if (when.isNotEmpty) when,
        ].join(' · ');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: _docCardDecoration(selected: selected),
          child: ListTile(
            onTap: _isOpening ? null : () => _onTap(doc),
            onLongPress: _isOpening ? null : () => _onLongPress(doc),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: selected
                  ? const Color(0xFF6366F1)
                  : color.withValues(alpha: 0.12),
              foregroundColor: selected ? Colors.white : color,
              child: Icon(selected ? Icons.check_rounded : _iconFor(doc.kind)),
            ),
            title: Text(
              doc.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            subtitle: Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black),
            ),
            trailing: opening
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : _selectionMode
                            ? Icons.circle_outlined
                            : Icons.open_in_new_rounded,
                    color: selected
                        ? const Color(0xFF6366F1)
                        : Colors.black,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLargeIconsGrid(List<PhoneDocument> filtered) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
            final opening = _openingKey == doc.key;
            final selected = _selected.containsKey(doc.key);

            return Container(
              decoration: _docCardDecoration(selected: selected),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isOpening ? null : () => _onTap(doc),
                  onLongPress: _isOpening ? null : () => _onLongPress(doc),
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
                              child: _LocalDocPreview(
                                key: ValueKey(doc.key),
                                document: doc,
                                color: color,
                                icon: _iconFor(doc.kind),
                              ),
                            ),
                            if (opening)
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
                                    : _selectionMode
                                        ? Icons.circle_outlined
                                        : Icons.open_in_new_rounded,
                                color: selected
                                    ? const Color(0xFF6366F1)
                                    : Colors.black54,
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
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
          _selectionMode ? '$selectedCount selected' : 'Browse files',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: selectedCount == filtered.length
                  ? 'Deselect all'
                  : 'Select all',
              icon: Icon(
                selectedCount == filtered.length && filtered.isNotEmpty
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: _selectAll,
            )
          else ...[
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
              tooltip: 'Open from Files',
              onPressed: _isOpening ? null : _browseWithPicker,
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
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _shareSelected,
                        icon: const Icon(Icons.share_rounded),
                        label: Text(
                          selectedCount == 1
                              ? 'Share'
                              : 'Share $selectedCount',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                hintText: 'Search PDFs, Word, Excel, PowerPoint…',
                hintStyle: const TextStyle(color: Colors.black54),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.black,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.black,
                        ),
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _kinds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final kind = _kinds[index];
                final selected = _kindFilter == kind;
                return ChoiceChip(
                  label: Text(kind),
                  selected: selected,
                  onSelected: (_) => setState(() => _kindFilter = kind),
                  selectedColor: const Color(0xFF6366F1),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFE5E7EB),
                  ),
                  showCheckmark: false,
                );
              },
            ),
          ),
          if (!_hasAllFilesAccess && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Material(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.folder_off_rounded,
                    color: Color(0xFF6366F1),
                  ),
                  title: const Text(
                    'Allow all-files access to see every document',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final granted =
                          await PhoneDocumentService.instance.requestAccess();
                      if (!granted) {
                        await openAppSettings();
                      }
                      if (!mounted) return;
                      await _loadDocuments(requestPermission: false);
                    },
                    child: const Text('Enable'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6366F1),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Looking for documents…',
                          style: TextStyle(
                            color: Colors.black,
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
                            actionLabel: 'Open from Files',
                            onAction: _browseWithPicker,
                          )
                        : RefreshIndicator(
                            onRefresh: _selectionMode
                                ? () async {}
                                : () => _loadDocuments(),
                            notificationPredicate: (_) => !_selectionMode,
                            child: _useLargeIcons
                                ? _buildLargeIconsGrid(filtered)
                                : _buildDetailsList(filtered),
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

  const _LocalDocPreview({
    super.key,
    required this.document,
    required this.color,
    required this.icon,
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
      color: widget.color.withValues(alpha: 0.1),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
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
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black),
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
