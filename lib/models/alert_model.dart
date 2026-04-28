enum AlertSeverity { critical, warning, safe }

class CrisisAlert {
  final String id;
  final String title;
  final String description;
  final AlertSeverity severity;
  final String time;
  final String distance;
  final double latitude;
  final double longitude;
  final int? corroborationCount;

  const CrisisAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.time,
    required this.distance,
    required this.latitude,
    required this.longitude,
    this.corroborationCount,
  });

  factory CrisisAlert.fromJson(Map<String, dynamic> json) {
    AlertSeverity severity;
    final sev = (json['severity'] as String? ?? 'warning').toLowerCase();
    if (sev == 'critical') {
      severity = AlertSeverity.critical;
    } else if (sev == 'safe') {
      severity = AlertSeverity.safe;
    } else {
      severity = AlertSeverity.warning;
    }

    return CrisisAlert(
      id:                 json['id']?.toString()         ?? '',
      title:              json['title']?.toString()       ?? json['incident_type']?.toString() ?? 'Unknown',
      description:        json['description']?.toString() ?? json['ai_summary']?.toString()    ?? '',
      severity:           severity,
      time:               json['time']?.toString()        ?? 'Unknown',
      distance:           json['distance']?.toString()    ?? '',
      latitude:           (json['latitude']  as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble()  ?? 0.0,
      longitude:          (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble()  ?? 0.0,
      corroborationCount: (json['corroboration_count'] as num?)?.toInt(),
    );
  }
}

final List<CrisisAlert> mockAlerts = [
  const CrisisAlert(
    id: '1',
    title: 'Flash Flood Warning',
    description: 'Severe flooding reported in downtown area. Seek higher ground immediately.',
    severity: AlertSeverity.critical,
    time: '2 mins ago',
    distance: '1.2 km away',
    latitude: 37.7749,
    longitude: -122.4194,
  ),
  const CrisisAlert(
    id: '2',
    title: 'Structural Fire',
    description: 'Multi-story building fire. Fire crews on scene. Avoid the area.',
    severity: AlertSeverity.warning,
    time: '15 mins ago',
    distance: '3.4 km away',
    latitude: 37.7849,
    longitude: -122.4094,
  ),
  const CrisisAlert(
    id: '3',
    title: 'Area Secured',
    description: 'Previous gas leak has been contained. Safe to return.',
    severity: AlertSeverity.safe,
    time: '1 hour ago',
    distance: '0.8 km away',
    latitude: 37.7649,
    longitude: -122.4294,
  ),
];
