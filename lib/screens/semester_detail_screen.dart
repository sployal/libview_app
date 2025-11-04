import 'package:flutter/material.dart';
import '../services/google_drive_service.dart';
import '../services/download_service.dart';
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
            onPressed: () => _loadSubjectFiles(selectedSubject!),
          ),
        ],
      ),
      body: isLoadingFiles
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
                                  // NEW: Download button
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
            onPressed: _loadSubjects,
            tooltip: 'Refresh',
          ),
        ],
      ),
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
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_open_rounded,
                                  size: 64,
                                  color: Color(0xFF9CA3AF),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No Units found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'units will appear here when available',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: ListView.builder(
                              itemCount: subjects.length,
                              itemBuilder: (context, index) {
                                final subject = subjects[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: GestureDetector(
                                    onTap: () => _loadSubjectFiles(subject),
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
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
                                          const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 16,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ],
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