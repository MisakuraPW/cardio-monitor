import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class CloudApiService {
  CloudApiService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  String baseUrl;

  Uri _uri(String path) {
    final sanitized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$sanitized$path');
  }

  Future<SessionRecord> createSession(SessionRecord session) async {
    final response = await _client.post(
      _uri('/api/v1/sessions'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(
        <String, dynamic>{
          'deviceId': session.deviceId,
          'sourceMode': session.sourceMode,
          'channelKeys': session.channelKeys,
          'startedAt': session.startedAt,
        },
      ),
    );
    _ensureOk(response);
    return SessionRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<UploadTask> uploadSessionData({
    required String sessionId,
    required Map<String, dynamic> summary,
    required Map<String, dynamic> excerpts,
  }) async {
    final response = await _client.post(
      _uri('/api/v1/sessions/$sessionId/uploads'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(
        <String, dynamic>{
          'summary': summary,
          'excerpts': excerpts,
        },
      ),
    );
    _ensureOk(response);
    return UploadTask.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AnalysisJob> createAnalysisJob(String sessionId) async {
    final response = await _client.post(
      _uri('/api/v1/analysis/jobs'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'sessionId': sessionId}),
    );
    _ensureOk(response);
    return AnalysisJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AnalysisJob> getAnalysisJob(String jobId) async {
    final response = await _client.get(_uri('/api/v1/analysis/jobs/$jobId'));
    _ensureOk(response);
    return AnalysisJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<MedicalReport> getReport(String sessionId) async {
    final response = await _client.get(_uri('/api/v1/reports/$sessionId'));
    _ensureOk(response);
    return MedicalReport.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  void dispose() {
    _client.close();
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(
      'Cloud API request failed: ${response.statusCode} ${response.body}',
    );
  }
}
