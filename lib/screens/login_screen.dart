import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'main_map_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _login(BuildContext context, bool asRescue) {
    HapticFeedback.mediumImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => MainMapScreen(isRescueMode: asRescue),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // ── Radial red glow background ──────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _GlowPainter()),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),

                  // ── AERION AI Logo ──────────────────────────
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, _) => Transform.scale(
                        scale: _pulseAnim.value,
                        child: _buildLogo(context),
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Feature chips ────────────────────────────
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(Icons.auto_awesome, 'Gemini AI Triage'),
                      _chip(Icons.location_on, 'Live GPS Tracking'),
                      _chip(Icons.people, 'Crowd Corroboration'),
                      _chip(Icons.notifications_active, 'Instant Alerts'),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // ── Role select heading ──────────────────────
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, _) => Opacity(
                      opacity: _fadeAnim.value,
                      child: Text(
                        'SELECT YOUR ROLE',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.textSecondary,
                              letterSpacing: 3,
                              fontSize: 11,
                            ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Citizen button ───────────────────────────
                  _RoleButton(
                    icon: Icons.person_outlined,
                    title: 'CITIZEN',
                    subtitle: 'Report incidents · SOS panic button',
                    color: Colors.blue,
                    onTap: () => _login(context, false),
                  ),
                  const SizedBox(height: 12),

                  // ── Responder button ─────────────────────────
                  _RoleButton(
                    icon: Icons.local_police_outlined,
                    title: 'EMERGENCY RESPONDER',
                    subtitle: 'Live dashboard · Dispatch · Analytics',
                    color: AppTheme.emergencyRed,
                    onTap: () => _login(context, true),
                    isCritical: true,
                  ),

                  const SizedBox(height: 16),

                  // ── Emergency notice ─────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.emergencyRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.emergencyRed.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppTheme.emergencyRed, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Real emergencies: always call 112 first',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.emergencyRed.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Column(
      children: [
        // ── Logo image ─────────────────────────────────────
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E6FFF).withValues(alpha: 0.35),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: AppTheme.emergencyRed.withValues(alpha: 0.2),
                blurRadius: 60,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: Image.asset(
              'assets/aerion_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: const Color(0xFF1E6FFF).withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.radar, size: 80, color: Color(0xFF1E6FFF)),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Brand name ────────────────────────────────────
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF4FC3F7), Colors.white, Color(0xFF4FC3F7)],
          ).createShader(bounds),
          child: Text(
            'AERION AI',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                  color: Colors.white,
                ),
          ),
        ),
        const SizedBox(height: 6),

        // ── Tagline ───────────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 24, height: 1.5, color: AppTheme.emergencyRed),
            const SizedBox(width: 8),
            Text(
              'SOS ALERT SYSTEM',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 3.5,
                    fontSize: 11,
                  ),
            ),
            const SizedBox(width: 8),
            Container(width: 24, height: 1.5, color: AppTheme.emergencyRed),
          ],
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceElevated),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4FC3F7), size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Role selection card ────────────────────────────────────────
class _RoleButton extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isCritical;

  const _RoleButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isCritical = false,
  });

  @override
  State<_RoleButton> createState() => _RoleButtonState();
}

class _RoleButtonState extends State<_RoleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: widget.isCritical
                ? widget.color.withValues(alpha: 0.12)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.color.withValues(alpha: widget.isCritical ? 0.5 : 0.3),
              width: widget.isCritical ? 1.5 : 1,
            ),
            boxShadow: widget.isCritical
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.isCritical ? widget.color : AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: widget.color.withValues(alpha: 0.7),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Background glow painter ────────────────────────────────────
class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.4),
        radius: 0.7,
        colors: [
          const Color(0xFF1E6FFF).withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);

    final paint2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.8),
        radius: 0.5,
        colors: [
          const Color(0xFFFF3B30).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
