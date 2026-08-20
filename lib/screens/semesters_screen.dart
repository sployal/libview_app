import 'package:flutter/material.dart';
import '../services/course_service.dart';
import '../services/google_drive_service.dart';
import 'semester_detail_screen.dart';

class SemestersScreen extends StatefulWidget {
  const SemestersScreen({super.key});

  @override
  State<SemestersScreen> createState() => _SemestersScreenState();
}

class _SemestersScreenState extends State<SemestersScreen> {
  final Map<String, int> _unitCounts = {};
  bool _isLoadingCourse = true;
  bool _isLoadingCounts = true;
  Course _course = Course.engineeringFallback();
  Map<String, String>? _selectedSemester;

  Map<String, Map<String, String>> get _semesterFolderIds => _course.semesters;

  List<Map<String, dynamic>> get _years => _course.yearGroups;

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  Future<void> _loadCourse() async {
    setState(() {
      _isLoadingCourse = true;
    });

    try {
      final course = await CourseService.instance.courseForCurrentUser();
      if (!mounted) return;
      setState(() {
        _course = course;
        _isLoadingCourse = false;
      });
      await _loadUnitCounts();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _course = Course.engineeringFallback();
        _isLoadingCourse = false;
      });
      await _loadUnitCounts();
    }
  }

  Future<void> _loadUnitCounts() async {
    setState(() {
      _isLoadingCounts = true;
    });

    final counts = await Future.wait(
      _semesterFolderIds.entries.map((entry) async {
        final folderId = entry.value['folderId'] ?? '';
        if (folderId.isEmpty || folderId.contains('PASTE_')) {
          return MapEntry(entry.key, 0);
        }
        try {
          final count = await GoogleDriveService.countFoldersInFolder(folderId);
          return MapEntry(entry.key, count);
        } catch (_) {
          return MapEntry(entry.key, _unitCounts[entry.key] ?? 0);
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _unitCounts
        ..clear()
        ..addEntries(counts);
      _isLoadingCounts = false;
    });
  }

  void _openSemester(Map<String, String> semesterConfig) {
    setState(() {
      _selectedSemester = semesterConfig;
    });
  }

  void _closeSemester() {
    setState(() {
      _selectedSemester = null;
    });
    _loadUnitCounts();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedSemester;
    if (selected != null) {
      return SemesterDetailScreen(
        key: ValueKey(selected['folderId']),
        semesterName: selected['name']!,
        folderId: selected['folderId'],
        onBack: _closeSemester,
      );
    }

    final years = _years;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'Academic Years',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (!_isLoadingCourse)
              Text(
                _course.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _isLoadingCourse || _isLoadingCounts ? null : _loadCourse,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoadingCourse
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: years.length,
        itemBuilder: (context, yearIndex) {
          final year = years[yearIndex];
          final semesters = year['semesters'] as List;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Compact Year Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${year['year']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Compact Semester Cards
                ...List.generate(semesters.length, (semIndex) {
                  final semester = semesters[semIndex];
                  final semesterKey = semester['key'] as String;
                  final semesterConfig = _semesterFolderIds[semesterKey];
                  final semNum = semIndex + 1;
                  final unitCount = _unitCounts[semesterKey];
                  
                  // Determine card color based on semester
                  final colors = semNum == 1
                      ? [const Color(0xFF1E293B), const Color(0xFF334155)]
                      : [const Color(0xFF334155), const Color(0xFF475569)];
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () {
                        if (semesterConfig != null && semesterConfig['folderId']!.isNotEmpty && 
                            !semesterConfig['folderId']!.contains('PASTE_')) {
                          // Navigate to SemesterDetailScreen with Google Drive folder ID
                          _openSemester(semesterConfig);
                        } else {
                          // Show error if folder ID is not configured
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Please configure  ID for ${semesterConfig?['name'] ?? 'this semester'}',
                              ),
                              backgroundColor: const Color(0xFFEF4444),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Semester Icon
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Icon(
                                      semNum == 1 
                                          ? Icons.wb_sunny_rounded 
                                          : Icons.nights_stay_rounded,
                                      color: semNum == 1 
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFF60A5FA),
                                      size: 24,
                                    ),
                                  ),
                                  // Live indicator if folder is configured
                                  if (semesterConfig != null && 
                                      semesterConfig['folderId']!.isNotEmpty && 
                                      !semesterConfig['folderId']!.contains('PASTE_'))
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 12),
                            
                            // Semester Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${semester['name']}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (semesterConfig != null && 
                                          semesterConfig['folderId']!.isNotEmpty && 
                                          !semesterConfig['folderId']!.contains('PASTE_')) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'LIVE',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Color(0xFF10B981),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isLoadingCounts && unitCount == null
                                        ? 'Loading units...'
                                        : '${unitCount ?? 0} ${(unitCount ?? 0) == 1 ? 'Unit' : 'Units'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 8),
                            
                            // Arrow
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white.withOpacity(0.5),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}