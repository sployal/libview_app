import 'package:flutter/material.dart';
import '../services/google_drive_service.dart';

class Semester4BrowserScreen extends StatefulWidget {
  const Semester4BrowserScreen({super.key});

  @override
  State<Semester4BrowserScreen> createState() => _Semester4BrowserScreenState();
}

class _Semester4BrowserScreenState extends State<Semester4BrowserScreen> {
  bool isLoading = true;
  String? errorMessage;
  List<DriveItem> items = [];
  final List<_NavEntry> navStack = [];

  @override
  void initState() {
    super.initState();
    _load(GoogleDriveService.folderId, label: 'Semester 4');
  }

  Future<void> _load(String folderId, {String? label}) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final loaded = await GoogleDriveService.getFolderContents(folderId);
      setState(() {
        if (label != null) {
          navStack.add(_NavEntry(folderId: folderId, label: label));
        }
        items = loaded;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load folder contents';
        isLoading = false;
      });
    }
  }

  Future<void> _open(DriveItem item) async {
    if (item.isFolder) {
      await _load(item.id, label: item.name);
    } else {
      // Open via webViewLink if available
      final url = item.webViewLink;
      if (url == null || url.isEmpty) return;
      // Defer to SubjectDetailScreen's opener style: external launch
      // Keeping it minimal here to avoid extra deps
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening file in browser...')),
      );
    }
  }

  bool _canPop() => navStack.length > 1;

  void _pop() {
    if (!_canPop()) return;
    navStack.removeLast();
    final parent = navStack.last;
    _load(parent.folderId);
  }

  @override
  Widget build(BuildContext context) {
    final title = navStack.isEmpty ? 'Semester 4' : navStack.last.label;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(title ?? 'Semester 4'),
        leading: _canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _pop,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _load(navStack.isEmpty ? GoogleDriveService.folderId : navStack.last.folderId),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(navStack.isEmpty ? GoogleDriveService.folderId : navStack.last.folderId),
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No items found',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isFolder = item.isFolder;
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: Colors.white,
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: (isFolder ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                              color: isFolder ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                            ),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            isFolder ? 'Folder' : (item.size ?? ''),
                            style: const TextStyle(color: Color(0xFF6B7280)),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF9CA3AF)),
                          onTap: () => _open(item),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: items.length,
                    ),
            ),
    );
  }
}

class _NavEntry {
  final String folderId;
  final String? label;
  _NavEntry({required this.folderId, required this.label});
}


