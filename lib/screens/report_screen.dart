import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../services/api_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  bool _isSendingSos = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Get current GPS location ─────────────────────────────
  Future<Position?> _getLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  // ── Submit AI-triaged incident report ────────────────────
  Future<void> _submitReport() async {
    final text = _controller.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the situation (min 5 characters).')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final position = await _getLocation();
      final result = await ApiService.quickReport(
        message: text,
        lat:     position?.latitude  ?? 12.9716,
        lng:     position?.longitude ?? 77.5946,
      );

      if (!mounted) return;

      final bool clustered = result['clustered'] == true;
      final int? corrobCount =
          (result['incident']?['corroboration_count'] as num?)?.toInt();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clustered
                ? '✅ Added as confirmation #$corrobCount — responders already notified!'
                : '✅ Report sent! AI triage complete. Help is on the way.',
          ),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed: ${e.toString()}'),
          backgroundColor: AppTheme.emergencyRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Panic SOS button ─────────────────────────────────────
  Future<void> _sendSos() async {
    setState(() => _isSendingSos = true);
    try {
      final position = await _getLocation();
      await ApiService.quickSos(
        lat:     position?.latitude  ?? 12.9716,
        lng:     position?.longitude ?? 77.5946,
        message: _controller.text.trim().isNotEmpty
            ? _controller.text.trim()
            : 'EMERGENCY SOS — User needs immediate help!',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🆘 SOS sent to ALL emergency responders!'),
          backgroundColor: AppTheme.emergencyRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ SOS failed: ${e.toString()}'),
          backgroundColor: AppTheme.emergencyRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingSos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Incident Report'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Describe the situation',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Our AI will automatically classify the incident type, severity, and alert responders.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),

              // AI badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: AppTheme.successGreen, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Powered by Gemini AI — instant triage',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.successGreen,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.surfaceElevated),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Trapped on the second floor, water is rising fast. About 10 people here...',
                      hintStyle: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Submit report button
              _isSending
                  ? const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: AppTheme.emergencyRed),
                          SizedBox(height: 8),
                          Text('AI triaging your report...',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : PrimaryButton(
                      text: 'SEND AI REPORT',
                      icon: Icons.psychology,
                      isCritical: true,
                      onPressed: _submitReport,
                    ),
              const SizedBox(height: 12),

              // Pure SOS panic button
              _isSendingSos
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.warningOrange),
                    )
                  : PrimaryButton(
                      text: 'PANIC SOS — INSTANT ALERT',
                      icon: Icons.emergency,
                      isCritical: false,
                      onPressed: _sendSos,
                    ),
              const SizedBox(height: 12),

              PrimaryButton(
                text: 'CANCEL',
                isCritical: false,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
