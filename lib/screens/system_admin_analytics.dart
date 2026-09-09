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
  static const _sky = Color(0xFF0EA5E9);
  static const _media = Color(0xFF8B5CF6);
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
  String _platformBytesKind = 'download';
  late int _year;
  late int _month;
  late int _week;
  AnalyticsSnapshot? _data;
  late final ScrollController _monthScroll;
  late final ScrollController _weekScroll;
  bool _pinMonthWindow = true;
  static const _monthItemWidth = 52.0;
  static const _monthItemGap = 8.0;
  static const _monthItemExtent = _monthItemWidth + _monthItemGap;
  static const _weekItemWidth = 52.0;
  static const _weekItemGap = 8.0;
  static const _weekItemExtent = _weekItemWidth + _weekItemGap;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  bool get _wide => MediaQuery.sizeOf(context).width >= 720;
  Color get _bg =>
      _isDark ? const Color(0xFF111827) : const Color(0xFFE8EEF5);
  Color get _card => _isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get _titleColor =>
      _isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
  Color get _muted =>
      _isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _chip =>
      _isDark ? const Color(0xFF374151) : const Color(0xFFDCE3EE);
  Color get _line =>
      _isDark ? const Color(0xFF374151) : const Color(0xFFCBD5E1);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _week = _isoWeekInfo(now).week;
    _monthScroll = ScrollController(
      onAttach: (_) {
        if (_period == 'month') _alignMonth(animate: false);
      },
    );
    _weekScroll = ScrollController(
      onAttach: (_) {
        if (_period == 'week') _alignWeek(animate: false);
      },
    );
    _verifyAccess();
  }

  @override
  void dispose() {
    _monthScroll.dispose();
    _weekScroll.dispose();
    super.dispose();
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
    _alignMonth(animate: false);
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
        week: _period == 'week' ? _week : null,
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
      _alignMonth(animate: false);
      _alignWeek(animate: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      _alignMonth(animate: false);
      _alignWeek(animate: false);
    }
  }

  void _selectPeriod(String period) {
    if (_period == period) return;
    HapticFeedback.selectionClick();
    setState(() {
      _period = period;
      if (period == 'week') {
        final iso = _isoWeekInfo(DateTime.now());
        if (_year == iso.year) {
          _week = iso.week;
        } else {
          _week = _week.clamp(1, _weeksInIsoYear(_year)).toInt();
        }
      }
    });
    if (period == 'month') _alignMonth(animate: false);
    if (period == 'week') _alignWeek(animate: false);
    _load();
  }

  ({int year, int week}) _isoWeekInfo(DateTime date) {
    final utc = DateTime.utc(date.year, date.month, date.day);
    final thursday = utc.add(Duration(days: 4 - utc.weekday));
    final jan4 = DateTime.utc(thursday.year, 1, 4);
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final week = 1 + thursday.difference(week1Monday).inDays ~/ 7;
    return (year: thursday.year, week: week);
  }

  int _weeksInIsoYear(int year) {
    return _isoWeekInfo(DateTime.utc(year, 12, 28)).week;
  }

  String get _periodPhrase {
    switch (_period) {
      case 'week':
        return 'this week';
      case 'year':
        return 'this year';
      case 'all':
        return 'all time';
      default:
        return 'this month';
    }
  }

  double _monthWindowOffset(double viewport, double maxExtent) {
    if (viewport <= 0) return 0;
    // Keep the selected month at the leading edge of the strip so the
    // window opens on the current month instead of January.
    return ((_month - 1) * _monthItemExtent).clamp(0.0, maxExtent);
  }

  void _alignMonth({bool animate = true, int attempt = 0}) {
    _pinMonthWindow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _period != 'month') return;
      if (!_monthScroll.hasClients) {
        if (attempt < 24) _alignMonth(animate: animate, attempt: attempt + 1);
        return;
      }
      final position = _monthScroll.position;
      final viewport = position.viewportDimension;
      final maxExtent = position.maxScrollExtent;
      final contentWidth = 12 * _monthItemExtent;
      if (viewport <= 0 ||
          (maxExtent <= 0 && contentWidth > viewport + 1 && attempt < 24)) {
        _alignMonth(animate: animate, attempt: attempt + 1);
        return;
      }
      final target = _monthWindowOffset(viewport, maxExtent);
      if ((position.pixels - target).abs() < 1) {
        _pinMonthWindow = false;
        return;
      }
      if (animate) {
        _monthScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ).whenComplete(() {
          if (mounted) _pinMonthWindow = false;
        });
      } else {
        _monthScroll.jumpTo(target);
        _pinMonthWindow = false;
      }
    });
  }

  void _alignWeek({bool animate = true, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _period != 'week') return;
      if (!_weekScroll.hasClients) {
        if (attempt < 24) _alignWeek(animate: animate, attempt: attempt + 1);
        return;
      }
      final position = _weekScroll.position;
      final maxExtent = position.maxScrollExtent;
      if (position.viewportDimension <= 0 && attempt < 24) {
        _alignWeek(animate: animate, attempt: attempt + 1);
        return;
      }
      final target =
          ((_week - 1) * _weekItemExtent).clamp(0.0, maxExtent).toDouble();
      if ((position.pixels - target).abs() < 1) return;
      if (animate) {
        _weekScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        _weekScroll.jumpTo(target);
      }
    });
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
                  compactSliverAppBar(
                    automaticallyImplyLeading: true,
                    backgroundColor: _bg,
                    foregroundColor: _titleColor,
                    title: Text(
                      'Analytics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: tablet ? 22 : 20,
                      ),
                    ),
                    actions: [
                      if (_data != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Center(child: _periodBadge()),
                        ),
                    ],
                  ),
                  if (_loading && _data != null)
                    SliverToBoxAdapter(
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: _accent,
                        backgroundColor: _accent.withValues(alpha: 0.12),
                      ),
                    ),
                  SliverPadding(
                    padding: pagePad.copyWith(top: 4, bottom: bottomPad),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _KeepAlive(
                          key: const ValueKey('analytics-filters'),
                          child: _filters(),
                        ),
                        const SizedBox(height: 16),
                        if (_loading && _data == null)
                          _loadingSkeleton()
                        else if (_error != null && _data == null)
                          _errorCard()
                        else ...[
                          if (_error != null) _errorCard(),
                          _hero(),
                          const SizedBox(height: 16),
                          _overviewCard(),
                          const SizedBox(height: 16),
                          if (_platform == 'all')
                            _pair(_platformCard(), _rolesCard())
                          else
                            _rolesCard(),
                          const SizedBox(height: 16),
                          _courseUsersCard(),
                          const SizedBox(height: 16),
                          _bandwidthCard(),
                          const SizedBox(height: 16),
                          _pair(_fileTypesCard(), _documentsCard()),
                          const SizedBox(height: 16),
                          _mediaPlaysCard(),
                          const SizedBox(height: 16),
                          _activityCard(),
                          const SizedBox(height: 24),
                          _sectionLabel('Other'),
                          _aiAnalysisCard(),
                          const SizedBox(height: 16),
                          _topUsersCard(),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _periodBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _data?.periodLabel ?? '',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _titleColor,
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

    return _panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
            const SizedBox(height: 16),
            _segmented(
              options: const [
                ('all', 'Combined'),
                ('mobile', 'Mobile'),
                ('web', 'Web'),
              ],
              selected: _platform,
              onSelected: _selectPlatform,
            ),
            const SizedBox(height: 10),
            _segmented(
              options: const [
                ('week', 'Weekly'),
                ('month', 'Monthly'),
                ('year', 'Yearly'),
                ('all', 'All time'),
              ],
              selected: _period,
              onSelected: _selectPeriod,
            ),
            if (_period != 'all') ...[
              const SizedBox(height: 12),
              _pillRow(
                options: [
                  for (final year in years) ('$year', '$year'),
                ],
                selected: '$_year',
                onSelected: (value) {
                  final next = int.tryParse(value);
                  if (next == null || next == _year) return;
                  HapticFeedback.selectionClick();
                  setState(() {
                    _year = next;
                    if (_period == 'week') {
                      _week = _week.clamp(1, _weeksInIsoYear(_year)).toInt();
                    }
                  });
                  if (_period == 'week') _alignWeek(animate: false);
                  _load();
                },
              ),
            ],
            if (_period == 'month') ...[
              const SizedBox(height: 10),
              _monthPills(),
            ],
            if (_period == 'week') ...[
              const SizedBox(height: 10),
              _weekPills(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final spots = _activitySpots();

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
            color: _accent.withValues(alpha: _isDark ? 0.28 : 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(right: -36, top: -48, child: _orb(168, 0.10)),
            Positioned(left: -28, bottom: -60, child: _orb(150, 0.08)),
            Positioned(right: 48, bottom: 18, child: _orb(70, 0.07)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF34D399),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _platformLabel(_platform),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data.activeUsers}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 0.95,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              data.newUsers > 0
                                  ? 'active users $_periodPhrase  ·  +${data.newUsers} new'
                                  : 'active users $_periodPhrase',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (spots.length > 1)
                        SizedBox(
                          width: _wide ? 132 : 96,
                          height: 56,
                          child: LineChart(
                            LineChartData(
                              minY: 0,
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              lineTouchData: const LineTouchData(enabled: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: Colors.white,
                                  barWidth: 2.2,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.32),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_platform == 'all') ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _heroSplitChip(
                          CupertinoIcons.device_phone_portrait,
                          '${data.mobile.activeUsers}',
                          'Mobile',
                        ),
                        const SizedBox(width: 8),
                        _heroSplitChip(
                          CupertinoIcons.globe,
                          '${data.web.activeUsers}',
                          'Web',
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _heroGlassStat(
                        CupertinoIcons.cloud_upload_fill,
                        _bytes(data.bytesUploaded),
                        'Uploaded',
                      ),
                      const SizedBox(width: 8),
                      _heroGlassStat(
                        CupertinoIcons.cloud_download_fill,
                        _bytes(data.transferDownloadBytes),
                        'Downloaded',
                      ),
                      const SizedBox(width: 8),
                      _heroGlassStat(
                        CupertinoIcons.arrow_2_circlepath,
                        _bytes(data.transferBytes),
                        'Total',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroSplitChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.82), size: 16),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroGlassStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.86), size: 15),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final cells = [
      ('${data.uploads}', 'Uploads'),
      ('${data.downloads}', 'Downloads'),
      ('${data.streams}', 'Media plays'),
      ('${data.newUsers}', 'New users'),
      (_bytes(data.avgUploadBytes), 'Avg upload'),
      (_bytes(data.avgDownloadBytes), 'Avg download'),
    ];

    Widget row(List<(String, String)> items) {
      return IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 0.5, color: _line),
              _overviewCell(items[i].$1, items[i].$2),
            ],
          ],
        ),
      );
    }

    return _panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text(
                  'Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _titleColor,
                  ),
                ),
                const Spacer(),
                Text(
                  _platformLabel(_platform),
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          _hairline(indent: 0),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: row(cells.sublist(0, 3)),
          ),
          _hairline(indent: 0),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: row(cells.sublist(3)),
          ),
        ],
      ),
    );
  }

  Widget _overviewCell(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: _titleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _platformCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final mobile = data.mobile.activeUsers;
    final web = data.web.activeUsers;

    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.device_phone_portrait,
            color: _accent,
            title: 'Platforms',
            subtitle: 'Where people are active',
            meta: '${mobile + web}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _compactSwitcher(
              options: const [
                ('download', 'Download'),
                ('upload', 'Upload'),
              ],
              selected: _platformBytesKind,
              onSelected: (value) {
                if (value == _platformBytesKind) return;
                HapticFeedback.selectionClick();
                setState(() => _platformBytesKind = value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _splitBar(mobile, web, _accent, _sky),
          ),
          _compareRow(
            'Mobile app',
            data.mobile,
            CupertinoIcons.device_phone_portrait,
            _accent,
            share: _pct(mobile, mobile + web),
            showDivider: true,
          ),
          _compareRow(
            'Web app',
            data.web,
            CupertinoIcons.globe,
            _sky,
            share: _pct(web, mobile + web),
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
    required String share,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  _glyph(icon, color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _titleColor,
                          ),
                        ),
                        Text(
                          '${count.activeUsers} active · $share',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _miniMetric('${count.uploads}', 'Uploads'),
                  _miniMetric('${count.downloads}', 'Downloads'),
                  _miniMetric('${count.streams}', 'Plays'),
                  _miniMetric(
                    _bytes(
                      _platformBytesKind == 'upload'
                          ? count.bytesUploaded
                          : count.bytesDownloaded,
                    ),
                    _platformBytesKind == 'upload' ? 'Up' : 'Down',
                  ),
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _chip.withValues(alpha: _isDark ? 0.45 : 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _titleColor,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _courseUsersCard() {
    final rows = _data?.activeUsersByCourse ?? const [];
    final total = rows.fold<int>(0, (sum, row) => sum + row.users);
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.book_fill,
            color: const Color(0xFF8B5CF6),
            title: 'Active users by course',
            subtitle: 'Who is using the library',
            meta: total > 0 ? '$total' : null,
          ),
          _pieBlock(
            values: [
              for (var i = 0; i < rows.length; i++)
                _ChartSlice(
                  label: rows[i].name,
                  value: rows[i].users.toDouble(),
                  color: _palette[i % _palette.length],
                ),
            ],
            empty: _period == 'all'
                ? 'No active users yet.'
                : 'No active users $_periodPhrase yet.',
            emptyIcon: CupertinoIcons.person_2,
            centerLabel: 'users',
          ),
          if (rows.isNotEmpty) _hairline(indent: 0),
          for (var i = 0; i < rows.length; i++)
            _progressRow(
              color: _palette[i % _palette.length],
              title: rows[i].name,
              subtitle: rows[i].kind == 'client'
                  ? 'Client workspace'
                  : rows[i].newUsers > 0
                      ? '${rows[i].newUsers} new'
                      : 'Course',
              value: '${rows[i].users}',
              progress: total == 0 ? 0 : rows[i].users / total,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _rolesCard() {
    final rows = _data?.activeUsersByRole ?? const [];
    final total = rows.fold<int>(0, (sum, row) => sum + row.users);
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.person_2_fill,
            color: const Color(0xFF10B981),
            title: 'Active users by role',
            subtitle: 'Breakdown of who is active',
            meta: total > 0 ? '$total' : null,
          ),
          if (rows.isEmpty)
            _emptyState(
              CupertinoIcons.person_crop_circle,
              _period == 'all'
                  ? 'No role activity yet.'
                  : 'No role activity $_periodPhrase.',
            )
          else
            for (var i = 0; i < rows.length; i++)
              _progressRow(
                color: _palette[i % _palette.length],
                title: rows[i].name,
                value: '${rows[i].users}',
                progress: total == 0 ? 0 : rows[i].users / total,
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
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.wifi,
            color: _sky,
            title: 'Bandwidth',
            subtitle: 'Upload and download traffic, not media plays',
            meta: _bytes(data.transferBytes),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _dualBarChart(
              points: data.series,
              uploadOf: (point) => point.bytesUploaded.toDouble(),
              downloadOf: (point) => point.bytesDownloaded.toDouble(),
              tooltip: (value) => _bytes(value.round()),
            ),
          ),
          _legendRow(const [
            (_accent, 'Upload'),
            (_sky, 'Download'),
          ]),
          _hairline(indent: 0),
          _progressRow(
            color: _accent,
            title: 'Total uploaded',
            value: _bytes(data.bytesUploaded),
            progress: _share(data.bytesUploaded, data.transferBytes),
            showDivider: true,
          ),
          _progressRow(
            color: _sky,
            title: 'Total downloaded',
            value: _bytes(data.transferDownloadBytes),
            progress: _share(data.transferDownloadBytes, data.transferBytes),
            showDivider: rows.isNotEmpty,
          ),
          for (var i = 0; i < rows.length; i++)
            _progressRow(
              color: _palette[i % _palette.length],
              title: rows[i].name,
              subtitle: _trafficSubtitle(rows[i]),
              value: _bytes(rows[i].totalBytes),
              progress: _share(rows[i].totalBytes, data.transferBytes),
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _fileTypesCard() {
    final rows = (_data?.fileTypes ?? const [])
        .where((row) => row.id != 'video' && row.id != 'audio')
        .toList();
    final slices = [
      for (final row in rows)
        if (row.totalCount > 0)
          _ChartSlice(
            label: row.name,
            value: row.totalCount.toDouble(),
            color: _typeColors[row.id] ?? _muted,
          ),
    ];
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.square_stack_3d_up_fill,
            color: const Color(0xFFF59E0B),
            title: 'File types',
            subtitle: 'Uploads and downloads, not media plays',
            meta: slices.isEmpty
                ? null
                : '${slices.fold<double>(0, (sum, item) => sum + item.value).round()}',
          ),
          _pieBlock(
            values: slices,
            empty: 'No file activity in this period yet.',
            emptyIcon: CupertinoIcons.doc,
            centerLabel: 'files',
          ),
          if (slices.isNotEmpty) _hairline(indent: 0),
          for (var i = 0; i < rows.length; i++)
            if (rows[i].totalCount > 0 || rows[i].totalBytes > 0)
              _progressRow(
                color: _typeColors[rows[i].id] ?? _muted,
                title: rows[i].name,
                subtitle: _fileTypeSubtitle(rows[i]),
                value: _bytes(rows[i].totalBytes),
                progress: _share(
                  rows[i].totalCount,
                  rows.fold<int>(0, (sum, row) => sum + row.totalCount),
                ),
                showDivider: i < rows.length - 1,
              ),
        ],
      ),
    );
  }

  List<AnalyticsFileType> _documentRows() {
    const wanted = [
      ('pdf', 'PDF'),
      ('word', 'Word'),
    ];
    final byId = <String, AnalyticsFileType>{};
    for (final row in [
      ...?_data?.documents,
      ...?_data?.fileTypes,
    ]) {
      byId.putIfAbsent(row.id, () => row);
    }
    return [
      for (final (id, name) in wanted)
        byId[id] ??
            AnalyticsFileType(
              id: id,
              name: name,
              group: 'document',
            ),
    ];
  }

  Widget _documentsCard() {
    final rows = _documentRows();
    final total = rows.fold<int>(0, (sum, row) => sum + row.totalCount);
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.doc_text_fill,
            color: const Color(0xFFEF4444),
            title: 'Documents',
            subtitle: 'Office and PDF traffic',
            meta: '$total',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _typeBarChart(rows),
          ),
          _legendRow(const [
            (_accent, 'Uploads'),
            (_sky, 'Downloads'),
          ]),
          _hairline(indent: 0),
          for (var i = 0; i < rows.length; i++)
            _progressRow(
              color: _typeColors[rows[i].id] ?? _muted,
              title: rows[i].name,
              subtitle: '${rows[i].uploads} up · ${rows[i].downloads} down',
              value: '${rows[i].totalCount}',
              progress: _share(rows[i].totalCount, total),
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _mediaPlaysCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final rows = data.mediaRows;
    final video = rows.where((row) => row.id == 'video').fold<int>(
          0,
          (sum, row) => sum + row.playCount,
        );
    final audio = rows.where((row) => row.id == 'audio').fold<int>(
          0,
          (sum, row) => sum + row.playCount,
        );
    final videoBytes = rows.where((row) => row.id == 'video').fold<int>(
          0,
          (sum, row) => sum + row.playBytes,
        );
    final audioBytes = rows.where((row) => row.id == 'audio').fold<int>(
          0,
          (sum, row) => sum + row.playBytes,
        );
    final plays = data.streams > 0 ? data.streams : video + audio;
    final playBytes = data.playBytes;
    final slices = [
      if (video > 0)
        _ChartSlice(
          label: 'Video',
          value: video.toDouble(),
          color: _typeColors['video'] ?? _media,
        ),
      if (audio > 0)
        _ChartSlice(
          label: 'Audio',
          value: audio.toDouble(),
          color: _typeColors['audio'] ?? _sky,
        ),
    ];

    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.play_circle_fill,
            color: _media,
            title: 'Media plays',
            subtitle: playBytes > 0
                ? '${_bytes(playBytes)} streamed in the player'
                : 'Video and audio opened in the player',
            meta: plays > 0 ? '$plays' : null,
          ),
          _pieBlock(
            values: slices,
            empty: 'No video or audio plays in this period yet.',
            emptyIcon: CupertinoIcons.play_circle,
            centerLabel: 'plays',
          ),
          if (plays > 0) ...[
            _hairline(indent: 0),
            _progressRow(
              color: _typeColors['video'] ?? _media,
              title: 'Video',
              subtitle: videoBytes > 0 ? _bytes(videoBytes) : 'Opened in the video player',
              value: '$video',
              progress: _share(video, plays),
              showDivider: true,
            ),
            _progressRow(
              color: _typeColors['audio'] ?? _sky,
              title: 'Audio',
              subtitle: audioBytes > 0 ? _bytes(audioBytes) : 'Opened in the audio player',
              value: '$audio',
              progress: _share(audio, plays),
              showDivider: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _singleBarChart(
                points: data.series,
                valueOf: (point) => point.streams.toDouble(),
                color: _media,
                empty: 'No play activity over time yet.',
                tooltip: (value) => '$value plays',
              ),
            ),
            _legendRow(const [
              (_media, 'Plays'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _activityCard() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.chart_bar_alt_fill,
            color: _accent,
            title: 'Activity',
            subtitle: 'Uploads and downloads over time',
            meta: '${data.uploads + data.downloads}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _dualBarChart(
              points: data.series,
              uploadOf: (point) => point.uploads.toDouble(),
              downloadOf: (point) => point.downloads.toDouble(),
              tooltip: (value) => value.round().toString(),
            ),
          ),
          _legendRow(const [
            (_accent, 'Uploads'),
            (_sky, 'Downloads'),
          ]),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _topUsersCard() {
    final uploads = _data?.topUploaders ?? const [];
    final downloads = _data?.topDownloaders ?? const [];
    final players = _data?.topPlayers ?? const [];
    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.star_fill,
            color: const Color(0xFFF59E0B),
            title: 'Top users',
            subtitle: 'Most active people this period',
          ),
          if (uploads.isEmpty && downloads.isEmpty && players.isEmpty)
            _emptyState(
              CupertinoIcons.person_2,
              'Top users appear after the first upload, download, or play.',
            )
          else ...[
            _innerHeader('Uploaders'),
            if (uploads.isEmpty)
              _emptyState(CupertinoIcons.cloud_upload, 'No uploads in this period.')
            else
              for (var i = 0; i < uploads.length; i++)
                _rankRow(
                  rank: i + 1,
                  color: _accent,
                  title: uploads[i].name,
                  subtitle: uploads[i].courseName,
                  detail: _typeBreakdown(uploads[i]),
                  value: uploads[i].bytes > 0 ? _bytes(uploads[i].bytes) : '',
                  showDivider: i < uploads.length - 1,
                ),
            _hairline(indent: 0),
            _innerHeader('Downloaders'),
            if (downloads.isEmpty)
              _emptyState(
                CupertinoIcons.cloud_download,
                'No downloads in this period.',
              )
            else
              for (var i = 0; i < downloads.length; i++)
                _rankRow(
                  rank: i + 1,
                  color: _sky,
                  title: downloads[i].name,
                  subtitle: downloads[i].courseName,
                  detail: _typeBreakdown(downloads[i]),
                  value: downloads[i].bytes > 0 ? _bytes(downloads[i].bytes) : '',
                  showDivider: i < downloads.length - 1,
                ),
            _hairline(indent: 0),
            _innerHeader('Media players'),
            if (players.isEmpty)
              _emptyState(
                CupertinoIcons.play_circle,
                'No video or audio plays in this period.',
              )
            else
              for (var i = 0; i < players.length; i++)
                _rankRow(
                  rank: i + 1,
                  color: _media,
                  title: players[i].name,
                  subtitle: players[i].courseName,
                  detail: _playsBreakdown(players[i]),
                  showDivider: i < players.length - 1,
                ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: _muted,
        ),
      ),
    );
  }

  Widget _aiAnalysisCard() {
    const chatColor = Color(0xFF6366F1);
    const scanColor = Color(0xFFF59E0B);
    const promptColor = Color(0xFF8B5CF6);
    const completionColor = Color(0xFF14B8A6);
    final ai = _data?.ai ?? const AnalyticsAiUsage();
    final rows = ai.byOwner;
    final totalTokens = ai.totalTokens > 0
        ? ai.totalTokens
        : rows.fold<int>(0, (sum, row) => sum + row.totalTokens);
    final requests = ai.requests > 0
        ? ai.requests
        : rows.fold<int>(0, (sum, row) => sum + row.requests);
    final chats = ai.chats;
    final scans = ai.imageScans;
    final chatTokens = chats.totalTokens;
    final scanTokens = scans.totalTokens;
    final chatRequests = chats.requests;
    final scanRequests = scans.requests;

    return _panel(
      child: Column(
        children: [
          _cardHeader(
            icon: CupertinoIcons.sparkles,
            color: completionColor,
            title: 'AI analysis',
            subtitle: 'Chats and image scans by course. Client usage is combined.',
            meta: totalTokens > 0 ? _tokens(totalTokens) : null,
          ),
          if (ai.isEmpty)
            _emptyState(
              CupertinoIcons.sparkles,
              'AI token use appears here after the first chat or image scan in this period.',
            )
          else ...[
            if (chatTokens > 0 || scanTokens > 0) ...[
              _pieBlock(
                values: [
                  _ChartSlice(
                    label: 'Chats',
                    value: chatTokens.toDouble(),
                    color: chatColor,
                  ),
                  _ChartSlice(
                    label: 'Image scans',
                    value: scanTokens.toDouble(),
                    color: scanColor,
                  ),
                ],
                empty: 'No AI token use in this period yet.',
                emptyIcon: CupertinoIcons.sparkles,
                centerLabel: 'tokens',
                formatTotal: (total) => _compactNumber(total.round()),
                formatSlice: (slice) =>
                    '${slice.label} · ${_tokens(slice.value.round())}',
              ),
              _hairline(indent: 0),
            ],
            _progressRow(
              color: chatColor,
              title: 'Chats',
              subtitle: chatRequests == 1
                  ? '1 text turn'
                  : '$chatRequests text turns',
              value: _tokens(chatTokens),
              progress: _share(chatTokens, totalTokens),
              showDivider: true,
            ),
            _progressRow(
              color: scanColor,
              title: 'Image scans',
              subtitle: scanRequests == 1
                  ? '1 photo question'
                  : '$scanRequests photo questions',
              value: _tokens(scanTokens),
              progress: _share(scanTokens, totalTokens),
              showDivider: true,
            ),
            _progressRow(
              color: promptColor,
              title: 'Prompt tokens',
              subtitle: 'Sent to the model',
              value: _tokens(ai.promptTokens),
              progress: _share(ai.promptTokens, totalTokens),
              showDivider: true,
            ),
            _progressRow(
              color: completionColor,
              title: 'Completion tokens',
              subtitle: 'Returned by the model',
              value: _tokens(ai.completionTokens),
              progress: _share(ai.completionTokens, totalTokens),
              showDivider: true,
            ),
            _progressRow(
              color: const Color(0xFF0EA5E9),
              title: 'Requests',
              subtitle: requests == 1 ? '1 turn' : '$requests turns',
              value: _compactNumber(requests),
              progress: 1,
              showDivider: rows.isNotEmpty,
            ),
            if (rows.isNotEmpty) _innerHeader('By course and clients'),
            for (var i = 0; i < rows.length; i++)
              _progressRow(
                color: _palette[i % _palette.length],
                title: rows[i].name,
                subtitle: _aiOwnerSubtitle(rows[i]),
                value: _tokens(rows[i].totalTokens),
                progress: _share(rows[i].totalTokens, totalTokens),
                showDivider: i < rows.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  Widget _pieBlock({
    required List<_ChartSlice> values,
    required String empty,
    required IconData emptyIcon,
    required String centerLabel,
    String Function(double total)? formatTotal,
    String Function(_ChartSlice slice)? formatSlice,
  }) {
    final slices = values.where((item) => item.value > 0).toList();
    if (slices.isEmpty) return _emptyState(emptyIcon, empty);
    final total = slices.fold<double>(0, (sum, item) => sum + item.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 214,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 58,
                    startDegreeOffset: -90,
                    sections: [
                      for (final slice in slices)
                        PieChartSectionData(
                          value: slice.value,
                          color: slice.color,
                          radius: 44,
                          title: total <= 0 || (slice.value / total) < 0.08
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatTotal?.call(total) ?? '${total.round()}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: _titleColor,
                      ),
                    ),
                    Text(
                      centerLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final slice in slices)
                _legendChip(
                  slice.color,
                  formatSlice?.call(slice) ??
                      '${slice.label} · ${slice.value.round()}',
                ),
            ],
          ),
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
      return _emptyState(
        CupertinoIcons.chart_bar,
        'No traffic in this period yet.',
      );
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
            _rod(uploadOf(points[i]), _accent, points.length),
            _rod(downloadOf(points[i]), _sky, points.length),
          ],
        ),
    ];

    return SizedBox(
      height: 228,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.18,
          barGroups: groups,
          groupsSpace: points.length > 16 ? 6 : 10,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _line.withValues(alpha: 0.85),
              strokeWidth: 0.8,
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
                reservedSize: 24,
                interval: points.length > 16 ? 5 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (points.length > 16 && index % 5 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[index].label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0F172A),
              getTooltipItem: (group, _, rod, rodIndex) {
                final label = rodIndex == 0 ? 'Upload' : 'Download';
                return BarTooltipItem(
                  '${points[group.x].label}\n$label ${tooltip(rod.toY.round())}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _singleBarChart({
    required List<AnalyticsSeriesPoint> points,
    required double Function(AnalyticsSeriesPoint) valueOf,
    required Color color,
    required String empty,
    required String Function(int) tooltip,
  }) {
    if (points.isEmpty || points.every((point) => valueOf(point) == 0)) {
      return _emptyState(CupertinoIcons.chart_bar, empty);
    }

    final maxValue = points.fold<double>(0, (current, point) {
      final local = valueOf(point);
      return local > current ? local : current;
    });
    final groups = <BarChartGroupData>[
      for (var i = 0; i < points.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [_rod(valueOf(points[i]), color, points.length)],
        ),
    ];

    return SizedBox(
      height: 196,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.18,
          barGroups: groups,
          groupsSpace: points.length > 16 ? 6 : 10,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _line.withValues(alpha: 0.85),
              strokeWidth: 0.8,
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
                reservedSize: 24,
                interval: points.length > 16 ? 5 : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (points.length > 16 && index % 5 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[index].label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0F172A),
              getTooltipItem: (group, _, rod, __) {
                return BarTooltipItem(
                  '${points[group.x].label}\n${tooltip(rod.toY.round())}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
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
      height: 214,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.2,
          groupsSpace: 14,
          barGroups: [
            for (var i = 0; i < rows.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  _rod(rows[i].uploads.toDouble(), _accent, rows.length),
                  _rod(rows[i].downloads.toDouble(), _sky, rows.length),
                ],
              ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _line.withValues(alpha: 0.85),
              strokeWidth: 0.8,
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
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= rows.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      rows[index].name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  BarChartRodData _rod(double value, Color color, int count) {
    return BarChartRodData(
      toY: value,
      width: count > 16 ? 5 : 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [color.withValues(alpha: 0.55), color],
      ),
    );
  }

  Widget _errorCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _panel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _glyph(CupertinoIcons.exclamationmark_circle_fill, _danger),
              const SizedBox(width: 12),
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

  Widget _loadingSkeleton() {
    Widget box({double height = 18, double? width}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: _chip.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    return Column(
      children: [
        _panel(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(width: 72, height: 12),
                const SizedBox(height: 12),
                box(width: 180, height: 22),
                const SizedBox(height: 10),
                box(height: 44),
                const SizedBox(height: 10),
                box(height: 44),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _panel(child: SizedBox(height: 210, child: Center(child: box(width: 160)))),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ],
    );
  }

  Widget _compactSwitcher({
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onSelected(option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected == option.$1
                          ? _accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected == option.$1
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected == option.$1
                            ? Colors.white
                            : _titleColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segmented({
    required List<(String, String)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onSelected(option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected == option.$1 ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: options.length > 3 ? 12 : 13,
                        fontWeight: selected == option.$1
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected == option.$1
                            ? Colors.white
                            : _titleColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthPills() {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (!_pinMonthWindow || _period != 'month' || !_monthScroll.hasClients) {
          return false;
        }
        final position = _monthScroll.position;
        final target = _monthWindowOffset(
          position.viewportDimension,
          position.maxScrollExtent,
        );
        if ((position.pixels - target).abs() < 1) {
          _pinMonthWindow = false;
          return false;
        }
        if (position.maxScrollExtent <= 0 &&
            12 * _monthItemExtent > position.viewportDimension + 1) {
          return false;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !_pinMonthWindow ||
              !_monthScroll.hasClients ||
              _period != 'month') {
            return;
          }
          final next = _monthScroll.position;
          final desired = _monthWindowOffset(
            next.viewportDimension,
            next.maxScrollExtent,
          );
          if ((next.pixels - desired).abs() < 1) {
            _pinMonthWindow = false;
            return;
          }
          _monthScroll.jumpTo(desired);
          _pinMonthWindow = false;
        });
        return false;
      },
      child: SingleChildScrollView(
        controller: _monthScroll,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 1; i <= 12; i++)
              Padding(
                padding: const EdgeInsets.only(right: _monthItemGap),
                child: SizedBox(
                  width: _monthItemWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        if (i == _month) return;
                        HapticFeedback.selectionClick();
                        setState(() => _month = i);
                        _alignMonth();
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == _month ? _accent : _chip,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _monthNames[i - 1].substring(0, 3),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == _month
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: i == _month ? Colors.white : _titleColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekPills() {
    final weeks = _weeksInIsoYear(_year);
    return SingleChildScrollView(
      controller: _weekScroll,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 1; i <= weeks; i++)
            Padding(
              padding: const EdgeInsets.only(right: _weekItemGap),
              child: SizedBox(
                width: _weekItemWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (i == _week) return;
                      HapticFeedback.selectionClick();
                      setState(() => _week = i);
                      _alignWeek();
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == _week ? _accent : _chip,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'W$i',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == _week
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: i == _week ? Colors.white : _titleColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pillRow({
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
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onSelected(option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected == option.$1 ? _accent : _chip,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      option.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected == option.$1
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected == option.$1
                            ? Colors.white
                            : _titleColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: _isDark ? null : Border.all(color: _line),
        boxShadow: [
          if (!_isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
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

  Widget _cardHeader({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    String? meta,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          _glyph(icon, color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: _titleColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
              ],
            ),
          ),
          if (meta != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: _isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                meta,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pair(Widget left, Widget right) {
    if (!_wide) {
      return Column(
        children: [
          left,
          const SizedBox(height: 16),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _innerHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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

  Widget _progressRow({
    required Color color,
    required String title,
    required String value,
    required double progress,
    String? subtitle,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _titleColor,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: _muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _titleColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: _isDark ? 0.16 : 0.12),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _hairline(),
      ],
    );
  }

  Widget _rankRow({
    required int rank,
    required Color color,
    required String title,
    String value = '',
    String? subtitle,
    String? detail,
    bool showDivider = false,
  }) {
    final medal = switch (rank) {
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFF94A3B8),
      3 => const Color(0xFFD97706),
      _ => _muted,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: medal.withValues(alpha: _isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: medal,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.72)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(title),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _titleColor,
                      ),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _titleColor,
                        ),
                      ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                  ],
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _titleColor,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showDivider) _hairline(indent: 82),
      ],
    );
  }

  Widget _legendRow(List<(Color, String)> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          for (final item in items) ...[
            _legendChip(item.$1, item.$2),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _legendChip(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glyph(IconData icon, Color color, {double size = 32}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }

  Widget _hairline({double indent = 16}) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(height: 0.5, thickness: 0.5, color: _line),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _chip.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _muted, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }

  Widget _splitBar(int left, int right, Color leftColor, Color rightColor) {
    final total = left + right;
    final leftFlex = total == 0 ? 1 : (left == 0 ? 1 : left);
    final rightFlex = total == 0 ? 1 : (right == 0 ? 1 : right);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            Expanded(
              flex: leftFlex,
              child: ColoredBox(color: leftColor),
            ),
            Expanded(
              flex: rightFlex,
              child: ColoredBox(color: rightColor),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _activitySpots() {
    final points = _data?.series ?? const [];
    if (points.length < 2) return const [];
    return [
      for (var i = 0; i < points.length; i++)
        FlSpot(
          i.toDouble(),
          (points[i].uploads + points[i].downloads).toDouble(),
        ),
    ];
  }

  double _share(num part, num total) => total <= 0 ? 0 : part / total;

  String _pct(num part, num total) {
    if (total <= 0) return '0%';
    return '${((part / total) * 100).round()}%';
  }

  String _bytes(int bytes) => DownloadService.formatFileSize(bytes);

  String _compactNumber(int value) {
    final abs = value.abs();
    if (abs < 1000) return '$value';
    final suffix = abs < 1000000 ? 'k' : 'M';
    final scaled = abs < 1000000 ? value / 1000 : value / 1000000;
    final absScaled = scaled.abs();
    final text = absScaled >= 100 || scaled == scaled.roundToDouble()
        ? scaled.round().toString()
        : scaled.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$text$suffix';
  }

  String _tokens(int value) => '${_compactNumber(value)} tok';

  String _aiOwnerSubtitle(AnalyticsAiOwner row) {
    final kind = row.kind == 'client'
        ? 'All clients'
        : row.kind == 'other'
            ? 'Unassigned'
            : 'Course';
    final requests =
        row.requests == 1 ? '1 request' : '${row.requests} requests';
    return '$kind · $requests';
  }

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

  String _typeBreakdown(AnalyticsTopUser user) {
    const order = [
      'pdf',
      'word',
      'excel',
      'ppt',
      'image',
      'video',
      'audio',
      'other',
    ];
    final parts = <String>[
      for (final id in order)
        if ((user.types[id] ?? 0) > 0) '${user.types[id]} $id',
    ];
    for (final entry in user.types.entries) {
      if (!order.contains(entry.key) && entry.value > 0) {
        parts.add('${entry.value} ${entry.key}');
      }
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    return user.count > 0 ? '${user.count}' : '';
  }

  String _playsBreakdown(AnalyticsTopUser user) {
    final video = user.video > 0 ? user.video : (user.types['video'] ?? 0);
    final audio = user.audio > 0 ? user.audio : (user.types['audio'] ?? 0);
    final parts = <String>[
      if (video > 0) '$video video',
      if (audio > 0) '$audio audio',
      '${user.count} plays',
    ];
    return parts.join(' · ');
  }

  String _fileTypeSubtitle(AnalyticsFileType row) {
    final parts = <String>[
      if (row.uploads > 0) '${row.uploads} uploaded',
      if (row.downloads > 0) '${row.downloads} downloaded',
    ];
    return parts.isEmpty ? 'No transfers' : parts.join(' · ');
  }

  String _trafficSubtitle(AnalyticsNamedCount row) {
    final parts = <String>[
      '${row.uploads} up',
      '${row.downloads} down',
      if (row.streams > 0) '${row.streams} plays',
    ];
    return parts.join(' · ');
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
