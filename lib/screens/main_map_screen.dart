import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../widgets/crisis_card.dart';
import '../models/alert_model.dart';
import '../services/api_service.dart';
import 'report_screen.dart';
import 'sos_screen.dart';
import 'rescue_dashboard_screen.dart';

class MainMapScreen extends StatefulWidget {
  final bool isRescueMode;
  const MainMapScreen({super.key, required this.isRescueMode});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  bool _isLoadingLocation = true;
  bool _isLoadingIncidents = false;
  List<CrisisAlert> _liveAlerts = [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
        _mapController.move(_currentPosition!, 14.0);
        _loadNearbyIncidents(position.latitude, position.longitude);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        // Fallback: load with default coords (Bangalore)
        _loadNearbyIncidents(12.9716, 77.5946);
      }
    }
  }

  Future<void> _loadNearbyIncidents(double lat, double lng) async {
    setState(() {
      _isLoadingIncidents = true;
      _loadError = null;
    });

    try {
      final rawList = await ApiService.getNearbyIncidents(
        lat:      lat,
        lng:      lng,
        radiusKm: 20,
      );

      final alerts = rawList.map((raw) {
        final map = raw as Map<String, dynamic>;
        AlertSeverity severity;
        final sev = (map['severity'] as String? ?? 'warning').toLowerCase();
        if (sev == 'critical') {
          severity = AlertSeverity.critical;
        } else if (sev == 'safe') {
          severity = AlertSeverity.safe;
        } else {
          severity = AlertSeverity.warning;
        }

        return CrisisAlert(
          id:          map['id']?.toString()          ?? '',
          title:       map['title']?.toString()        ?? map['incident_type']?.toString() ?? 'Unknown',
          description: map['description']?.toString()  ?? map['ai_summary']?.toString()    ?? '',
          severity:    severity,
          time:        map['time']?.toString()         ?? 'Unknown',
          distance:    map['distance']?.toString()     ?? '',
          latitude:    (map['latitude']  as num?)?.toDouble() ?? (map['lat'] as num?)?.toDouble() ?? 0.0,
          longitude:   (map['longitude'] as num?)?.toDouble() ?? (map['lng'] as num?)?.toDouble() ?? 0.0,
          corroborationCount: (map['corroboration_count'] as num?)?.toInt() ?? 1,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _liveAlerts         = alerts;
          _isLoadingIncidents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError          = e.toString();
          _isLoadingIncidents = false;
          _liveAlerts         = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Interactive Map ──────────────────────────────
          SizedBox(
            width:  double.infinity,
            height: double.infinity,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition ?? const LatLng(12.9716, 77.5946),
                initialZoom:   13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:       'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.aerion_ai',
                ),
                MarkerLayer(
                  markers: [
                    // Live backend incidents
                    ..._liveAlerts.map((alert) {
                      Color markerColor;
                      switch (alert.severity) {
                        case AlertSeverity.critical: markerColor = AppTheme.emergencyRed;   break;
                        case AlertSeverity.warning:  markerColor = AppTheme.warningOrange;  break;
                        case AlertSeverity.safe:     markerColor = AppTheme.successGreen;   break;
                      }
                      final count = alert.corroborationCount ?? 1;
                      return Marker(
                        point:  LatLng(alert.latitude, alert.longitude),
                        width:  count > 3 ? 52 : 40,
                        height: count > 3 ? 52 : 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.location_on, color: markerColor, size: count > 3 ? 52 : 40),
                            if (count > 1)
                              Positioned(
                                top: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: markerColor, width: 1.5),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: markerColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),

                    // Live user location marker
                    if (_currentPosition != null)
                      Marker(
                        point:  _currentPosition!,
                        width:  40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color:  Colors.blue.withValues(alpha: 0.3),
                            shape:  BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width:  16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color:  Colors.blue,
                                shape:  BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.white, spreadRadius: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Top overlay ──────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Live incidents count badge
                if (!_isLoadingIncidents)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.surfaceElevated),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: _liveAlerts.isEmpty
                                    ? AppTheme.successGreen
                                    : AppTheme.emergencyRed,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _liveAlerts.isEmpty
                                    ? 'No active incidents nearby'
                                    : '${_liveAlerts.length} active incident${_liveAlerts.length > 1 ? 's' : ''} nearby',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Refresh button
                        GestureDetector(
                          onTap: () {
                            if (_currentPosition != null) {
                              _loadNearbyIncidents(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.surfaceElevated),
                            ),
                            child: Icon(
                              _isLoadingIncidents ? Icons.hourglass_top : Icons.refresh,
                              color: AppTheme.textPrimary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error banner
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.warningOrange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.warningOrange.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: AppTheme.warningOrange, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Could not load live incidents. Tap refresh to retry.',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.warningOrange,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Rescue mode dashboard button
                if (widget.isRescueMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surface,
                          side: const BorderSide(color: AppTheme.warningOrange),
                        ),
                        icon: const Icon(Icons.dashboard, color: AppTheme.warningOrange),
                        label: const Text('Dashboard', style: TextStyle(color: AppTheme.warningOrange)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RescueDashboardScreen(
                                liveAlerts: _liveAlerts,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                const Spacer(),

                // Bottom incident list (citizen mode)
                if (!widget.isRescueMode && _liveAlerts.isNotEmpty)
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 16, bottom: 16),
                      itemCount: _liveAlerts.length,
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 300,
                          child: CrisisCard(
                            alert: _liveAlerts[index],
                            isRescueMode: false,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ── Loading overlay ──────────────────────────────
          if (_isLoadingLocation)
            Container(
              color: AppTheme.background.withValues(alpha: 0.85),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.successGreen),
                    SizedBox(height: 16),
                    Text('Acquiring GPS Signal...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: widget.isRescueMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Secondary: AI Report button
                FloatingActionButton.extended(
                  heroTag: 'reportFab',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ReportScreen()),
                    ).then((_) {
                      if (_currentPosition != null) {
                        _loadNearbyIncidents(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        );
                      }
                    });
                  },
                  backgroundColor: AppTheme.surfaceElevated,
                  elevation: 2,
                  icon: const Icon(Icons.psychology, color: AppTheme.warningOrange),
                  label: const Text(
                    'AI REPORT',
                    style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                // Primary: SOS panic button
                FloatingActionButton.extended(
                  heroTag: 'sosFab',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SosScreen()),
                    );
                  },
                  backgroundColor: AppTheme.emergencyRed,
                  elevation: 6,
                  icon: const Icon(Icons.emergency_share_rounded, color: Colors.white),
                  label: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
