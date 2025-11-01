import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/google_drive_service.dart';
import 'pdf_reader.dart';

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
  bool isProcessing = false;

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
      final directUrl = _getDirectDownloadUrl(item.id);
      
      if (directUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open file'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PDFReaderScreen(
            pdfUrl: directUrl,
            fileName: item.name,
          ),
        ),
      );
    }
  }

  String _getDirectDownloadUrl(String fileId) {
    return 'https://drive.google.com/uc?export=download&id=$fileId';
  }

  bool _canPop() => navStack.length > 1;

  void _pop() {
    if (!_canPop()) return;
    navStack.removeLast();
    final parent = navStack.last;
    _load(parent.folderId);
  }

  String get _currentFolderId {
    return navStack.isEmpty ? GoogleDriveService.folderId : navStack.last.folderId;
  }

  // Show add options bottom sheet
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.create_new_folder_rounded, color: Color(0xFF10B981)),
                ),
                title: const Text('Create Folder', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Add a new folder', style: TextStyle(color: Color(0xFF6B7280))),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateFolderDialog();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.upload_file_rounded, color: Color(0xFF6366F1)),
                ),
                title: const Text('Upload File', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload PDF or image', style: TextStyle(color: Color(0xFF6B7280))),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadFile();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Create folder dialog
  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter folder name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              _createFolder(name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // Create folder
  Future<void> _createFolder(String folderName) async {
    setState(() => isProcessing = true);
    try {
      await GoogleDriveService.createFolder(folderName, _currentFolderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder "$folderName" created successfully'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      await _load(_currentFolderId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create folder: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // Pick and upload file
  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to read file'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      setState(() => isProcessing = true);
      
      await GoogleDriveService.uploadFile(
        fileName: file.name,
        fileBytes: file.bytes!,
        mimeType: _getMimeType(file.extension ?? ''),
        folderId: _currentFolderId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.name} uploaded successfully'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      await _load(_currentFolderId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  // Show delete confirmation
  void _showDeleteConfirmation(DriveItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete:'),
            const SizedBox(height: 8),
            Text(
              '"${item.name}"?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Delete item
  Future<void> _deleteItem(DriveItem item) async {
    setState(() => isProcessing = true);
    try {
      await GoogleDriveService.deleteFile(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${item.name}" deleted successfully'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      await _load(_currentFolderId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
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
            onPressed: () => _load(_currentFolderId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Stack(
        children: [
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          else if (errorMessage != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _load(_currentFolderId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: () => _load(_currentFolderId),
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
                          onLongPress: () => _showDeleteConfirmation(item),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: items.length,
                    ),
            ),
          if (isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                        SizedBox(height: 16),
                        Text('Processing...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavEntry {
  final String folderId;
  final String? label;
  _NavEntry({required this.folderId, required this.label});
}