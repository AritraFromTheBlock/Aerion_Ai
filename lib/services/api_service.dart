import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

// =============================================================
// AERION AI API SERVICE
// Wires Flutter screens to the real backend.
// Anonymous endpoints use X-Api-Key header.
// Authenticated endpoints (future) use Firebase JWT Bearer token.
// =============================================================

class ApiService {
  // ── CONFIG ────────────────────────────────────────────────
  static const String baseUrl =
      'https://arion-ai-backend-kshlsswxia-el.a.run.app';
  static const String _apiKey = 'arion-flutter-dev-key-change-in-production';

  static final Map<String, String> _anonHeaders = {
    'Content-Type': 'application/json',
    'X-Api-Key':    _apiKey,
    'User-Agent':   'AERION-AI-Mobile',
  };

  // ── SAFE JSON DECODE ──────────────────────────────────────
  // Central helper that prevents FormatException crashes when
  // the backend returns non-JSON (HTML error pages, 502/503, etc.)
  // ──────────────────────────────────────────────────────────
  static Map<String, dynamic> _safeJsonDecode(http.Response response) {
    final body = response.body;

    // Empty body guard
    if (body.isEmpty) {
      throw ApiException(
        'Server returned empty response (HTTP ${response.statusCode})',
      );
    }

    // HTML response guard — the server returned an error page, not JSON
    if (body.trimLeft().startsWith('<') || body.trimLeft().startsWith('<!')) {
      throw ApiException(
        'Server unavailable (HTTP ${response.statusCode}). Please try again.',
      );
    }

    // Attempt JSON parse
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      // Response was valid JSON but not a Map (e.g. a plain string or array)
      return {'data': decoded};
    } on FormatException {
      // Body is non-empty, non-HTML, but still not valid JSON
      throw ApiException(
        'Unexpected server response (HTTP ${response.statusCode})',
      );
    }
  }

  // ── Convenience: decode + status check in one call ────────
  static Map<String, dynamic> _expectSuccess(
    http.Response response, {
    List<int> okCodes = const [200, 201],
    String fallbackError = 'Request failed',
  }) {
    final data = _safeJsonDecode(response);
    if (okCodes.contains(response.statusCode)) {
      return data;
    }
    throw ApiException(
      data['error']?.toString() ?? '$fallbackError (HTTP ${response.statusCode})',
    );
  }

  // ── DEVICE ID ─────────────────────────────────────────────
  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _cachedDeviceId = android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        _cachedDeviceId = ios.identifierForVendor ?? 'ios-unknown';
      } else {
        _cachedDeviceId = 'unknown-device';
      }
    } catch (_) {
      _cachedDeviceId = 'unknown-device';
    }
    return _cachedDeviceId!;
  }

  // =============================================================
  // POST /incidents/quick-report
  // Used by ReportScreen — submits text report with AI triage.
  // Returns the mapped CrisisAlert-compatible incident.
  // =============================================================
  static Future<Map<String, dynamic>> quickReport({
    required String message,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final deviceId = await getDeviceId();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/incidents/quick-report'),
            headers: _anonHeaders,
            body: jsonEncode({
              'message':  message,
              'lat':      lat,
              'lng':      lng,
              if (address != null) 'address': address,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 30));

      return _expectSuccess(response, fallbackError: 'Failed to submit report');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not submit report. Check your connection.');
    }
  }

  // =============================================================
  // POST /sos/quick
  // Anonymous SOS panic button — sends with GPS + optional info.
  // =============================================================
  static Future<Map<String, dynamic>> quickSos({
    required double lat,
    required double lng,
    String message = 'EMERGENCY SOS — User needs immediate help!',
    String? name,
    String? phone,
    double? accuracy,
    double? altitude,
  }) async {
    final deviceId = await getDeviceId();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/sos/quick'),
            headers: _anonHeaders,
            body: jsonEncode({
              'lat':      lat,
              'lng':      lng,
              'message':  message,
              'deviceId': deviceId,
              if (name != null && name.isNotEmpty)   'name':     name,
              if (phone != null && phone.isNotEmpty) 'phone':    phone,
              if (accuracy != null)                  'accuracy': accuracy,
              if (altitude != null)                  'altitude': altitude,
            }),
          )
          .timeout(const Duration(seconds: 20));

      return _expectSuccess(
        response,
        okCodes: [201],
        fallbackError: 'Failed to send SOS. Please call 112 immediately!',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: SOS could not be sent. Please call 112!');
    }
  }

  // =============================================================
  // POST /sos/quick/update
  // Push live location updates for an active SOS.
  // =============================================================
  static Future<void> updateSosLocation({
    required String sosId,
    required double lat,
    required double lng,
    double? accuracy,
  }) async {
    final deviceId = await getDeviceId();
    try {
      await http
          .post(
            Uri.parse('$baseUrl/sos/quick/update'),
            headers: _anonHeaders,
            body: jsonEncode({
              'sosId':    sosId,
              'lat':      lat,
              'lng':      lng,
              'deviceId': deviceId,
              if (accuracy != null) 'accuracy': accuracy,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Location updates are best-effort — don't surface errors
    }
  }

  // =============================================================
  // POST /sos/quick/cancel
  // Cancel an active anonymous SOS.
  // =============================================================
  static Future<void> cancelSos(String sosId) async {
    final deviceId = await getDeviceId();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/sos/quick/cancel'),
            headers: _anonHeaders,
            body: jsonEncode({
              'sosId':    sosId,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final data = _safeJsonDecode(response);
        throw ApiException(data['error']?.toString() ?? 'Failed to cancel SOS');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not cancel SOS. Please try again.');
    }
  }

  // =============================================================
  // GET /incidents/nearby
  // Used by MainMapScreen to load real incidents onto the map.
  // Returns list of incidents with Flutter CrisisAlert fields.
  // =============================================================
  static Future<List<dynamic>> getNearbyIncidents({
    required double lat,
    required double lng,
    double radiusKm = 20,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/incidents/nearby?lat=$lat&lng=$lng&radius=$radiusKm',
            ),
          )
          .timeout(const Duration(seconds: 15));

      final data = _expectSuccess(
        response,
        fallbackError: 'Failed to fetch nearby incidents',
      );
      return (data['incidents'] as List<dynamic>?) ?? [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not load incidents.');
    }
  }

  // =============================================================
  // POST /incidents/:id/corroborate
  // Anyone can confirm an incident (crowd verification).
  // =============================================================
  static Future<Map<String, dynamic>> corroborateIncident(String id) async {
    final deviceId = await getDeviceId();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/incidents/$id/corroborate'),
            headers: _anonHeaders,
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 15));

      return _expectSuccess(response, fallbackError: 'Failed to corroborate');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not confirm incident.');
    }
  }

  // =============================================================
  // GET /analytics/heatmap
  // Returns weighted points for the map heat overlay.
  // =============================================================
  static Future<List<dynamic>> getHeatmap({
    required double lat,
    required double lng,
    double radiusKm = 20,
    int hours = 24,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/analytics/heatmap?lat=$lat&lng=$lng&radius=$radiusKm&hours=$hours',
            ),
          )
          .timeout(const Duration(seconds: 15));

      final data = _expectSuccess(
        response,
        fallbackError: 'Failed to fetch heatmap',
      );
      return (data['points'] as List<dynamic>?) ?? [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not load heatmap.');
    }
  }

  // =============================================================
  // GET /analytics/trends
  // Returns incident type and severity breakdowns for dashboard.
  // =============================================================
  static Future<Map<String, dynamic>> getAnalyticsTrends({int hours = 168}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/analytics/trends?hours=$hours'))
          .timeout(const Duration(seconds: 15));

      return _expectSuccess(response, fallbackError: 'Failed to fetch trends');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not load trends.');
    }
  }

  // =============================================================
  // GET /incidents/:id
  // Fetch full incident detail with timeline.
  // =============================================================
  static Future<Map<String, dynamic>> getIncidentDetail(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/incidents/$id'))
          .timeout(const Duration(seconds: 15));

      return _expectSuccess(response, fallbackError: 'Failed to fetch incident');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not load incident details.');
    }
  }

  // =============================================================
  // POST /incidents/:id/retriage
  // Re-run AI triage for incidents where initial triage failed.
  // Returns updated AI analysis or error.
  // =============================================================
  static Future<Map<String, dynamic>> retriageIncident(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/incidents/$id/retriage'),
            headers: _anonHeaders,
          )
          .timeout(const Duration(seconds: 30));

      return _expectSuccess(response, fallbackError: 'Failed to retriage incident');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: could not retriage incident.');
    }
  }

  // =============================================================
  // HELPER: Check if a description is the AI fallback text
  // =============================================================
  static bool isTriageFallback(String description) {
    return description.isEmpty ||
        description.contains('Automated triage unavailable') ||
        description.contains('Manual review required') ||
        description == 'Incident reported — details pending.' ||
        description == 'No details available.';
  }
}

// =============================================================
// API EXCEPTION
// =============================================================
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}
