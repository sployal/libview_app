import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/phone_document_service.dart';

class PhonePdfScreen extends StatefulWidget {
  const PhonePdfScreen({super.key});

  @override
  State<PhonePdfScreen> createState() => _PhonePdfScreenState();
}

class _PhonePdfScreenState extends State<PhonePdfScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  List<PhoneDocument> _documents = [];
  bool _isLoading = true;
  bool _hasAllFilesAccess = false;
  String? _errorMessage;
  String _query = '';
  String _kindFilter = 'All';
  String? _preparingName;

  static const _kinds = ['All', 'PDF', 'Word', 'Excel', 'PowerPoint'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDocuments();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
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

  Future<void> _selectDocument(PhoneDocument document) async {
    if (_preparingName != null) return;

    setState(() {
      _preparingName = document.name;
    });

    try {
      final picked =
          await PhoneDocumentService.instance.prepareForUpload(document);
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
          _preparingName = null;
        });
      }
    }
  }

  Future<void> _browseWithPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
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

    Navigator.pop(
      context,
      PhonePickedDocument(
        name: file.name,
        path: path,
        sizeBytes: file.size,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'PDFs & documents',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Browse files',
            onPressed: _preparingName == null ? _browseWithPicker : null,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadDocuments(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search PDFs, Word, Excel, PowerPoint…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
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
                    color: selected ? Colors.white : const Color(0xFF374151),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Looking for documents…',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
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
                            actionLabel: 'Browse files',
                            onAction: _browseWithPicker,
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadDocuments(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final doc = filtered[index];
                                final color = _colorFor(doc.kind);
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
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    onTap: _preparingName == null
                                        ? () => _selectDocument(doc)
                                        : null,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: color.withValues(
                                        alpha: 0.12,
                                      ),
                                      foregroundColor: color,
                                      child: Icon(_iconFor(doc.kind)),
                                    ),
                                    title: Text(
                                      doc.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: preparing
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.upload_rounded,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
