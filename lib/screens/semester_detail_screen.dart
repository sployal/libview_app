import 'package:flutter/material.dart';
import '../services/google_drive_service.dart';
import 'subject_detail_screen.dart';

class SemesterDetailScreen extends StatefulWidget {
  final String semesterName;
  final String? folderId; // Google Drive folder ID for this semester

  const SemesterDetailScreen({
    super.key,
    this.semesterName = 'Semester',
    this.folderId, // Pass the folder ID from the semesters screen
  });

  @override
  State<SemesterDetailScreen> createState() => _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends State<SemesterDetailScreen> {
  List<Subject> subjects = [];
  bool isLoading = true;
  String? errorMessage;

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
      // Check if we have a Google Drive folder ID
      if (widget.folderId != null && widget.folderId!.isNotEmpty) {
        // Load subjects from the specified Google Drive folder
        final loadedSubjects = await GoogleDriveService.getSubjectsFromFolder(widget.folderId!);
        setState(() {
          subjects = loadedSubjects;
          isLoading = false;
        });
      } else {
        // Use sample data if no folder ID provided
        setState(() {
          subjects = _getSampleSubjects();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load subjects. Please check your internet connection.';
        subjects = GoogleDriveService.getFallbackSubjects();
        isLoading = false;
      });
    }
  }

  List<Subject> _getSampleSubjects() {
    return [
      Subject(
        id: '1',
        name: 'Sample Subject 1',
        code: 'SUB101',
        folderId: '',
        color: const Color(0xFF6366F1),
        fileCount: 0,
      ),
      Subject(
        id: '2',
        name: 'Sample Subject 2',
        code: 'SUB102',
        folderId: '',
        color: const Color(0xFF10B981),
        fileCount: 0,
      ),
    ];
  }

  bool get _isLiveFolder => widget.folderId != null && widget.folderId!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.semesterName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_isLiveFolder)
              const Text(
                'Live from Google Drive',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSubjects,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Banner
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
                    Icons.cloud_sync_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connected to Google Drive',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Real-time sync with your ${widget.semesterName} folder',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
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

          // Loading or Content
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
                          'Loading subjects from Google Drive...',
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
                                  'No subjects found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Check your Google Drive folder',
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
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SubjectDetailScreen(
                                            subjectName: subject.name,
                                            subjectCode: subject.code,
                                            subjectId: subject.id,
                                            folderId: subject.folderId,
                                            isLiveFolder: _isLiveFolder,
                                          ),
                                        ),
                                      );
                                    },
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
                                                    Icons.book_rounded,
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
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: subject.color.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text(
                                                        '${subject.fileCount} files',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: subject.color,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if (_isLiveFolder) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF10B981).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: const Text(
                                                          'LIVE',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Color(0xFF10B981),
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
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