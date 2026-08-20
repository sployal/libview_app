import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/google_drive_service.dart';
import '../services/download_service.dart';
import '../services/upload_service.dart';
import 'web_view_screen.dart';

class SemesterDetailScreen extends StatefulWidget {
  final String semesterName;
  final String? folderId;

  const SemesterDetailScreen({
    super.key,
    this.semesterName = 'Semester',
    this.folderId,
  });

  @override
  State<SemesterDetailScreen> createState() => _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends State<SemesterDetailScreen> {
  List<Subject> subjects = [];
  bool isLoading = true;
  String? errorMessage;
  
  Subject? selectedSubject;
  List<StudyMaterial> currentFiles = [];
  bool isLoadingFiles = false;
  
  // NEW: Track downloading state for each file
  Map<String, bool> downloadingFiles = {};
  Map<String, double> downloadProgress = {};
  final Set<String> _deletingIds = {};
  bool isUploading = false;
  double uploadProgress = 0.0;
  bool _isMutatingFolder = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (widget.folderId != null && widget.folderId!.isNotEmpty) {
        final loadedSubjects = await GoogleDriveService.getSubjectsFromFolder(widget.folderId!);
        setState(() {
          subjects = loadedSubjects;
          isLoading = false;
        });
      } else {
        setState(() {
          subjects = _getSampleSubjects();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load units. Please check your internet connection.';
        subjects = GoogleDriveService.getFallbackSubjects();
        isLoading = false;
      });
    }
  }

  List<Subject> _getSampleSubjects() {
    return [
      Subject(
        id: '1',
        name: 'Sample unit 1',
        code: 'SUB101',
        folderId: '',
        color: const Color(0xFF6366F1),
        fileCount: 0,
      ),
      Subject(
        id: '2',
        name: 'Sample unit 2',
        code: 'SUB102',
        folderId: '',
        color: const Color(0xFF10B981),
        fileCount: 0,
      ),
    ];
  }

  bool get _isLiveFolder => widget.folderId != null && widget.folderId!.isNotEmpty;

  Future<void> _loadSubjectFiles(Subject subject) async {
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This unit is not connected to database'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      selectedSubject = subject;
      isLoadingFiles = true;
      currentFiles = [];
      downloadingFiles.clear();
      downloadProgress.clear();
    });

    try {
      final files = await GoogleDriveService.getSubjectFiles(subject.folderId);
      setState(() {
        currentFiles = files;
        isLoadingFiles = false;
      });
    } catch (e) {
      setState(() {
        isLoadingFiles = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load files: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openFileInWebView(StudyMaterial material) {
    if (material.downloadUrl == null || material.downloadUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File URL not available'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebViewScreen(
          url: material.downloadUrl!,
          title: material.name,
          subject: selectedSubject?.name ?? 'Unknown',
        ),
      ),
    );
  }

  // NEW: Extract file ID from Google Drive URL
  String? _extractFileId(String url) {
    try {
      // Pattern 1: /d/FILE_ID/
      RegExp pattern1 = RegExp(r'/d/([a-zA-Z0-9_-]+)');
      Match? match = pattern1.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      // Pattern 2: ?id=FILE_ID or &id=FILE_ID
      RegExp pattern2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');
      match = pattern2.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      // Pattern 3: /file/d/FILE_ID/
      RegExp pattern3 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      match = pattern3.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  // NEW: Download individual file
  Future<void> _downloadFile(StudyMaterial material) async {
    if (material.downloadUrl == null || material.downloadUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('File URL not available'),
              ),
            ],
          ),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Extract file ID from URL
    final fileId = _extractFileId(material.downloadUrl!);
    
    if (fileId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Could not identify file from URL'),
                ),
              ],
            ),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      downloadingFiles[material.id] = true;
      downloadProgress[material.id] = 0.0;
    });

    // Download file using the file ID
    final result = await DownloadService.downloadFile(
      fileId: fileId,
      subject: selectedSubject?.name ?? 'Unknown',
      onProgress: (progress) {
        setState(() {
          downloadProgress[material.id] = progress;
        });
      },
    );

    setState(() {
      downloadingFiles[material.id] = false;
      downloadProgress.remove(material.id);
    });

    // Show result to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(result.message),
              ),
            ],
          ),
          backgroundColor: result.success 
              ? const Color(0xFF10B981) 
              : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: Duration(seconds: result.success ? 3 : 5),
        ),
      );
    }
  }

  Future<void> _confirmDelete(StudyMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete material?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            '“${material.name}” will be permanently removed from this unit.',
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
        );
      },
    );

    if (confirmed == true) {
      await _deleteMaterial(material);
    }
  }

  Future<void> _deleteMaterial(StudyMaterial material) async {
    if (_deletingIds.contains(material.id)) return;

    setState(() {
      _deletingIds.add(material.id);
    });

    try {
      if (_isLiveFolder) {
        await UploadService.instance.deleteFile(material.id);
      }

      if (!mounted) return;
      setState(() {
        currentFiles.removeWhere((item) => item.id == material.id);
        _deletingIds.remove(material.id);
        if (selectedSubject != null && selectedSubject!.fileCount > 0) {
          selectedSubject!.fileCount -= 1;
        }
      });
      _showMessage('Deleted ${material.name}');
    } on UploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(material.id);
      });
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(material.id);
      });
      _showMessage('Failed to delete ${material.name}', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<String?> _promptFolderName({
    required String title,
    required String confirmLabel,
    String initial = '',
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _FolderNameDialog(
          title: title,
          confirmLabel: confirmLabel,
          initial: initial,
        );
      },
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _createUnitFolder() async {
    if (!_isLiveFolder || widget.folderId == null || widget.folderId!.isEmpty) {
      _showMessage('This semester is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Create unit folder',
      confirmLabel: 'Create',
    );
    if (name == null) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.createFolder(
        parentFolderId: widget.folderId!,
        name: name,
      );
      if (!mounted) return;
      _showMessage('Created "$name"');
      await _loadSubjects();
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to create folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _renameUnitFolder(Subject subject) async {
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This unit is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Rename folder',
      confirmLabel: 'Rename',
      initial: subject.name,
    );
    if (name == null || name == subject.name) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.renameFile(
        fileId: subject.folderId,
        name: name,
      );
      if (!mounted) return;
      _showMessage('Renamed to "$name"');
      await _loadSubjects();
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to rename folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    final subject = selectedSubject;
    if (subject == null || !_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('Open a live unit before uploading', isError: true);
      return;
    }
    if (isUploading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      dialogTitle: 'Select a file to upload',
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
    });

    try {
      await UploadService.instance.uploadFile(
        folderId: subject.folderId,
        fileName: file.name,
        filePath: file.path,
        bytes: file.bytes,
        onProgress: (progress) {
          if (mounted) {
            setState(() => uploadProgress = progress);
          }
        },
      );

      _showMessage('${file.name} uploaded successfully');
      await _loadSubjectFiles(subject);
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Upload failed. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          uploadProgress = 0.0;
        });
      }
    }
  }

  void _backToSubjects() {
    setState(() {
      selectedSubject = null;
      currentFiles = [];
      downloadingFiles.clear();
      downloadProgress.clear();
    });
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

  @override
  Widget build(BuildContext context) {
    if (selectedSubject != null) {
      return _buildFilesView();
    }
    
    return _buildSubjectsView();
  }

  Widget _buildFilesView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _backToSubjects,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedSubject!.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              selectedSubject!.code,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: isUploading
                ? null
                : () => _loadSubjectFiles(selectedSubject!),
          ),
        ],
      ),
      floatingActionButton: _isLiveFolder && selectedSubject!.folderId.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: isUploading ? null : _pickAndUploadFile,
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              icon: isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(isUploading ? 'Uploading...' : 'Upload file'),
            )
          : null,
      body: Column(
        children: [
          if (isUploading)
            LinearProgressIndicator(
              value: uploadProgress > 0 ? uploadProgress : null,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              minHeight: 3,
            ),
          Expanded(
            child: isLoadingFiles
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading files...',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : currentFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No files found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This units folder is empty',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (_isLiveFolder && selectedSubject!.folderId.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: isUploading ? null : _pickAndUploadFile,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                          ),
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload file'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadSubjectFiles(selectedSubject!),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: currentFiles.length,
                    itemBuilder: (context, index) {
                      final file = currentFiles[index];
                      final fileColor = _getFileColor(file.type);
                      final fileIcon = _getFileIcon(file.type);
                      final isDownloading = downloadingFiles[file.id] ?? false;
                      final progress = downloadProgress[file.id] ?? 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isDownloading ? null : () => _openFileInWebView(file),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: fileColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      fileIcon,
                                      color: fileColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        if (isDownloading)
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              LinearProgressIndicator(
                                                value: progress,
                                                backgroundColor: const Color(0xFFE5E7EB),
                                                valueColor: AlwaysStoppedAnimation<Color>(fileColor),
                                                minHeight: 3,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Downloading ${(progress * 100).toInt()}%',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: fileColor,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Text(
                                            '${file.type} • ${file.size} • ${file.date}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF6B7280),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_deletingIds.contains(file.id))
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
                                        ),
                                      ),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFEF4444),
                                      ),
                                      tooltip: 'Delete',
                                      onPressed: isDownloading
                                          ? null
                                          : () => _confirmDelete(file),
                                    ),
                                  IconButton(
                                    icon: isDownloading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(fileColor),
                                            ),
                                          )
                                        : Icon(
                                            Icons.download_rounded,
                                            color: fileColor,
                                          ),
                                    onPressed: isDownloading ? null : () => _downloadFile(file),
                                    tooltip: 'Download',
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ],
                              ),
                            ),
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

  Widget _buildSubjectsView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.semesterName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isMutatingFolder ? null : _loadSubjects,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: _isLiveFolder
          ? FloatingActionButton.extended(
              onPressed: _isMutatingFolder ? null : _createUnitFolder,
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              icon: _isMutatingFolder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.create_new_folder_rounded),
              label: Text(_isMutatingFolder ? 'Working...' : 'New folder'),
            )
          : null,
      body: Column(
        children: [
          if (_isLiveFolder)
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_done_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap any unit to view files',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
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
                          'Loading units...',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadSubjects,
                    child: subjects.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.folder_open_rounded,
                                  size: 64,
                                  color: Color(0xFF9CA3AF),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No Units found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Create a folder for this semester',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                                if (_isLiveFolder) ...[
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed:
                                        _isMutatingFolder ? null : _createUnitFolder,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                    ),
                                    icon: const Icon(Icons.create_new_folder_rounded),
                                    label: const Text('New folder'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: subjects.length,
                              itemBuilder: (context, index) {
                                final subject = subjects[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      onTap: () => _loadSubjectFiles(subject),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: subject.color.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Stack(
                                                children: [
                                                  Center(
                                                    child: Icon(
                                                      Icons.folder_rounded,
                                                      color: subject.color,
                                                      size: 30,
                                                    ),
                                                  ),
                                                  if (_isLiveFolder)
                                                    Positioned(
                                                      top: 4,
                                                      right: 4,
                                                      child: Container(
                                                        width: 12,
                                                        height: 12,
                                                        decoration: const BoxDecoration(
                                                          color: Color(0xFF10B981),
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    subject.name,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF1F2937),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    subject.code,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Color(0xFF6B7280),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: subject.color.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.insert_drive_file_rounded,
                                                          size: 14,
                                                          color: subject.color,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '${subject.fileCount} files',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: subject.color,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (_isLiveFolder)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.drive_file_rename_outline_rounded,
                                                  color: Color(0xFF6366F1),
                                                ),
                                                tooltip: 'Rename',
                                                onPressed: _isMutatingFolder
                                                    ? null
                                                    : () => _renameUnitFolder(subject),
                                              ),
                                            const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 16,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initial;

  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initial = '',
  });

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'e.g. CS101 Data Structures',
          labelText: 'Folder name',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}