import 'package:flutter/material.dart';
import 'semester_detail_screen.dart';

class SemestersScreen extends StatelessWidget {
  const SemestersScreen({super.key});

  // ============================================================================
  // 📁 PASTE YOUR GOOGLE DRIVE FOLDER IDs HERE
  // ============================================================================
  // To get the folder ID from a Google Drive link:
  // Example: https://drive.google.com/drive/folders/1ABC123XYZ456
  // The folder ID is: 1ABC123XYZ456
  // ============================================================================
  
  static const Map<String, Map<String, String>> semesterFolderIds = {
    'year1_sem1': {
      'folderId': '1q5b_1KP6n_q9KWitzQyfN0Tgjmri0jYn',
      'name': 'Year 1 - Semester 1',
    },
    'year1_sem2': {
      'folderId': '12btgs0JTwnTw_QXiK6Z4pC1QbZYLf82-',
      'name': 'Year 1 - Semester 2',
    },
    'year2_sem1': {
      'folderId': '1xANMxiJV9nMY2NLoH0gQWpn7wPdkqWUo',
      'name': 'Year 2 - Semester 1',
    },
    'year2_sem2': {
      'folderId': '1WIQks-VqcrqyJGx4y61PVvmHaBC09aPM',
      'name': 'Year 2 - Semester 2',
    },
    'year3_sem1': {
      'folderId': '1PpsJpwvFZBBkISEDXxweXHOtsQePcFEn',
      'name': 'Year 3 - Semester 1',
    },
    'year3_sem2': {
      'folderId': '15lmcOBEuIfqMcHE5Vh-qlXLwONw2A4A8',
      'name': 'Year 3 - Semester 2',
    },
    'year4_sem1': {
      'folderId': '1cj5eTlCl5srYKQrFxeelaMs8WRF44ED4',
      'name': 'Year 4 - Semester 1',
    },
    'year4_sem2': {
      'folderId': '1IUDJVwZH_h5BYsu5q0O3uts31ZIpb7OG',
      'name': 'Year 4 - Semester 2',
    },
    'year5_sem1': {
      'folderId': '1AxVJT5LwBxrxZ7CsW9iM1YH4dfmyELpt',
      'name': 'Year 5 - Semester 1',
    },
    'year5_sem2': {
      'folderId': '19noJ56kc-VtngAG1GyOY_FSFq_Z4PUOi',
      'name': 'Year 5 - Semester 2',
    },
  };

  @override
  Widget build(BuildContext context) {
    final years = [
      {
        'year': 'Year 1',
        'semesters': [
          {'name': 'Semester 1', 'Units': 6, 'progress': 0.8, 'key': 'year1_sem1'},
          {'name': 'Semester 2', 'Units': 5, 'progress': 0.6, 'key': 'year1_sem2'},
        ]
      },
      {
        'year': 'Year 2',
        'semesters': [
          {'name': 'Semester 1', 'Units': 7, 'progress': 1.0, 'key': 'year2_sem1'},
          {'name': 'Semester 2', 'Units': 6, 'progress': 0.9, 'key': 'year2_sem2'},
        ]
      },
      {
        'year': 'Year 3',
        'semesters': [
          {'name': 'Semester 1', 'Units': 6, 'progress': 0.75, 'key': 'year3_sem1'},
          {'name': 'Semester 2', 'Units': 7, 'progress': 0.85, 'key': 'year3_sem2'},
        ]
      },
      {
        'year': 'Year 4',
        'semesters': [
          {'name': 'Semester 1', 'Units': 5, 'progress': 0.95, 'key': 'year4_sem1'},
          {'name': 'Semester 2', 'Units': 6, 'progress': 0.88, 'key': 'year4_sem2'},
        ]
      },
      {
        'year': 'Year 5',
        'semesters': [
          {'name': 'Semester 1', 'Units': 6, 'progress': 1.0, 'key': 'year5_sem1'},
          {'name': 'Semester 2', 'Units': 5, 'progress': 0.92, 'key': 'year5_sem2'},
        ]
      },
    ];

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
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            onPressed: () {},
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
                  final progress = semester['progress'] as double;
                  
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SemesterDetailScreen(
                                semesterName: semesterConfig['name']!,
                                folderId: semesterConfig['folderId']!,
                              ),
                            ),
                          );
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
                                    '${semester['Units']} Units',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Progress Circle
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 4,
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress >= 0.9
                                          ? const Color(0xFF10B981)
                                          : progress >= 0.7
                                              ? const Color(0xFF3B82F6)
                                              : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
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