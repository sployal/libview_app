import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/google_drive_service.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectName;
  final String subjectCode;
  final String? subjectId;
  final String? folderId;
  final bool isLiveFolder;

  const SubjectDetailScreen({
    super.key,
    required this.subjectName,
    required this.subjectCode,
    this.subjectId,
    this.folderId,
    this.isLiveFolder = false,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  List<StudyMaterial> materials = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (widget.isLiveFolder && widget.folderId != null && widget.folderId!.isNotEmpty) {
        // Load from Google Drive
        final loadedMaterials = await GoogleDriveService.getSubjectFiles(widget.folderId!);
        setState(() {
          materials = loadedMaterials;
          isLoading = false;
        });
      } else {
        // Use sample data
        setState(() {
          materials = _getSampleMaterials();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load materials. Please check your connection.';
        materials = _getSampleMaterials();
        isLoading = false;
      });
    }
  }

  List<StudyMaterial> _getSampleMaterials() {
    return [
      StudyMaterial(
        id: '1',
        name: 'Lecture 1: Introduction',
        type: 'PDF',
        size: '2.4 MB',
        date: '2024-01-15',
      ),
      StudyMaterial(
        id: '2',
        name: 'Assignment 1',
        type: 'PDF',
        size: '1.2 MB',
        date: '2024-01-20',
      ),
      StudyMaterial(
        id: '3',
        name: 'Lab Exercise 1',
        type: 'PDF',
        size: '800 KB',
        date: '2024-01-22',
      ),
    ];
  }

  Future<void> _openFile(StudyMaterial material) async {
    if (material.downloadUrl != null) {
      try {
        final uri = Uri.parse(material.downloadUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showMessage('Cannot open file. Please try again.', isError: true);
        }
      } catch (e) {
        _showMessage('Error opening file: $e', isError: true);
      }
    } else {
      _showMessage('File URL not available', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _getFileIcon(String fileType) {
    switch (fileType.toUpperCase()) {
      case 'PDF':
        return const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 24);
      case 'DOC':
        return const Icon(Icons.description_rounded, color: Color(0xFF2563EB), size: 24);
      case 'PPT':
        return const Icon(Icons.slideshow_rounded, color: Color(0xFFEA580C), size: 24);
      case 'XLS':
        return const Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 24);
      default:
        return const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF6B7280), size: 24);
    }
  }

  Color _getFileColor(String fileType) {
    switch (fileType.toUpperCase()) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'DOC':
        return const Color(0xFF2563EB);
      case 'PPT':
        return const Color(0xFFEA580C);
      case 'XLS':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subjectCode,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.subjectName,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMaterials,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Info
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.isLiveFolder 
                    ? [const Color(0xFF10B981), const Color(0xFF059669)]
                    : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.isLiveFolder 
                      ? const Color(0xFF10B981).withOpacity(0.3)
                      : const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.isLiveFolder ? Icons.cloud_sync_rounded : Icons.school_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.subjectCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isLiveFolder 
                            ? '${materials.length} files (Live from Drive)'
                            : '${materials.length} files available',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.isLiveFolder ? 'LIVE' : 'DEMO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error Message
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

          // Files List
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading materials...',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadMaterials,
                    child: materials.isEmpty
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
                                  'No materials found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Materials will appear here when available',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ListView.builder(
                              itemCount: materials.length,
                              itemBuilder: (context, index) {
                                final material = materials[index];
                                final fileColor = _getFileColor(material.type);
                                
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
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
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: fileColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: _getFileIcon(material.type),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                material.name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1F2937),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: fileColor.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      material.type,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: fileColor,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${material.size} • ${material.date}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Color(0xFF6B7280),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (widget.isLiveFolder) ...[
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.open_in_new_rounded,
                                                  color: Color(0xFF6366F1),
                                                  size: 20,
                                                ),
                                                onPressed: () => _openFile(material),
                                              ),
                                            ] else ...[
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.visibility_rounded,
                                                  color: Color(0xFF6B7280),
                                                  size: 20,
                                                ),
                                                onPressed: () {
                                                  HapticFeedback.lightImpact();
                                                  _showMessage('Preview feature coming soon!');
                                                },
                                              ),
                                            ],
                                            IconButton(
                                              icon: Icon(
                                                widget.isLiveFolder 
                                                    ? Icons.cloud_download_rounded
                                                    : Icons.download_rounded,
                                                color: const Color(0xFF6366F1),
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                HapticFeedback.lightImpact();
                                                if (widget.isLiveFolder) {
                                                  _openFile(material);
                                                } else {
                                                  _showMessage('Downloading ${material.name}...');
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
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
      floatingActionButton: widget.isLiveFolder ? null : FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showUploadDialog(context);
        },
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Material'),
        elevation: 8,
      ),
    );
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add Study Material',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This feature is not available for demo subjects.'),
              SizedBox(height: 8),
              Text(
                'Connect to Google Drive for live folder management!',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}