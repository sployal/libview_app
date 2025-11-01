import 'package:flutter/material.dart';
import 'semester_detail_screen.dart';
import 'semester4_browser_screen.dart';

class SemestersScreen extends StatelessWidget {
  const SemestersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final years = [
      {
        'year': 'Year 1',
        'semesters': [
          {'name': 'Semester 1', 'subjects': 6, 'progress': 0.8},
          {'name': 'Semester 2', 'subjects': 5, 'progress': 0.6},
        ]
      },
      {
        'year': 'Year 2',
        'semesters': [
          {'name': 'Semester 1', 'subjects': 7, 'progress': 1.0},
          {'name': 'Semester 2', 'subjects': 6, 'progress': 0.9},
        ]
      },
      {
        'year': 'Year 3',
        'semesters': [
          {'name': 'Semester 1', 'subjects': 6, 'progress': 0.75},
          {'name': 'Semester 2', 'subjects': 7, 'progress': 0.85},
        ]
      },
      {
        'year': 'Year 4',
        'semesters': [
          {'name': 'Semester 1', 'subjects': 5, 'progress': 0.95},
          {'name': 'Semester 2', 'subjects': 6, 'progress': 0.88},
        ]
      },
      {
        'year': 'Year 5',
        'semesters': [
          {'name': 'Semester 1', 'subjects': 6, 'progress': 1.0},
          {'name': 'Semester 2', 'subjects': 5, 'progress': 0.92},
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
                  final yearNum = yearIndex + 1;
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
                        final yearName = year['year'] as String;
                        
                        if (yearNum == 2 && semNum == 2) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const Semester4BrowserScreen(),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SemesterDetailScreen(
                                semesterName: '$yearName - Semester $semNum',
                              ),
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
                            
                            const SizedBox(width: 12),
                            
                            // Semester Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${semester['name']}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${semester['subjects']} Subjects',
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