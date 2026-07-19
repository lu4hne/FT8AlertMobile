import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ApiService {
  // Use 10.0.2.2 for Android emulator testing, or localhost / specific IP for real device
  static const String baseUrl = 'https://ft8alert.app/api/mobile';

  
  final _storage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '841290912227-gqmirotu70tusspnmc1gpebqpjir89oh.apps.googleusercontent.com',
  );
  
  String? _jwtToken;
  bool _isProfileComplete = false;

  Future<void> init() async {
    _jwtToken = await _storage.read(key: 'jwt_token');
    final profileStr = await _storage.read(key: 'profile_complete');
    _isProfileComplete = profileStr == 'true';
  }

  bool get isAuthenticated => _jwtToken != null;
  bool get isProfileComplete => _isProfileComplete;

  Future<bool> login() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('Google SignIn cancelado');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) throw Exception('No se recibió ID Token de Google');

      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _jwtToken = data['token'];
        _isProfileComplete = data['profile_complete'] ?? false;
        await _storage.write(key: 'jwt_token', value: _jwtToken);
        await _storage.write(key: 'profile_complete', value: _isProfileComplete.toString());
        return true;
      } else {
        throw Exception('Error del servidor: HTTP ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Fallo el login: $e');
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'profile_complete');
    _jwtToken = null;
    _isProfileComplete = false;
  }

  Future<Map<String, dynamic>> getMetadata() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/metadata'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'activity_types': [], 'modes': []};
    } catch (e) {
      print('Metadata error: $e');
      return {'activity_types': [], 'modes': []};
    }
  }

  Future<int?> createActivity({
    required int activityTypeId,
    required int modeId,
    required String qthLocator,
    String? activatorCallsign,
    double? freq,
    String? reference,
    String? comment,
    DateTime? startTime,
    DateTime? endTime,
    bool waitreport = true,
  }) async {
    if (_jwtToken == null) return null;

    final body = {
      'activity_type_id': activityTypeId,
      'mode_id': modeId,
      'qth_locator': qthLocator,
      if (activatorCallsign != null && activatorCallsign.isNotEmpty) 'activator_callsign': activatorCallsign,
      if (freq != null) 'freq': freq,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (startTime != null) 'start_time': startTime.toIso8601String(),
      if (endTime != null) 'end_time': endTime.toIso8601String(),
      'waitreport': waitreport,
    };
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/activities'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['activity_id'];
      }
      return null;
    } catch (e) {
      print('Create activity error: $e');
      return null;
    }
  }

  // The base URL for fetching the audio directly (handled mostly by the downloader in flutter)
  String getAudioUrl(int activityId, String type) {
    // type is 'ft8' or 'cw'
    // This points to the existing backend endpoint
    final serverUrl = baseUrl.replaceAll('/mobile', '');
    return '$serverUrl/audio/$type/$activityId';
  }
}

final apiService = ApiService();
