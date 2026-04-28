import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../models/alert_model.dart';
import '../widgets/primary_button.dart';
import '../services/api_service.dart';

class AlertDetailsScreen extends StatefulWidget {
  final CrisisAlert alert;
  final bool isRescueMode;

  const AlertDetailsScreen({
    super.key,
    required this.alert,
    required this.isRescueMode,
  });

  @override
  State<AlertDetailsScreen> createState() => _AlertDetailsScreenState();
}

class _AlertDetailsScreenState extends State<AlertDetailsScreen> {
  late AlertSeverity _currentSeverity;
  bool _rescueRequested = false;
  bool _isCorroborating = false;
  bool _hasCorroborated = false;
  late int _corroborationCount;

  // AI retriage state
  bool _isRetriaging = false;
  String? _retriagedDescription;
  bool _retriageFailed = false;

  @override
  void initState() {
    super.initState();
    _currentSeverity = widget.alert.severity;
    _corroborationCount = widget.alert.corroborationCount ?? 1;

    // Auto-retriage if the current description is the fallback text
    if (ApiService.isTriageFallback(widget.alert.description)) {
      _autoRetriage();
    }
  }

  Future<void> _autoRetriage() async {
    if (widget.alert.id.isEmpty) return;
    setState(() {
      _isRetriaging = true;
      _retriageFailed = false;
    });
    try {
      final result = await ApiService.retriageIncident(widget.alert.id);
      if (mounted) {
        final newSummary = result['aiSummary']?.toString() ?? '';
        if (result['retriaged'] == true && newSummary.isNotEmpty) {
          setState(() {
            _retriagedDescription = newSummary;
            _isRetriaging = false;
          });
        } else if (result['retriaged'] == false && !ApiService.isTriageFallback(newSummary)) {
          // Already had valid analysis on server side
          setState(() {
            _retriagedDescription = newSummary;
            _isRetriaging = false;
          });
        } else {
          setState(() {
            _isRetriaging = false;
            _retriageFailed = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRetriaging = false;
          _retriageFailed = true;
        });
      }
    }
  }

  /// Returns the best available description (retriage result or original)
  String get _effectiveDescription =>
      _retriagedDescription ?? widget.alert.description;

  Future<void> _corroborate() async {
    if (_hasCorroborated || _isCorroborating) return;
    HapticFeedback.lightImpact();
    setState(() => _isCorroborating = true);
    try {
      await ApiService.corroborateIncident(widget.alert.id);
      if (mounted) {
        setState(() {
          _hasCorroborated = true;
          _corroborationCount++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ You confirmed this incident ($_corroborationCount reports total)'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not confirm: ${e.toString()}'),
            backgroundColor: AppTheme.warningOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCorroborating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color severityColor;
    String statusText;
    IconData statusIcon;

    switch (_currentSeverity) {
      case AlertSeverity.critical:
        severityColor = AppTheme.emergencyRed;
        statusText = 'CRITICAL';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case AlertSeverity.warning:
        severityColor = AppTheme.warningOrange;
        statusText = 'IN PROGRESS';
        statusIcon = Icons.error_outline;
        break;
      case AlertSeverity.safe:
        severityColor = AppTheme.successGreen;
        statusText = 'SAFE / RESOLVED';
        statusIcon = Icons.check_circle_outline;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Corroborate button (citizen mode)
          if (!widget.isRescueMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _isCorroborating
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.warningOrange),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        _hasCorroborated ? Icons.thumb_up : Icons.thumb_up_outlined,
                        color: _hasCorroborated ? AppTheme.successGreen : AppTheme.warningOrange,
                      ),
                      tooltip: 'Confirm this incident',
                      onPressed: _hasCorroborated ? null : _corroborate,
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Live Map ─────────────────────────────────
                    SizedBox(
                      height: 220,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(widget.alert.latitude, widget.alert.longitude),
                              initialZoom: 15.0,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.aerion_ai',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(widget.alert.latitude, widget.alert.longitude),
                                    width: 60,
                                    height: 60,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: severityColor,
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(color: severityColor.withValues(alpha: 0.5), blurRadius: 8),
                                            ],
                                          ),
                                          child: Text(
                                            statusText,
                                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        Icon(statusIcon, color: severityColor, size: 28),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Map gradient overlay at bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, AppTheme.background.withValues(alpha: 0.8)],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Status Badge ──────────────────────────
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, color: severityColor, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      statusText,
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            color: severityColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Corroboration badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.surfaceElevated),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.people, color: AppTheme.textSecondary, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$_corroborationCount confirmed',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Title ────────────────────────────────
                          Text(
                            widget.alert.title,
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
                          ),
                          const SizedBox(height: 8),

                          // ── Meta ─────────────────────────────────
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 16, color: AppTheme.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.alert.distance.isNotEmpty
                                      ? widget.alert.distance
                                      : '${widget.alert.latitude.toStringAsFixed(4)}, ${widget.alert.longitude.toStringAsFixed(4)}',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                widget.alert.time,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── AI Summary ───────────────────────────
                          _buildAiAnalysisSection(context),

                          // ── Safety Guidance ──────────────────────
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: severityColor.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: severityColor.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.shield, color: severityColor, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Safety Guidance',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _getSafetyGuidance(widget.alert.title),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: AppTheme.textSecondary,
                                        height: 1.5,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Action Buttons ───────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: AppTheme.background,
                border: Border(top: BorderSide(color: AppTheme.surfaceElevated)),
              ),
              child: widget.isRescueMode ? _buildResponderActions() : _buildUserActions(),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Analysis Section Widget ──────────────────────────────
  Widget _buildAiAnalysisSection(BuildContext context) {
    final isFallback = ApiService.isTriageFallback(_effectiveDescription);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with optional loading indicator
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.warningOrange, size: 16),
            const SizedBox(width: 8),
            Text(
              'AI Analysis',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
            ),
            if (_isRetriaging) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.warningOrange,
                ),
              ),
            ],
            if (!_isRetriaging && !isFallback)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.successGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Gemini AI',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.successGreen,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Content card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isRetriaging
                  ? AppTheme.warningOrange.withValues(alpha: 0.4)
                  : (isFallback
                      ? AppTheme.surfaceElevated
                      : AppTheme.successGreen.withValues(alpha: 0.3)),
            ),
          ),
          child: _isRetriaging
              // Loading state
              ? Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.warningOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Running Gemini AI triage analysis…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                )
              : isFallback
                  // Fallback / retriage failed state
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: AppTheme.warningOrange,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'AI analysis could not be generated for this incident.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.textSecondary,
                                      height: 1.5,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        if (_retriageFailed) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _autoRetriage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.warningOrange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.warningOrange.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.refresh, color: AppTheme.warningOrange, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Retry AI Analysis',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: AppTheme.warningOrange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  // Success state — real AI analysis
                  : Text(
                      _effectiveDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textPrimary,
                            height: 1.6,
                          ),
                    ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _getSafetyGuidance(String incidentType) {
    final t = incidentType.toLowerCase();
    if (t.contains('fire') || t.contains('flood'))         return 'Evacuate immediately. Do not re-enter buildings. Follow emergency services instructions and move to higher ground if flooding.';
    if (t.contains('earthquake') || t.contains('structur')) return 'Drop, cover, and hold on. Move away from buildings after shaking stops. Watch for falling debris.';
    if (t.contains('medical'))                             return 'Do not move the person unless in danger. Call 112. Keep them calm and still. Begin CPR if trained and needed.';
    if (t.contains('gas') || t.contains('chemical'))       return 'Do not use any electrical switches. Evacuate the area immediately. Avoid open flames. Call emergency services.';
    if (t.contains('violence'))                            return 'Move to safety immediately. Do not confront the threat. Contact law enforcement at 100. Warn others quietly.';
    return 'Follow local authority instructions. Stay calm. Keep emergency contacts ready. Do not return until cleared.';
  }

  Widget _buildUserActions() {
    final bool isSafe = _currentSeverity == AlertSeverity.safe;

    return Column(
      children: [
        if (!isSafe) ...[
          PrimaryButton(
            text: _rescueRequested ? '✓ RESCUE REQUESTED' : 'REQUEST RESCUE',
            icon: _rescueRequested ? Icons.check : Icons.emergency,
            isCritical: !_rescueRequested,
            onPressed: () {
              if (!_rescueRequested) {
                HapticFeedback.heavyImpact();
                setState(() => _rescueRequested = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('🚨 Rescue request sent to nearby responders'),
                    backgroundColor: AppTheme.emergencyRed,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        PrimaryButton(
          text: 'I AM SAFE',
          icon: Icons.check_circle,
          isCritical: false,
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              _currentSeverity = AlertSeverity.safe;
              _rescueRequested = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildResponderActions() {
    final bool isResolved = _currentSeverity == AlertSeverity.safe;

    if (isResolved) {
      return PrimaryButton(
        text: '✓ INCIDENT RESOLVED',
        icon: Icons.check,
        isCritical: false,
        onPressed: () => Navigator.pop(context),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                text: 'NAVIGATE',
                icon: Icons.navigation,
                isCritical: false,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Navigate to: ${widget.alert.latitude.toStringAsFixed(5)}, ${widget.alert.longitude.toStringAsFixed(5)}',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                text: 'DISPATCH',
                icon: Icons.local_shipping,
                isCritical: false,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dispatch request sent to command'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          text: 'MARK IN PROGRESS',
          icon: Icons.update,
          isCritical: false,
          onPressed: () {
            setState(() => _currentSeverity = AlertSeverity.warning);
          },
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          text: 'MARK RESOLVED',
          icon: Icons.done_all,
          isCritical: true,
          onPressed: () {
            setState(() => _currentSeverity = AlertSeverity.safe);
          },
        ),
      ],
    );
  }
}
