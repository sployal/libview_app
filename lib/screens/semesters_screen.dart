import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/course_service.dart';
import '../services/google_drive_service.dart';
import 'semester_detail_screen.dart';

class SemestersScreen extends StatefulWidget {
  const SemestersScreen({super.key});

  @override
  State<SemestersScreen> createState() => _SemestersScreenState();
}

class _SemestersScreenState extends State<SemestersScreen> {
  static const _selectedYearPrefKey = 'semesters_selected_year';
  static const _lastSemesterKeyPref = 'semesters_last_key';
  static const _lastSemesterNamePref = 'semesters_last_name';
  static const _lastSemesterYearPref = 'semesters_last_year';

  final Map<String, int> _unitCounts = {};
  bool _isLoadingCourse = true;
  bool _isLoadingCounts = true;
  Course _course = Course.engineeringFallback();
  Map<String, String>? _selectedSemester;
  int _selectedYearIndex = 0;
  String? _lastSemesterKey;
  String? _lastSemesterName;
  String? _lastSemesterYear;

  Map<String, Map<String, String>> get _semesterFolderIds => _course.semesters;

  List<Map<String, dynamic>> get _years => _course.yearGroups;

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    _loadCourse();
  }

  Future<void> _restorePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedYearIndex = prefs.getInt(_selectedYearPrefKey) ?? 0;
      _lastSemesterKey = prefs.getString(_lastSemesterKeyPref);
      _lastSemesterName = prefs.getString(_lastSemesterNamePref);
      _lastSemesterYear = prefs.getString(_lastSemesterYearPref);
    });
  }

  Future<void> _saveSelectedYear(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedYearPrefKey, index);
  }

  Future<void> _rememberSemester({
    required String key,
    required String name,
    required String yearLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSemesterKeyPref, key);
    await prefs.setString(_lastSemesterNamePref, name);
    await prefs.setString(_lastSemesterYearPref, yearLabel);
    if (!mounted) return;
    setState(() {
      _lastSemesterKey = key;
      _lastSemesterName = name;
      _lastSemesterYear = yearLabel;
    });
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
        if (_selectedYearIndex >= course.years) {
          _selectedYearIndex = 0;
        }
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
        if (!_isConfiguredId(folderId)) {
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

  bool _isConfiguredId(String? folderId) {
    if (folderId == null || folderId.isEmpty) return false;
    return !folderId.contains('PASTE_');
  }

  bool _isSemesterReady(Map<String, String>? config) {
    return config != null && _isConfiguredId(config['folderId']);
  }

  int get _readySemesterCount {
    return _semesterFolderIds.values.where(_isSemesterReady).length;
  }

  int get _totalUnits {
    return _unitCounts.values.fold(0, (sum, count) => sum + count);
  }

  void _selectYear(int index) {
    if (index == _selectedYearIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedYearIndex = index;
    });
    _saveSelectedYear(index);
  }

  void _openSemester(
    Map<String, String> semesterConfig, {
    String? semesterKey,
    String? yearLabel,
  }) {
    if (!_isSemesterReady(semesterConfig)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Materials for ${semesterConfig['name'] ?? 'this semester'} are not available yet',
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    if (semesterKey != null && yearLabel != null) {
      _rememberSemester(
        key: semesterKey,
        name: semesterConfig['name'] ?? 'Semester',
        yearLabel: yearLabel,
      );
    }

    setState(() {
      _selectedSemester = semesterConfig;
    });
  }

  void _continueLastSemester() {
    final key = _lastSemesterKey;
    if (key == null) return;
    final config = _semesterFolderIds[key];
    if (config == null) return;

    final match = RegExp(r'year(\d+)_sem').firstMatch(key);
    final yearIndex = match == null ? _selectedYearIndex : int.parse(match.group(1)!) - 1;
    if (yearIndex >= 0 && yearIndex < _years.length) {
      _selectYear(yearIndex);
    }
    _openSemester(
      config,
      semesterKey: key,
      yearLabel: _lastSemesterYear ?? 'Year ${yearIndex + 1}',
    );
  }

  void _closeSemester() {
    setState(() {
      _selectedSemester = null;
    });
    _loadUnitCounts();
  }

  Color _yearAccent(int yearIndex) {
    const accents = [
      Color(0xFF6366F1),
      Color(0xFF0EA5E9),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
    ];
    return accents[yearIndex % accents.length];
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final subtitleColor = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: background,
      body: _isLoadingCourse
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                ),
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF6366F1),
              onRefresh: _loadCourse,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar.large(
                    backgroundColor: background,
                    surfaceTintColor: Colors.transparent,
                    pinned: true,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _isLoadingCounts ? null : _loadCourse,
                        tooltip: 'Refresh',
                      ),
                    ],
                    title: Text(
                      'Semesters',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Text(
                          _course.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _OverviewStrip(
                          isDark: isDark,
                          years: _course.years,
                          readySemesters: _readySemesterCount,
                          totalSemesters: _semesterFolderIds.length,
                          units: _totalUnits,
                          loadingUnits: _isLoadingCounts,
                        ),
                        if (_lastSemesterKey != null &&
                            _semesterFolderIds.containsKey(_lastSemesterKey)) ...[
                          const SizedBox(height: 16),
                          _ContinueCard(
                            isDark: isDark,
                            semesterName: _lastSemesterName ?? 'Semester',
                            yearLabel: _lastSemesterYear ?? '',
                            onTap: _continueLastSemester,
                          ),
                        ],
                        const SizedBox(height: 28),
                        Text(
                          'Choose a year',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _YearSelector(
                          years: _years,
                          selectedIndex: _selectedYearIndex,
                          accentFor: _yearAccent,
                          isDark: isDark,
                          onSelected: _selectYear,
                        ),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _SemesterPair(
                            key: ValueKey(_selectedYearIndex),
                            year: _years[_selectedYearIndex],
                            accent: _yearAccent(_selectedYearIndex),
                            isDark: isDark,
                            unitCounts: _unitCounts,
                            isLoadingCounts: _isLoadingCounts,
                            folderIds: _semesterFolderIds,
                            isReady: _isSemesterReady,
                            onOpen: _openSemester,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Your academic path',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AcademicPath(
                          years: _years,
                          selectedIndex: _selectedYearIndex,
                          accentFor: _yearAccent,
                          isDark: isDark,
                          unitCounts: _unitCounts,
                          folderIds: _semesterFolderIds,
                          isReady: _isSemesterReady,
                          onSelectYear: _selectYear,
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({
    required this.isDark,
    required this.years,
    required this.readySemesters,
    required this.totalSemesters,
    required this.units,
    required this.loadingUnits,
  });

  final bool isDark;
  final int years;
  final int readySemesters;
  final int totalSemesters;
  final int units;
  final bool loadingUnits;

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final label = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final value = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);

    Widget stat(String title, String body) {
      return Expanded(
        child: Column(
          children: [
            Text(
              body,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: value,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: label,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        children: [
          stat('Years', '$years'),
          _divider(isDark),
          stat('Ready', '$readySemesters/$totalSemesters'),
          _divider(isDark),
          stat('Units', loadingUnits ? '—' : '$units'),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) {
    return Container(
      width: 1,
      height: 32,
      color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.isDark,
    required this.semesterName,
    required this.yearLabel,
    required this.onTap,
  });

  final bool isDark;
  final String semesterName;
  final String yearLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        yearLabel.isEmpty
                            ? semesterName
                            : '$yearLabel · $semesterName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selectedIndex,
    required this.accentFor,
    required this.isDark,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> years;
  final int selectedIndex;
  final Color Function(int index) accentFor;
  final bool isDark;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: years.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          final accent = accentFor(index);
          return GestureDetector(
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? accent
                    : (isDark ? const Color(0xFF1F2937) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? null
                    : Border.all(
                        color: isDark
                            ? const Color(0xFF374151)
                            : const Color(0xFFE5E7EB),
                      ),
              ),
              child: Text(
                '${years[index]['year']}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF374151)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SemesterPair extends StatelessWidget {
  const _SemesterPair({
    super.key,
    required this.year,
    required this.accent,
    required this.isDark,
    required this.unitCounts,
    required this.isLoadingCounts,
    required this.folderIds,
    required this.isReady,
    required this.onOpen,
  });

  final Map<String, dynamic> year;
  final Color accent;
  final bool isDark;
  final Map<String, int> unitCounts;
  final bool isLoadingCounts;
  final Map<String, Map<String, String>> folderIds;
  final bool Function(Map<String, String>?) isReady;
  final void Function(
    Map<String, String> config, {
    String? semesterKey,
    String? yearLabel,
  }) onOpen;

  @override
  Widget build(BuildContext context) {
    final semesters = year['semesters'] as List;
    final yearLabel = '${year['year']}';

    return Column(
      children: List.generate(semesters.length, (index) {
        final semester = semesters[index] as Map;
        final key = semester['key'] as String;
        final config = folderIds[key];
        final ready = isReady(config);
        final unitCount = unitCounts[key];
        final isFirst = index == 0;

        return Padding(
          padding: EdgeInsets.only(bottom: index == semesters.length - 1 ? 0 : 12),
          child: _SemesterCard(
            name: '${semester['name']}',
            subtitle: isFirst
                ? 'Opening term · lectures, notes, and labs'
                : 'Second term · lectures, notes, and labs',
            unitsLabel: isLoadingCounts && unitCount == null
                ? 'Counting units…'
                : '${unitCount ?? 0} ${(unitCount ?? 0) == 1 ? 'unit' : 'units'}',
            ready: ready,
            isDark: isDark,
            accent: accent,
            icon: isFirst ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
            iconColor: isFirst
                ? const Color(0xFFF59E0B)
                : const Color(0xFF60A5FA),
            onTap: config == null
                ? null
                : () => onOpen(
                      config,
                      semesterKey: key,
                      yearLabel: yearLabel,
                    ),
          ),
        );
      }),
    );
  }
}

class _SemesterCard extends StatelessWidget {
  const _SemesterCard({
    required this.name,
    required this.subtitle,
    required this.unitsLabel,
    required this.ready,
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String unitsLabel;
  final bool ready;
  final bool isDark;
  final Color accent;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final title = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            ready
                                ? Icons.folder_open_rounded
                                : Icons.lock_outline_rounded,
                            size: 15,
                            color: ready ? accent : muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ready ? unitsLabel : 'Not set up yet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ready ? accent : muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AcademicPath extends StatelessWidget {
  const _AcademicPath({
    required this.years,
    required this.selectedIndex,
    required this.accentFor,
    required this.isDark,
    required this.unitCounts,
    required this.folderIds,
    required this.isReady,
    required this.onSelectYear,
  });

  final List<Map<String, dynamic>> years;
  final int selectedIndex;
  final Color Function(int index) accentFor;
  final bool isDark;
  final Map<String, int> unitCounts;
  final Map<String, Map<String, String>> folderIds;
  final bool Function(Map<String, String>?) isReady;
  final ValueChanged<int> onSelectYear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: years.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final year = years[index];
          final semesters = year['semesters'] as List;
          final accent = accentFor(index);
          final selected = index == selectedIndex;
          var yearUnits = 0;
          var readyCount = 0;
          for (final semester in semesters) {
            final key = (semester as Map)['key'] as String;
            yearUnits += unitCounts[key] ?? 0;
            if (isReady(folderIds[key])) readyCount++;
          }

          return GestureDetector(
            onTap: () => onSelectYear(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 132,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withOpacity(isDark ? 0.22 : 0.1)
                    : (isDark ? const Color(0xFF1F2937) : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? accent.withOpacity(0.55)
                      : (isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFE5E7EB)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${year['year']}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? accent
                          : (isDark
                              ? const Color(0xFFF9FAFB)
                              : const Color(0xFF111827)),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: List.generate(semesters.length, (semIndex) {
                      final filled = semIndex < readyCount;
                      return Container(
                        margin: const EdgeInsets.only(right: 5),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? accent
                              : accent.withOpacity(0.22),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$yearUnits units',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
