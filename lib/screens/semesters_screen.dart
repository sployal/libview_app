import 'package:flutter/material.dart';
import 'semester_detail_screen.dart';
import 'semester4_browser_screen.dart';

class SemestersScreen extends StatelessWidget {
  const SemestersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final semesters = [
      {'name': 'Semester 1', 'year': '2024', 'subjects': 6, 'progress': 0.8},
      {'name': 'Semester 2', 'year': '2024', 'subjects': 5, 'progress': 0.6},
      {'name': 'Semester 3', 'year': '2023', 'subjects': 7, 'progress': 1.0},
      {'name': 'Semester 4', 'year': '2023', 'subjects': 6, 'progress': 0.9},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Semesters',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView.builder(
          itemCount: semesters.length,
          itemBuilder: (context, index) {
            final semester = semesters[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () {
                  final name = semester['name'] as String;
                  if (name.contains('4')) {
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
                          semesterName: name,
                        ),
                      ),
                    );
                  }
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${semester['name']} ${semester['year']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${semester['subjects']} Subjects',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Progress',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: semester['progress'] as double,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF6366F1),
                                  ),
                                  minHeight: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${((semester['progress'] as double) * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}