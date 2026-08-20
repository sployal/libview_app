import 'package:flutter/material.dart';
import '../services/google_drive_service.dart';
import 'semester_detail_screen.dart';

class SemestersScreen extends StatefulWidget {
  const SemestersScreen({super.key});

  @override
  State<SemestersScreen> createState() => _SemestersScreenState();
}

class _SemestersScreenState extends State<SemestersScreen> {
  final Map<String, int> _unitCounts = {};
  bool _isLoadingCounts = true;

  // ============================================================================
  // 📁 PASTE YOUR GOOGLE DRIVE FOLDER IDs HERE
  // ============================================================================
  // To get the folder ID from a Google Drive link:
  // Example: https://drive.google.com/drive/folders/1ABC123XYZ456
  // The folder ID is: 1ABC123XYZ456
  // ============================================================================
  
  static const Map<String, Map<String, String>> semesterFolderIds = {
    'year1_sem1': {
      'folderId': '18YgdYz4ErI9yJHn2Gx1UoaVqZ7YECSFz',
      'name': 'Year 1 - Semester 1',
    },
    'year1_sem2': {
      'folderId': '13sB0aRpu0xjtScMoJbtlSHcWvbr1gvbp',
      'name': 'Year 1 - Semester 2',
    },
    'year2_sem1': {
      'folderId': '12RdiiGAfWsJPR9Q9fFf7Pi6p-g51sd1C',
      'name': 'Year 2 - Semester 1',
    },
    'year2_sem2': {
      'folderId': '1_50Uj07FIcQY_KTQaFExtFpRnFi4C_G6',
      'name': 'Year 2 - Semester 2',
    },
    'year3_sem1': {
      'folderId': '1jAJiVWsNEAcz6GSVLluxBeMGTTiALv6d',
      'name': 'Year 3 - Semester 1',
    },
    'year3_sem2': {
      'folderId': '16K6uo5lRlS4s93lO8bZ1UkVQ5ywbZCnF',
      'name': 'Year 3 - Semester 2',
    },
    'year4_sem1': {
      'folderId': '1-vulmlL7rswowcYWgl0y9DHw3o1hdnmx',
      'name': 'Year 4 - Semester 1',
    },
    'year4_sem2': {
      'folderId': '15W3I9I9Dqwt3JKjNy8a9fDBCc6V0qjxf',
      'name': 'Year 4 - Semester 2',
    },
    'year5_sem1': {
      'folderId': '18oNF6Xm4NV6oPnpZTJVBCPDqrxlWm6vE',
      'name': 'Year 5 - Semester 1',
    },
    'year5_sem2': {
      'folderId': '1VXL_RjzzO8QxDj1JY3eANLXP-38v-FiX',
      'name': 'Year 5 - Semester 2',
    },
  };

  static const _years = [
    {
      'year': 'Year 1',
      'semesters': [
        {'name': 'Semester 1', 'key': 'year1_sem1'},
        {'name': 'Semester 2', 'key': 'year1_sem2'},
      ]
    },
    {
      'year': 'Year 2',
      'semesters': [
        {'name': 'Semester 1', 'key': 'year2_sem1'},
        {'name': 'Semester 2', 'key': 'year2_sem2'},
      ]
    },
    {
      'year': 'Year 3',
      'semesters': [
        {'name': 'Semester 1', 'key': 'year3_sem1'},
        {'name': 'Semester 2', 'key': 'year3_sem2'},
      ]
    },
    {
      'year': 'Year 4',
      'semesters': [
        {'name': 'Semester 1', 'key': 'year4_sem1'},
        {'name': 'Semester 2', 'key': 'year4_sem2'},
      ]
    },
    {
      'year': 'Year 5',
      'semesters': [
        {'name': 'Semester 1', 'key': 'year5_sem1'},
        {'name': 'Semester 2', 'key': 'year5_sem2'},
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUnitCounts();
  }

  Future<void> _loadUnitCounts() async {
    setState(() {
      _isLoadingCounts = true;
    });

    final counts = await Future.wait(
      semesterFolderIds.entries.map((entry) async {
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

  Future<void> _openSemester(Map<String, String> semesterConfig) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SemesterDetailScreen(
          semesterName: semesterConfig['name']!,
          folderId: semesterConfig['folderId']!,
        ),
      ),
    );
    await _loadUnitCounts();
  }

  @override
  Widget build(BuildContext context) {
    final years = _years;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Academic Years',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _isLoadingCounts ? null : _loadUnitCounts,
            tooltip: 'Refresh unit counts',
          ),
        ],
      ),
      body: ListView.builder(
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
                  final semesterConfig = semesterFolderIds[semesterKey];
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