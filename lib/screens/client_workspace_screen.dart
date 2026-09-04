import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/client_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_service.dart';
import '../ui/file_sort.dart';
import 'client_files_browser_screen.dart';

class ClientWorkspaceScreen extends StatelessWidget {
  const ClientWorkspaceScreen({
    super.key,
    this.workspace,
    this.onBack,
  });

  final ClientWorkspace? workspace;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (workspace != null) {
      return _ClientFilesHome(client: workspace!, onBack: onBack);
    }

    return StreamBuilder<ClientWorkspace?>(
      stream: ClientService.instance.watchClientForCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final client = snapshot.data;
        if (client == null || client.driveFolderId.isEmpty) {
          return _ClientUnassignedState(onBack: onBack);
        }
        return _ClientFilesHome(client: client, onBack: onBack);
      },
    );
  }
}

class _ClientFilesHome extends StatefulWidget {
  const _ClientFilesHome({
    required this.client,
    this.onBack,
  });

  final ClientWorkspace client;
  final VoidCallback? onBack;

  @override
  State<_ClientFilesHome> createState() => _ClientFilesHomeState();
}

class _ClientFilesHomeState extends State<_ClientFilesHome> {
  static const _accent = Color(0xFF0EA5E9);
  static const _mint = Color(0xFF14B8A6);
  static const _amber = Color(0xFFF59E0B);
  static const _folderSortPrefKey = 'client_folders_sort_mode';
  static const _maxPreviewFolders = 6;

  DriveFolderSummary _summary = const DriveFolderSummary();
  List<Subject> _folders = [];
  List<ClientRecentFolder> _recents = [];
  bool _loading = true;
  bool _creating = false;
  bool _showBrowser = false;
  String? _openFolderId;
  String? _openFolderName;
  String _displayName = '';
  FileSortMode _folderSort = FileSortMode.nameAz;

  ClientWorkspace get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _loadGreeting();
    _loadFolderSort();
    _refresh();
  }

  Future<void> _loadFolderSort() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _folderSort = FileSortModeX.fromStorage(prefs.getString(_folderSortPrefKey));
    });
  }

  Future<void> _openFolderSort() async {
    final next = await showFileSortSheet(
      context: context,
      selected: _folderSort,
      kind: FileSortKind.folders,
    );
    if (next == null || !mounted || next == _folderSort) return;
    setState(() {
      _folderSort = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderSortPrefKey, next.storageValue);
  }

  List<Subject> get _sortedFolders {
    return FileSort.apply(
      _folders,
      mode: _folderSort,
      nameOf: (folder) => folder.name,
      sizeOf: (folder) => folder.fileCount,
      dateOf: (folder) => folder.modifiedAt,
    );
  }

  bool _folderIsLocked(String folderId) {
    return _folders.any(
      (folder) => folder.folderId == folderId && folder.isLocked,
    );
  }

  Future<void> _loadGreeting() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await AuthService.instance.profileDocStream(uid).first;
    final name = (doc.data()?['full_name'] as String?)?.trim() ?? '';
    if (!mounted || name.isEmpty) return;
    setState(() => _displayName = name.split(RegExp(r'\s+')).first);
  }

  Future<void> _refresh() async {
    final showFullPage = _folders.isEmpty;
    if (showFullPage) {
      setState(() => _loading = true);
    }
    try {
      final folderId = _client.driveFolderId;
      final results = await Future.wait([
        GoogleDriveService.summarizeFolder(folderId),
        GoogleDriveService.getSubjectsFromFolder(folderId),
        ClientRecentFolders.load(_client.id),
        () async {
          try {
            return await UploadService.instance.fetchLockedFolderIds(folderId);
          } catch (_) {
            return <String>{};
          }
        }(),
      ]);
      if (!mounted) return;
      final lockedIds = results[3] as Set<String>;
      final folders = (results[1] as List<Subject>)
          .map(
            (folder) => folder.copyWith(isLocked: lockedIds.contains(folder.folderId)),
          )
          .toList();
      setState(() {
        _summary = results[0] as DriveFolderSummary;
        _folders = folders;
        _recents = results[2] as List<ClientRecentFolder>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openBrowser({String? folderId, String? folderName}) {
    HapticFeedback.lightImpact();
    setState(() {
      _showBrowser = true;
      _openFolderId = folderId;
      _openFolderName = folderName;
    });
  }

  void _closeBrowser() {
    setState(() {
      _showBrowser = false;
      _openFolderId = null;
      _openFolderName = null;
    });
    _refresh();
  }

  Future<void> _createFolder() async {
    final name = await _promptName(
      title: 'New folder',
      hint: '',
    );
    if (name == null || name.isEmpty) return;
    if (_folders.any((folder) => GoogleDriveService.folderNamesClash(folder.name, name))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A folder named "$name" already exists')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final result = await UploadService.instance.createFolder(
        parentFolderId: _client.driveFolderId,
        name: name,
      );
      if (!mounted) return;
      final savedName = result.name.isNotEmpty ? result.name : name;
      if (result.id.isNotEmpty) {
        setState(() {
          _folders.removeWhere((folder) => folder.folderId == result.id);
          _folders.add(
            GoogleDriveService.subjectFromFolder(
              id: result.id,
              name: savedName,
              colorIndex: _folders.length,
              modifiedAt: DateTime.now(),
              createdAt: DateTime.now(),
            ),
          );
          _summary = DriveFolderSummary(
            bytes: _summary.bytes,
            fileCount: _summary.fileCount,
            folderCount: _summary.folderCount + 1,
          );
        });
      }
    } on UploadException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<String?> _promptName({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    final takenNames = _folders.map((folder) => folder.name).toList();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              if (takenNames.any(
                (taken) => GoogleDriveService.folderNamesClash(taken, name),
              )) {
                setDialogState(() {
                  error = 'A folder with that name already exists';
                });
                return;
              }
              Navigator.pop(context, name);
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: hint,
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) {
                    setDialogState(() {
                      error = null;
                    });
                  }
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submit,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showBrowser) {
      return ClientFilesBrowserScreen(
        workspaceName: _client.name,
        folderId: _client.driveFolderId,
        clientId: _client.id,
        initialFolderId: _openFolderId,
        initialFolderName: _openFolderName,
        onBack: _closeBrowser,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF0F9FF);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final card = isDark ? const Color(0xFF111827) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _accent,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _header(title, muted),
              const SizedBox(height: 22),
              _storageCard(isDark),
              const SizedBox(height: 18),
              _actionsRow(),
              const SizedBox(height: 22),
              _recentHeader(title),
              const SizedBox(height: 10),
              _recentSection(card, title, muted, isDark),
              const SizedBox(height: 22),
              _foldersHeader(title),
              const SizedBox(height: 10),
              _foldersPreview(card, title, muted, isDark),
              const SizedBox(height: 20),
              _viewAllButton(card, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color title, Color muted) {
    return Row(
      children: [
        if (widget.onBack != null)
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName.isEmpty ? 'Your files' : 'Hi, $_displayName',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: title,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _client.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loading ? null : _refresh,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  double get _storageProgress {
    final limit = _client.storageLimitBytes;
    if (limit <= 0) return 0;
    return (_summary.bytes / limit).clamp(0.0, 1.0);
  }

  Widget _storageCard(bool isDark) {
    final used = ClientWorkspace.formatStorage(_summary.bytes);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0C4A6E), Color(0xFF134E4A)]
              : const [Color(0xFF0EA5E9), Color(0xFF14B8A6)],
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(isDark ? 0.22 : 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workspace storage',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            used,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of ${ClientWorkspace.formatStorage(_client.storageLimitBytes)} used',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: _storageProgress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                _storageProgress >= 1 ? const Color(0xFFF87171) : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _metric(_summary.folderCount.toString(), 'Folders'),
              const SizedBox(width: 10),
              _metric(_summary.fileCount.toString(), 'Files'),
              const SizedBox(width: 10),
              _metric(_recents.length.toString(), 'Recent'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow() {
    return Row(
      children: [
        Expanded(
          child: _actionChip(
            icon: Icons.create_new_folder_rounded,
            label: 'New folder',
            color: _accent,
            onTap: _creating ? null : _createFolder,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionChip(
            icon: Icons.upload_file_rounded,
            label: 'Upload',
            color: _mint,
            onTap: () => _openBrowser(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionChip(
            icon: Icons.grid_view_rounded,
            label: 'Browse',
            color: _amber,
            onTap: () => _openBrowser(),
          ),
        ),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color title) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: title,
      ),
    );
  }

  Widget _foldersHeader(Color title) {
    return Row(
      children: [
        Expanded(child: _sectionLabel('Your folders', title)),
        if (_folders.isNotEmpty)
          GestureDetector(
            onTap: _openFolderSort,
            child: Row(
              children: [
                const Icon(Icons.sort_rounded, color: _accent, size: 20),
                const SizedBox(width: 4),
                Text(
                  'Sort',
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _recentHeader(Color title) {
    return Row(
      children: [
        Expanded(child: _sectionLabel('Recently opened', title)),
        if (_recents.isNotEmpty)
          GestureDetector(
            onTap: _clearRecents,
            child: const Text(
              'Clear',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _clearRecents() async {
    await ClientRecentFolders.clear(_client.id);
    if (!mounted) return;
    setState(() => _recents = []);
  }

  Widget _recentSection(
    Color card,
    Color title,
    Color muted,
    bool isDark,
  ) {
    if (_loading && _recents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_recents.isEmpty) {
      return _emptyCard(
        card,
        muted,
        'Folders you open will appear here.',
      );
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final recent = _recents[index];
          return InkWell(
            onTap: () => _openBrowser(
              folderId: recent.folderId,
              folderName: recent.name,
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 148,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _folderIsLocked(recent.folderId)
                        ? Icons.folder_special_rounded
                        : Icons.folder_rounded,
                    color: _accent,
                  ),
                  const Spacer(),
                  Text(
                    recent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: title,
                    ),
                  ),
                  Text(
                    _relativeTime(recent.openedAt),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _foldersPreview(
    Color card,
    Color title,
    Color muted,
    bool isDark,
  ) {
    if (_loading && _folders.isEmpty) {
      return _emptyCard(card, muted, 'Loading folders…');
    }
    if (_folders.isEmpty) {
      return _emptyCard(
        card,
        muted,
        'No folders yet. Create one to start uploading.',
      );
    }
    final sorted = _sortedFolders;
    final preview = sorted.take(_maxPreviewFolders).toList();
    final remaining = sorted.length - preview.length;
    return Column(
      children: [
        for (final folder in preview)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: card,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                onTap: () => _openBrowser(
                  folderId: folder.folderId,
                  folderName: folder.name,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: CircleAvatar(
                  backgroundColor: folder.color.withOpacity(0.16),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.folder_rounded, color: folder.color),
                      if (folder.isLocked)
                        const Positioned(
                          right: -4,
                          bottom: -4,
                          child: Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                    ],
                  ),
                ),
                title: Text(
                  folder.name,
                  style: TextStyle(fontWeight: FontWeight.w700, color: title),
                ),
                subtitle: Text(
                  '${folder.fileCount} file${folder.fileCount == 1 ? '' : 's'}',
                  style: TextStyle(color: muted),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: muted),
              ),
            ),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '+$remaining more ${remaining == 1 ? 'folder' : 'folders'}',
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _viewAllButton(Color card, bool isDark) {
    return Material(
      color: card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openBrowser(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open_rounded, color: _accent),
              const SizedBox(width: 8),
              Text(
                'View all files',
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(Color card, Color muted, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: TextStyle(color: muted)),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}';
  }
}

class _ClientUnassignedState extends StatelessWidget {
  const _ClientUnassignedState({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                Icon(
                  Icons.folder_shared_outlined,
                  size: 48,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
                const SizedBox(height: 16),
                Text(
                  'No client workspace yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFF9FAFB)
                        : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with the email the system admin used when creating this client.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
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
