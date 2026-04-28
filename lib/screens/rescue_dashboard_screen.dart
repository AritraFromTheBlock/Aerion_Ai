import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/alert_model.dart';
import '../widgets/crisis_card.dart';
import '../services/api_service.dart';

class RescueDashboardScreen extends StatefulWidget {
  final List<CrisisAlert> liveAlerts;
  const RescueDashboardScreen({super.key, this.liveAlerts = const []});

  @override
  State<RescueDashboardScreen> createState() => _RescueDashboardScreenState();
}

class _RescueDashboardScreenState extends State<RescueDashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────
  bool _isLoadingStats = false;
  Map<String, dynamic>? _trends;
  String? _statsError;
  bool _usingDemoData = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Demo / fallback data for live presentation ──────────────
  static Map<String, dynamic> _generateDemoTrends() {
    final now = DateTime.now();
    return {
      'success': true,
      'windowHours': 168,
      'incidentsByType': [
        {'incident_type': 'FIRE', 'count': '14', 'avg_corroboration': '3.2'},
        {'incident_type': 'FLOOD', 'count': '11', 'avg_corroboration': '4.1'},
        {'incident_type': 'MEDICAL', 'count': '9', 'avg_corroboration': '2.8'},
        {'incident_type': 'ACCIDENT', 'count': '7', 'avg_corroboration': '2.4'},
        {'incident_type': 'STRUCTURAL', 'count': '5', 'avg_corroboration': '1.9'},
        {'incident_type': 'CHEMICAL', 'count': '3', 'avg_corroboration': '1.5'},
        {'incident_type': 'OTHER', 'count': '2', 'avg_corroboration': '1.0'},
      ],
      'incidentsBySeverity': [
        {'severity': 'CRITICAL', 'count': '8'},
        {'severity': 'HIGH', 'count': '15'},
        {'severity': 'MODERATE', 'count': '12'},
        {'severity': 'LOW', 'count': '6'},
      ],
      'hourlyVolume': List.generate(24, (i) {
        final hour = now.subtract(Duration(hours: 23 - i));
        final base = (i < 6) ? 1 : (i < 12) ? 3 : (i < 18) ? 5 : 2;
        return {
          'hour': hour.toIso8601String(),
          'count': '${base + (i % 3)}',
          'high_priority_count': '${(base * 0.4).round()}',
        };
      }),
      'avgResponseMinutes': 4.7,
    };
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoadingStats = true;
      _statsError = null;
      _usingDemoData = false;
    });
    try {
      final trends = await ApiService.getAnalyticsTrends(hours: 168);
      if (mounted) {
        setState(() {
          _trends = trends;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      // ── FALLBACK: use demo data so the presentation always works ──
      if (mounted) {
        setState(() {
          _trends = _generateDemoTrends();
          _usingDemoData = true;
          _isLoadingStats = false;
          _statsError = null; // clear error — we have demo data
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.liveAlerts;
    final criticalCount = alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final warningCount  = alerts.where((a) => a.severity == AlertSeverity.warning).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(color: AppTheme.successGreen, shape: BoxShape.circle),
            ),
            const Text('Rescue Dashboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh stats',
            onPressed: _loadStats,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.emergencyRed,
          tabs: const [
            Tab(text: 'LIVE INCIDENTS'),
            Tab(text: 'ANALYTICS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveTab(alerts, criticalCount, warningCount),
          _buildAnalyticsTab(),
        ],
      ),
    );
  }

  // ── TAB 1: Live Incidents ─────────────────────────────────────
  Widget _buildLiveTab(List<CrisisAlert> alerts, int criticalCount, int warningCount) {
    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppTheme.emergencyRed,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats row ──────────────────────────────────────
            Row(
              children: [
                Expanded(child: _statCard(
                  title: 'Active',
                  value: alerts.length.toString(),
                  color: AppTheme.emergencyRed,
                  icon: Icons.crisis_alert,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  title: 'Critical',
                  value: criticalCount.toString(),
                  color: AppTheme.warningOrange,
                  icon: Icons.warning_amber_rounded,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  title: 'Warnings',
                  value: warningCount.toString(),
                  color: Colors.blue,
                  icon: Icons.error_outline,
                )),
              ],
            ),
            const SizedBox(height: 20),

            // ── Source badge ──────────────────────────────────
            Row(
              children: [
                if (alerts.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: AppTheme.successGreen, size: 8),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE — AERION AI backend',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.successGreen),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(
                  '${alerts.length} incident${alerts.length != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text('High Priority Reports', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),

            if (alerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.surfaceElevated),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'All Clear',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppTheme.successGreen),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No active incidents in your area.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: alerts.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CrisisCard(alert: alerts[index], isRescueMode: true),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── TAB 2: Analytics ──────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.emergencyRed));
    }

    // If trends is still null (shouldn't happen with demo fallback), show empty
    if (_trends == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: AppTheme.warningOrange, size: 48),
              const SizedBox(height: 16),
              Text('Could not load analytics', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Requires backend connectivity',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final byType     = (_trends?['incidentsByType']     as List?) ?? [];
    final bySeverity = (_trends?['incidentsBySeverity'] as List?) ?? [];
    final hourly     = (_trends?['hourlyVolume']        as List?) ?? [];
    final avgResp    = _trends?['avgResponseMinutes'];

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppTheme.emergencyRed,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Demo-data banner ────────────────────────────────
            if (_usingDemoData)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Displaying demo analytics — backend offline. Tap refresh to reconnect.',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Quick stat cards row ────────────────────────────
            Row(
              children: [
                Expanded(child: _statCard(
                  title: 'Total (7d)',
                  value: _totalFromList(byType).toString(),
                  color: AppTheme.emergencyRed,
                  icon: Icons.assessment,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  title: 'Avg Response',
                  value: avgResp != null ? '${(avgResp is num ? avgResp : double.tryParse(avgResp.toString()) ?? 0).toStringAsFixed(1)}m' : '—',
                  color: AppTheme.successGreen,
                  icon: Icons.timer,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  title: 'Peak/hr',
                  value: _peakFromHourly(hourly).toString(),
                  color: Colors.blue,
                  icon: Icons.trending_up,
                )),
              ],
            ),
            const SizedBox(height: 24),

            // ── Hourly Volume Sparkline ─────────────────────────
            if (hourly.isNotEmpty) ...[
              _sectionHeader('24h Incident Volume', Icons.show_chart, 'Hourly'),
              const SizedBox(height: 12),
              _buildSparkline(hourly),
              const SizedBox(height: 24),
            ],

            // ── Incidents by Type ───────────────────────────────
            _sectionHeader('Incidents by Type', Icons.category, '7-day window'),
            const SizedBox(height: 12),

            if (byType.isEmpty)
              _emptyCard('No incident data yet')
            else
              ...byType.map<Widget>((item) {
                final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
                final maxCount = byType.fold<int>(
                  1,
                  (m, i) => (int.tryParse(i['count']?.toString() ?? '0') ?? 0) > m
                      ? (int.tryParse(i['count']?.toString() ?? '0') ?? 0)
                      : m,
                );
                return _barRow(
                  label: item['incident_type']?.toString() ?? 'Unknown',
                  count: count,
                  maxCount: maxCount,
                  color: _colorForType(item['incident_type']?.toString() ?? ''),
                );
              }),

            const SizedBox(height: 24),
            _sectionHeader('By Severity', Icons.bar_chart, 'Active incidents'),
            const SizedBox(height: 12),

            if (bySeverity.isEmpty)
              _emptyCard('No severity data yet')
            else
              ...bySeverity.map<Widget>((item) {
                final sev   = item['severity']?.toString() ?? '';
                final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
                final maxCount = bySeverity.fold<int>(
                  1,
                  (m, i) => (int.tryParse(i['count']?.toString() ?? '0') ?? 0) > m
                      ? (int.tryParse(i['count']?.toString() ?? '0') ?? 0)
                      : m,
                );
                Color col;
                switch (sev.toUpperCase()) {
                  case 'CRITICAL': col = AppTheme.emergencyRed;   break;
                  case 'HIGH':     col = AppTheme.warningOrange;  break;
                  case 'MODERATE': col = Colors.blue;             break;
                  default:         col = AppTheme.successGreen;
                }
                return _barRow(label: sev, count: count, maxCount: maxCount, color: col);
              }),

            const SizedBox(height: 24),

            // ── AI info card ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceElevated),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.warningOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Powered by Gemini AI', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(
                          'All incidents are AI-triaged with severity classification and crowd corroboration.',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Sparkline bar chart for hourly volume ──────────────────────
  Widget _buildSparkline(List hourly) {
    final counts = hourly.map<int>((h) => int.tryParse(h['count']?.toString() ?? '0') ?? 0).toList();
    final maxVal = counts.fold<int>(1, (m, v) => v > m ? v : m);

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceElevated),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(counts.length, (i) {
          final frac = counts[i] / maxVal;
          final isHighPeak = counts[i] == maxVal;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '${counts[i]} incidents',
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 400 + i * 20),
                  curve: Curves.easeOutCubic,
                  height: (frac * 80).clamp(4.0, 80.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: isHighPeak
                          ? [AppTheme.emergencyRed, AppTheme.warningOrange]
                          : [AppTheme.emergencyRed.withValues(alpha: 0.5), AppTheme.warningOrange.withValues(alpha: 0.3)],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────
  int _totalFromList(List items) {
    int t = 0;
    for (final item in items) {
      t += int.tryParse(item['count']?.toString() ?? '0') ?? 0;
    }
    return t;
  }

  int _peakFromHourly(List hourly) {
    int peak = 0;
    for (final h in hourly) {
      final c = int.tryParse(h['count']?.toString() ?? '0') ?? 0;
      if (c > peak) peak = c;
    }
    return peak;
  }

  Color _colorForType(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':        return const Color(0xFFFF6B35);
      case 'FLOOD':       return const Color(0xFF4FC3F7);
      case 'MEDICAL':     return const Color(0xFFEF5350);
      case 'ACCIDENT':    return const Color(0xFFFFB74D);
      case 'STRUCTURAL':  return const Color(0xFF9575CD);
      case 'CHEMICAL':    return const Color(0xFF66BB6A);
      default:            return AppTheme.warningOrange;
    }
  }

  Widget _statCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(color: color, fontSize: 28),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.warningOrange, size: 18),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
        const Spacer(),
        Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceElevated),
      ),
      child: Center(
        child: Text(msg, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
      ),
    );
  }

  Widget _barRow({
    required String label,
    required int count,
    required int maxCount,
    required Color color,
  }) {
    final fraction = maxCount > 0 ? count / maxCount : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.toDouble(),
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
