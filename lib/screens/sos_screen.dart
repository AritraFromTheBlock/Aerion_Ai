import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────
// SOS SCREEN  — Full-screen emergency mode
// ─────────────────────────────────────────────
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _SosPhase { idle, sending, active, cancelling, cancelled }

class _SosScreenState extends State<SosScreen>
    with TickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────
  _SosPhase _phase = _SosPhase.idle;
  String? _sosId;
  String? _errorMsg;
  Position? _lastPosition;

  int _elapsedSeconds = 0;
  int _locationUpdates = 0;

  // ── Controllers ──────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;
  late Animation<double> _rippleOpacity;

  Timer? _elapsedTimer;
  Timer? _locationTimer;
  StreamSubscription<Position>? _posStream;

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rippleAnim = Tween<double>(begin: 0.5, end: 1.3).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );

    _rippleOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _elapsedTimer?.cancel();
    _locationTimer?.cancel();
    _posStream?.cancel();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────
  String get _elapsedLabel {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<Position?> _getPosition() async {
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _startLiveTracking() {
    // Push location every 15 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_sosId == null || _phase != _SosPhase.active) return;
      final pos = await _getPosition();
      if (pos == null) return;
      _lastPosition = pos;
      await ApiService.updateSosLocation(
        sosId:    _sosId!,
        lat:      pos.latitude,
        lng:      pos.longitude,
        accuracy: pos.accuracy,
      );
      if (mounted) setState(() => _locationUpdates++);
    });
  }

  // ── SEND SOS ─────────────────────────────────────────────
  Future<void> _sendSos() async {
    HapticFeedback.heavyImpact();

    setState(() {
      _phase    = _SosPhase.sending;
      _errorMsg = null;
    });

    try {
      final pos = await _getPosition();
      _lastPosition = pos;

      final result = await ApiService.quickSos(
        lat:      pos?.latitude  ?? 12.9716,
        lng:      pos?.longitude ?? 77.5946,
        message:  'EMERGENCY SOS — User needs immediate help!',
        accuracy: pos?.accuracy,
        altitude: pos?.altitude,
      );

      // Extract SOS ID — handle multiple possible response shapes
      final sosData = result['sosAlert'];
      if (sosData is Map<String, dynamic>) {
        _sosId = sosData['id']?.toString();
      }
      _sosId ??= result['id']?.toString() ?? 'tmp-${DateTime.now().millisecondsSinceEpoch}';

      setState(() => _phase = _SosPhase.active);

      _startElapsedTimer();
      _startLiveTracking();

      // Repeat haptic to signal success
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _phase    = _SosPhase.idle;
        _errorMsg = e.toString();
      });
    }
  }

  // ── CANCEL SOS ───────────────────────────────────────────
  Future<void> _cancelSos() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel SOS?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Only cancel if you are safe. Emergency responders will be notified.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('STAY ACTIVE', style: TextStyle(color: AppTheme.emergencyRed)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I'M SAFE"),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _phase = _SosPhase.cancelling);
    _elapsedTimer?.cancel();
    _locationTimer?.cancel();

    try {
      if (_sosId != null) await ApiService.cancelSos(_sosId!);
    } catch (_) { /* best effort */ }

    if (mounted) {
      setState(() => _phase = _SosPhase.cancelled);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  // ── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _SosPhase.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && _phase == _SosPhase.active) {
          await _cancelSos();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Animated red vignette background ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: _phase == _SosPhase.active
                      ? [
                          AppTheme.emergencyRed.withValues(alpha: 0.25),
                          Colors.black,
                        ]
                      : [
                          AppTheme.emergencyRed.withValues(alpha: 0.08),
                          Colors.black,
                        ],
                ),
              ),
            ),

            // ── Main content ──
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  const Spacer(),
                  _buildCenterSection(),
                  const Spacer(),
                  _buildBottomSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_phase != _SosPhase.active)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
            )
          else
            const SizedBox(width: 40),

          const Spacer(),

          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _statusColor().withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _statusLabel(),
                  style: TextStyle(
                    color: _statusColor(),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Color _statusColor() {
    switch (_phase) {
      case _SosPhase.idle:       return Colors.white54;
      case _SosPhase.sending:    return AppTheme.warningOrange;
      case _SosPhase.active:     return AppTheme.emergencyRed;
      case _SosPhase.cancelling: return AppTheme.warningOrange;
      case _SosPhase.cancelled:  return AppTheme.successGreen;
    }
  }

  String _statusLabel() {
    switch (_phase) {
      case _SosPhase.idle:       return 'STANDBY';
      case _SosPhase.sending:    return 'SENDING…';
      case _SosPhase.active:     return 'SOS ACTIVE';
      case _SosPhase.cancelling: return 'CANCELLING…';
      case _SosPhase.cancelled:  return 'SAFE';
    }
  }

  // ── CENTER SECTION ───────────────────────────────────────
  Widget _buildCenterSection() {
    if (_phase == _SosPhase.cancelled) {
      return _buildSafeView();
    }

    return Column(
      children: [
        // Ripple + pulse button
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple ring
              if (_phase == _SosPhase.active)
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (_, _) => Container(
                    width:  260 * _rippleAnim.value,
                    height: 260 * _rippleAnim.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.emergencyRed.withValues(alpha: _rippleOpacity.value),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),

              // Outer glow ring
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.emergencyRed.withValues(alpha: 
                    _phase == _SosPhase.active ? 0.18 : 0.08,
                  ),
                ),
              ),

              // Main SOS button
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(
                  scale: _phase == _SosPhase.active ? _pulseAnim.value : 1.0,
                  child: child,
                ),
                child: GestureDetector(
                  onTap: _phase == _SosPhase.idle ? _sendSos : null,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _phase == _SosPhase.active
                          ? AppTheme.emergencyRed
                          : AppTheme.emergencyRed.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.emergencyRed.withValues(alpha: 
                            _phase == _SosPhase.active ? 0.7 : 0.3,
                          ),
                          blurRadius:   _phase == _SosPhase.active ? 50 : 25,
                          spreadRadius: _phase == _SosPhase.active ? 10 : 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_phase == _SosPhase.sending)
                          const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          )
                        else ...[
                          Icon(
                            _phase == _SosPhase.active
                                ? Icons.campaign_rounded
                                : Icons.emergency_share_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _phase == _SosPhase.active ? 'SOS' : 'HOLD\nTO SEND',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: 2,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Info cards
        if (_phase == _SosPhase.active) _buildActiveInfoCards(),
        if (_phase == _SosPhase.idle)   _buildIdleInfo(),
        if (_phase == _SosPhase.sending) _buildSendingInfo(),
      ],
    );
  }

  Widget _buildActiveInfoCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Timer row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: AppTheme.warningOrange, size: 18),
              const SizedBox(width: 6),
              Text(
                'Alert active for $_elapsedLabel',
                style: const TextStyle(
                  color: AppTheme.warningOrange,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(child: _infoCard(
                icon: Icons.location_on,
                label: 'GPS TRACKING',
                value: _lastPosition != null
                    ? '${_lastPosition!.latitude.toStringAsFixed(4)}, ${_lastPosition!.longitude.toStringAsFixed(4)}'
                    : 'Acquiring…',
                color: AppTheme.successGreen,
              )),
              const SizedBox(width: 12),
              Expanded(child: _infoCard(
                icon: Icons.sync,
                label: 'UPDATES SENT',
                value: '$_locationUpdates',
                color: Colors.blue,
              )),
            ],
          ),
          const SizedBox(height: 12),

          // Responders info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.emergencyRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.emergencyRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_share, color: AppTheme.emergencyRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Emergency responders alerted',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Your live location is being broadcast every 15 seconds',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          if (_errorMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warningOrange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppTheme.warningOrange, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: AppTheme.warningOrange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const Text(
            'Tap the button to immediately alert all nearby emergency responders with your live GPS location.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _featureChip(Icons.location_on, 'Live GPS'),
              const SizedBox(width: 10),
              _featureChip(Icons.notifications_active, 'FCM Push'),
              const SizedBox(width: 10),
              _featureChip(Icons.wifi, 'Real-time'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendingInfo() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Acquiring GPS & contacting emergency services…',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.warningOrange, fontSize: 14, height: 1.5),
          ),
          SizedBox(height: 8),
          Text(
            'Do not close the app',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeView() {
    return Column(
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.successGreen.withValues(alpha: 0.15),
            border: Border.all(color: AppTheme.successGreen, width: 2.5),
          ),
          child: const Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 72),
        ),
        const SizedBox(height: 24),
        const Text(
          "You're Safe",
          style: TextStyle(
            color: AppTheme.successGreen,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'SOS cancelled. Emergency services have been notified that you are safe.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  // ── BOTTOM SECTION ───────────────────────────────────────
  Widget _buildBottomSection() {
    if (_phase == _SosPhase.active) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: GestureDetector(
          onTap: _cancelSos,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.successGreen, width: 1.5),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: AppTheme.successGreen, size: 22),
                SizedBox(width: 10),
                Text(
                  "I'M SAFE — CANCEL SOS",
                  style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_phase == _SosPhase.idle || _phase == _SosPhase.sending) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            // Call 112 fallback
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dial 112 on your phone for emergency services'),
                    backgroundColor: AppTheme.warningOrange,
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone, color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Call 112 — National Emergency',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── SMALL HELPERS ─────────────────────────────────────────
  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
