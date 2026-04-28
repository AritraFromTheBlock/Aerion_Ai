import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/alert_model.dart';
import '../screens/alert_details_screen.dart';

class CrisisCard extends StatelessWidget {
  final CrisisAlert alert;
  final bool isRescueMode;

  const CrisisCard({super.key, required this.alert, this.isRescueMode = false});

  @override
  Widget build(BuildContext context) {
    Color severityColor;
    switch (alert.severity) {
      case AlertSeverity.critical:
        severityColor = AppTheme.emergencyRed;
        break;
      case AlertSeverity.warning:
        severityColor = AppTheme.warningOrange;
        break;
      case AlertSeverity.safe:
        severityColor = AppTheme.successGreen;
        break;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlertDetailsScreen(
              alert: alert,
              isRescueMode: isRescueMode,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceElevated),
          boxShadow: alert.severity == AlertSeverity.critical
              ? [
                  BoxShadow(
                    color: AppTheme.emergencyRed.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 0,
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        alert.severity == AlertSeverity.critical
                            ? Icons.warning_amber_rounded
                            : (alert.severity == AlertSeverity.warning ? Icons.error_outline : Icons.check_circle_outline),
                        color: severityColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.title,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    alert.severity.name.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: severityColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  alert.distance,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  alert.time,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
