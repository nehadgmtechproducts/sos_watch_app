import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../common/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  String? token;

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body}) async {
    try {
      return await _send(method, path, body: body)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
          'The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw ApiException(
          'Cannot connect to the server. Check your connection and try again.');
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, dynamic>? body}) async {
    final response = await _client
        .send(http.Request(method, Uri.parse('${ApiConfig.baseUrl}$path'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token'
          })
          ..body = body == null ? '' : jsonEncode(body));
    final text = await response.stream.bytesToString();
    final json = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          (json['error'] as Map?)?['message']?.toString() ?? 'Request failed', statusCode: response.statusCode);
    }
    return json;
  }
}
