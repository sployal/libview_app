import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/analytics_service.dart';
import '../services/download_service.dart';
import '../ui/adaptive_layout.dart';
import 'system_admin_dashboard.dart';

class SystemAdminAnalyticsScreen extends StatefulWidget {
  const SystemAdminAnalyticsScreen({super.key});

  @override
  State<SystemAdminAnalyticsScreen> createState() =>
      _SystemAdminAnalyticsScreenState();
}

class _SystemAdminAnalyticsScreenState
    extends State<SystemAdminAnalyticsScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _typeColors = {
    'video': Color(0xFF8B5CF6),
    'audio': Color(0xFF0EA5E9),
    'image': Color(0xFFF59E0B),
    'pdf': Color(0xFFEF4444),
    'word': Color(0xFF3B82F6),
    'excel': Color(0xFF10B981),
    'ppt': Color(0xFFF97316),
    'other': Color(0xFF6B7280),
  };
  static const _palette = [
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFF472B6),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
  ];

  bool _checkingAccess = true;
  bool _hasAccess = false;
  bool _loading = true;
  String? _error;
  String _period = 'month';
  String _platform = 'all';
  late int _year;
  late int _month;
  AnalyticsSnapshot? _data;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg =>
      _isDark ? const Color(0xFF111827) : const Color(0xFFE8EEF5);
  Color get _card => _isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get _titleColor =>
      _isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
  Color get _muted =>
      _isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _chip =>
      _isDark ? const Color(0xFF374151) : const Color(0xFFDCE3EE);
  Color get _border => const Color(0xFFCBD5E1);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    final allowed = await SystemAdminDashboard.isCurrentUserSystemAdmin();
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have access to analytics.'),
          backgroundColor: _danger,
        ),
      );
      Navigator.pop(context);
      return;
    }
    setState(() {
      _hasAccess = true;
      _checkingAccess = false;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AnalyticsService.instance.fetch(
        period: _period,
        platform: _platform,
        year: _period == 'all' ? null : _year,
        month: _period == 'month' ? _month : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        if (data.availableYears.isNotEmpty &&
            !data.availableYears.contains(_year)) {
          _year = data.availableYears.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _selectPeriod(String period) {
    if (_period == period) return;
    HapticFeedback.selectionClick();
    setState(() => _period = period);
    _load();
  }

  void _selectPlatform(String platform) {
    if (_platform == platform) return;
    HapticFeedback.selectionClick();
    setState(() => _platform = platform);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pagePad = AdaptiveLayout.pagePadding(context);
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 28;
    final tablet = AdaptiveLayout.isTablet(context);

    return Scaffold(
      backgroundColor: _bg,
      body: _checkingAccess || !_hasAccess
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator(
              color: _accent,
              backgroundColor: _card,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: _bg,
                    foregroundColor: _titleColor,
                    surfaceTintColor: Colors.transparent,
                    title: Text(
                      'Analytics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: tablet ? 22 : 20,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: pagePad.copyWith(top: 4, bottom: bottomPad),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _filters(),
                        const SizedBox(height: 16),
                        if (_loading && _data == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 80),
                            child: Center(child: CupertinoActivityIndicator()),
                          )
                        else if (_error != null && _data == null)
                          _errorCard()
                        else ...[
                          if (_error != null) _errorCard(),
                          _hero(),
                          const SizedBox(height: 16),
                          _summaryGrid(),
                          if (_platform == 'all') ...[
                            const SizedBox(height: 16),
                            _sectionLabel('Platforms'),
                            _platformCompare(),
                          ],
                          const SizedBox(height: 16),
                          _sectionLabel('Active users by course'),
                          _courseUsersCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Active users by role'),
                          _rolesCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Bandwidth'),
                          _bandwidthCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('File types'),
                          _fileTypesCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Documents'),
                          _documentsCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Activity'),
                          _activityCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Top users'),
                          _topUsersCard(),
                          const SizedBox(height: 16),
                          _sectionLabel('Recent activity'),
                          _recentCard(),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _filters() {
    final years = {
      DateTime.now().year,
      _year,
      ...?_data?.availableYears,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    return _groupedCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _data?.periodLabel ?? 'Usage and activity',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: _titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Mobile, web, and combined traffic. New activity is stored as it happens.',
              style: TextStyle(fontSize: 13, height: 1.35, color: _muted),
            ),
            const SizedBox(height: 14),
            _chipRow(
              options: const [
                ('all', 'Combined'),
                ('mobile', 'Mobile'),
                ('web', 'Web'),
              ],
              selected: _platform,
              onSelected: _selectPlatform,
            ),
            const SizedBox(height: 10),
            _chipRow(
              options: const [
                ('month', 'Monthly'),
                ('year', 'Yearly'),
                ('all', 'All time'),
              ],
              selected: _period,
              onSelected: _selectPeriod,
            ),
            if (_period != 'all') ...[
              const SizedBox(height: 10),
              _chipRow(
                options: [
                  for (final year in years) ('$year', '$year'),
                ],
                selected: '$_year',
                onSelected: (value) {
                  final next = int.tryParse(value);
                  if (next == null || next == _year) return;
                  HapticFeedback.selectionClick();
                  setState(() => _year = next);
                  _load();
                },
              ),
            ],
            if (_period == 'month') ...[
              const SizedBox(height: 10),
              _chipRow(
                options: [
                  for (var i = 1; i <= 12; i++)
                    ('$i', _monthNames[i - 1].substring(0, 3)),
                ],
                selected: '$_month',
                onSelected: (value) {
                  final next = int.tryParse(value);
                  if (next == null || next == _month) return;
                  HapticFeedback.selectionClick();
                  setState(() => _month = next);
                  _load();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(_isDark ? 0.28 : 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _platformLabel(_platform),
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.activeUsers} active',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.newUsers > 0
                ? '+${data.newUsers} new accounts in this period'
                : 'Users seen on ${_platformLabel(_platform).toLowerCase()}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat(
                CupertinoIcons.cloud_upload_fill,
                _bytes(data.bytesUploaded),
                'Uploaded',
              ),
              _heroStat(
                CupertinoIcons.cloud_download_fill,
                _bytes(data.bytesDownloaded),
                'Downloaded',
              ),
              _heroStat(
                CupertinoIcons.arrow_2_circlepath,
                _bytes(data.bytesUploaded + data.bytesDownloaded),
                'Total',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final tiles = [
      _statTile('Uploads', '${data.uploads}', CupertinoIcons.up_arrow, _accent),
      _statTile(
        'Downloads',
        '${data.downloads}',
        CupertinoIcons.down_arrow,
        const Color(0xFF0EA5E9),
      ),
      _statTile(
        'Media plays',
        '${data.streams}',
        CupertinoIcons.play_fill,
        const Color(0xFF8B5CF6),
      ),
      _statTile(
        'New users',
        '${data.newUsers}',
        CupertinoIcons.person_badge_plus,
        const Color(0xFF10B981),
      ),
      _statTile(
        'Avg upload',
        _bytes(data.avgUploadBytes),
        CupertinoIcons.doc_fill,
        const Color(0xFFF59E0B),
      ),
      _statTile(
        'Avg download',
        _bytes(data.avgDownloadBytes),
        CupertinoIcons.square_arrow_down_fill,
        const Color(0xFFF472B6),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: wide
                    ? (constraints.maxWidth - 20) / 3
                    : (constraints.maxWidth - 10) / 2,
                child: tile,
              ),
          ],
        );
      },
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return _groupedCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _glyph(icon, color),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: _titleColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _platformCompare() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return _groupedCard(
      child: Column(
        children: [
          _compareRow(
            'Mobile app',
            data.mobile,
            CupertinoIcons.device_phone_portrait,
            _accent,
            showDivider: true,
          ),
          _compareRow(
            'Web app',
            data.web,
            CupertinoIcons.globe,
            const Color(0xFF0EA5E9),
          ),
        ],
      ),
    );
  }

  Widget _compareRow(
    String title,
    AnalyticsCount count,
    IconData icon,
    Color color, {
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  _glyph(icon, color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _titleColor,
                      ),
                    ),
                  ),
                  Text(
                    '${count.activeUsers} active',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _miniMetric('${count.uploads}', 'Uploads'),
                  _miniMetric('${count.downloads}', 'Downloads'),
                  _miniMetric(_bytes(count.bytesUploaded), 'Up'),
                  _miniMetric(_bytes(count.bytesDownloaded), 'Down'),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) _hairline(indent: 0),
      ],
    );
  }

  Widget _miniMetric(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _titleColor,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }

  Widget _courseUsersCard() {
    final rows = _data?.activeUsersByCourse ?? const [];
    return _groupedCard(
      child: Column(
        children: [
          _pieBlock(
            values: [
              for (var i = 0; i < rows.length; i++)
                _ChartSlice(
                  label: rows[i].name,
                  value: rows[i].users.toDouble(),
                  color: _palette[i % _palette.length],
                ),
            ],
            empty: 'No active users in this period yet.',
          ),
          if (rows.isNotEmpty) _hairline(indent: 0),
          for (var i = 0; i < rows.length; i++)
            _tableRow(
              color: _palette[i % _palette.length],
              title: rows[i].name,
              subtitle: rows[i].kind == 'client'
                  ? 'Client workspace'
                  : rows[i].newUsers > 0
                      ? '${rows[i].newUsers} new'
                      : 'Course',
              value: '${rows[i].users}',
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _rolesCard() {
    final rows = _data?.activeUsersByRole ?? const [];
    if (rows.isEmpty) {
      return _groupedCard(child: _emptyNote('No role activity in this period.'));
    }
    return _groupedCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _tableRow(
              color: _palette[i % _palette.length],
              title: rows[i].name,
              value: '${rows[i].users}',
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _bandwidthCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final rows = data.bandwidthByCourse;
    return _groupedCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: _dualBarChart(
              points: data.series,
              uploadOf: (point) => point.bytesUploaded.toDouble(),
              downloadOf: (point) => point.bytesDownloaded.toDouble(),
              tooltip: (value) => _bytes(value.round()),
            ),
          ),
          _legendRow(const [
            (_accent, 'Upload'),
            (Color(0xFF0EA5E9), 'Download'),
          ]),
          _hairline(indent: 0),
          _tableRow(
            color: _accent,
            title: 'Total uploaded',
            value: _bytes(data.bytesUploaded),
            showDivider: true,
          ),
          _tableRow(
            color: const Color(0xFF0EA5E9),
            title: 'Total downloaded',
            value: _bytes(data.bytesDownloaded),
            showDivider: rows.isNotEmpty,
          ),
          for (var i = 0; i < rows.length; i++)
            _tableRow(
              color: _palette[i % _palette.length],
              title: rows[i].name,
              subtitle:
                  '${rows[i].uploads} up · ${rows[i].downloads} down',
              value: _bytes(rows[i].totalBytes),
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _fileTypesCard() {
    final rows = _data?.fileTypes ?? const [];
    return _groupedCard(
      child: Column(
        children: [
          _pieBlock(
            values: [
              for (final row in rows)
                if (row.totalCount > 0)
                  _ChartSlice(
                    label: row.name,
                    value: row.totalCount.toDouble(),
                    color: _typeColors[row.id] ?? _muted,
                  ),
            ],
            empty: 'No file activity in this period yet.',
          ),
          if (rows.any((row) => row.totalCount > 0)) _hairline(indent: 0),
          for (var i = 0; i < rows.length; i++)
            if (rows[i].totalCount > 0 || rows[i].totalBytes > 0)
              _tableRow(
                color: _typeColors[rows[i].id] ?? _muted,
                title: rows[i].name,
                subtitle:
                    '${rows[i].uploads} uploaded · ${rows[i].downloads} downloaded',
                value: _bytes(rows[i].totalBytes),
                showDivider: i < rows.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _documentsCard() {
    final rows = _data?.documents ?? const [];
    final hasData = rows.any((row) => row.totalCount > 0 || row.totalBytes > 0);
    return _groupedCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: hasData
                ? _typeBarChart(rows)
                : _emptyNote('No document uploads or downloads yet.'),
          ),
          if (hasData) ...[
            const SizedBox(height: 4),
            for (var i = 0; i < rows.length; i++)
              _tableRow(
                color: _typeColors[rows[i].id] ?? _muted,
                title: rows[i].name,
                subtitle:
                    '${rows[i].uploads} up · ${rows[i].downloads} down',
                value: '${rows[i].totalCount}',
                showDivider: i < rows.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  Widget _activityCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return _groupedCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: _dualBarChart(
              points: data.series,
              uploadOf: (point) => point.uploads.toDouble(),
              downloadOf: (point) => point.downloads.toDouble(),
              tooltip: (value) => value.round().toString(),
            ),
          ),
          _legendRow(const [
            (_accent, 'Uploads'),
            (Color(0xFF0EA5E9), 'Downloads'),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _topUsersCard() {
    final uploads = _data?.topUploaders ?? const [];
    final downloads = _data?.topDownloaders ?? const [];
    if (uploads.isEmpty && downloads.isEmpty) {
      return _groupedCard(
        child: _emptyNote('Top users appear after the first upload or download.'),
      );
    }
    return _groupedCard(
      child: Column(
        children: [
          _innerHeader('Uploaders'),
          if (uploads.isEmpty)
            _emptyNote('No uploads in this period.')
          else
            for (var i = 0; i < uploads.length; i++)
              _tableRow(
                color: _accent,
                title: uploads[i].name,
                subtitle: uploads[i].courseName,
                value: '${uploads[i].count} · ${_bytes(uploads[i].bytes)}',
                showDivider: i < uploads.length - 1,
              ),
          _hairline(indent: 0),
          _innerHeader('Downloaders'),
          if (downloads.isEmpty)
            _emptyNote('No downloads in this period.')
          else
            for (var i = 0; i < downloads.length; i++)
              _tableRow(
                color: const Color(0xFF0EA5E9),
                title: downloads[i].name,
                subtitle: downloads[i].courseName,
                value:
                    '${downloads[i].count} · ${_bytes(downloads[i].bytes)}',
                showDivider: i < downloads.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _recentCard() {
    final rows = _data?.recent ?? const [];
    if (rows.isEmpty) {
      return _groupedCard(
        child: _emptyNote('Recent uploads and downloads will show up here.'),
      );
    }
    return _groupedCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _tableRow(
              color: _typeColors[rows[i].fileType] ?? _accent,
              title: rows[i].fileName.isEmpty ? rows[i].kind : rows[i].fileName,
              subtitle: [
                rows[i].name,
                rows[i].kind,
                rows[i].platform,
                if (rows[i].ownerName.isNotEmpty) rows[i].ownerName,
              ].join(' · '),
              value: _bytes(rows[i].sizeBytes),
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _pieBlock({
    required List<_ChartSlice> values,
    required String empty,
  }) {
    final slices = values.where((item) => item.value > 0).toList();
    if (slices.isEmpty) return _emptyNote(empty);
    final total = slices.fold<double>(0, (sum, item) => sum + item.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Column(
        children: [
          SizedBox(
            height: 210,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 48,
                sections: [
                  for (final slice in slices)
                    PieChartSectionData(
                      value: slice.value,
                      color: slice.color,
                      radius: 46,
                      title: total <= 0
                          ? ''
                          : '${((slice.value / total) * 100).round()}%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final slice in slices)
                _legendDot(slice.color, '${slice.label} · ${slice.value.round()}'),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _dualBarChart({
    required List<AnalyticsSeriesPoint> points,
    required double Function(AnalyticsSeriesPoint) uploadOf,
    required double Function(AnalyticsSeriesPoint) downloadOf,
    required String Function(int) tooltip,
  }) {
    if (points.isEmpty ||
        points.every((point) => uploadOf(point) == 0 && downloadOf(point) == 0)) {
      return _emptyNote('No traffic in this period yet.');
    }

    final maxValue = points.fold<double>(0, (current, point) {
      final local = uploadOf(point) > downloadOf(point)
          ? uploadOf(point)
          : downloadOf(point);
      return local > current ? local : current;
    });
    final groups = <BarChartGroupData>[
      for (var i = 0; i < points.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: 3,
          barRods: [
            BarChartRodData(
              toY: uploadOf(points[i]),
              width: points.length > 16 ? 4 : 7,
              borderRadius: BorderRadius.circular(3),
              color: _accent,
            ),
            BarChartRodData(
              toY: downloadOf(points[i]),
              width: points.length > 16 ? 4 : 7,
              borderRadius: BorderRadius.circular(3),
              color: const Color(0xFF0EA5E9),
            ),
          ],
        ),
    ];

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.15,
          barGroups: groups,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _chip.withOpacity(0.7),
              strokeWidth: 0.6,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: points.length > 16 ? 5 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (points.length > 16 && index % 5 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    points[index].label,
                    style: TextStyle(fontSize: 10, color: _muted),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _isDark
                  ? const Color(0xFF111827)
                  : const Color(0xFF111827),
              getTooltipItem: (group, _, rod, rodIndex) {
                final label = rodIndex == 0 ? 'Upload' : 'Download';
                return BarTooltipItem(
                  '${points[group.x].label}\n$label ${tooltip(rod.toY.round())}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeBarChart(List<AnalyticsFileType> rows) {
    final maxValue = rows.fold<double>(0, (current, row) {
      final local = row.uploads > row.downloads
          ? row.uploads.toDouble()
          : row.downloads.toDouble();
      return local > current ? local : current;
    });
    return SizedBox(
      height: 210,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.2,
          barGroups: [
            for (var i = 0; i < rows.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: rows[i].uploads.toDouble(),
                    width: 10,
                    borderRadius: BorderRadius.circular(4),
                    color: _accent,
                  ),
                  BarChartRodData(
                    toY: rows[i].downloads.toDouble(),
                    width: 10,
                    borderRadius: BorderRadius.circular(4),
                    color: _typeColors[rows[i].id] ?? const Color(0xFF0EA5E9),
                  ),
                ],
              ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _chip.withOpacity(0.7),
              strokeWidth: 0.6,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= rows.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    rows[index].name,
                    style: TextStyle(fontSize: 10, color: _muted),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _groupedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(CupertinoIcons.exclamationmark_circle_fill,
                  color: _danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error ?? 'Could not load analytics',
                  style: TextStyle(color: _titleColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipRow({
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.$2),
                selected: selected == option.$1,
                onSelected: (_) => onSelected(option.$1),
                selectedColor: _accent,
                backgroundColor: _chip,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected == option.$1 ? FontWeight.w600 : FontWeight.w500,
                  color: selected == option.$1 ? Colors.white : _titleColor,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupedCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: _isDark ? null : Border.all(color: _border),
        boxShadow: [
          if (!_isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: _muted,
        ),
      ),
    );
  }

  Widget _innerHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: _muted,
        ),
      ),
    );
  }

  Widget _tableRow({
    required Color color,
    required String title,
    required String value,
    String? subtitle,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _titleColor,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _titleColor,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _hairline(),
      ],
    );
  }

  Widget _legendRow(List<(Color, String)> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          for (final item in items) ...[
            _legendDot(item.$1, item.$2),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }

  Widget _glyph(IconData icon, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  Widget _hairline({double indent = 34}) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(height: 0.5, thickness: 0.5, color: _chip),
    );
  }

  Widget _emptyNote(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.4, color: _muted),
      ),
    );
  }

  String _bytes(int bytes) => DownloadService.formatFileSize(bytes);

  String _platformLabel(String platform) {
    switch (platform) {
      case 'mobile':
        return 'Mobile app';
      case 'web':
        return 'Web app';
      default:
        return 'All platforms';
    }
  }
}

class _ChartSlice {
  const _ChartSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}
