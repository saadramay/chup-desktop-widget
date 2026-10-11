import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

/// Endpoints — see API-CONTRACT.md. Every one of these already exists on the
/// backend; only `no-show` has never been exercised by a client before.
class Urls {
  static const login = 'user/auth/widget-login';
  static const validateToken = 'user/auth/validate-token';
  static const logout = 'user/logout';

  static const visits = 'user/visits';
  static const serving = 'user/visits/serving';

  /// `widget=1` asks the backend for called_at / started_at / limits (see
  /// design/chup-online-backend.patch); servers without it ignore the flag.
  static const widgetQuery = {'widget': '1'};

  /// The list defaults to 10 rows; Large shows nine, and the rest still count.
  static const listQuery = {'size': '50', ...widgetQuery};

  static String alert(int id) => 'user/visits/$id/alert';
  static String undoAlert(int id) => 'user/visits/$id/undo-alert';
  static String noShow(int id) => 'user/visits/$id/no-show';
  static String served(int id) => 'user/visits/$id/served';
  static String serving_(int id) => 'user/visits/$id/serving';
}

/// Base URL is supplied at build time so no environment file ships with the exe.
///
///   release builds (clinics):  https://chup.online/api/v1/   <- release default
///   debug/profile builds:      https://chup.tech/api/v1/     <- so a forgotten
///                              flag never writes to live clinics' queues
///
///   `flutter run -d windows --dart-define=BASE_URL=https://chup.tech/api/v1/`
///
/// NOTE the `v1` segment. The deployed API sits under /api/v1/ even though the
/// repo's RouteServiceProvider only shows a bare `api` prefix — without it every
/// route returns a Laravel 404 that looks exactly like a wrong path.
const String kBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: kReleaseMode
      ? 'https://chup.online/api/v1/'
      : 'https://chup.tech/api/v1/',
);

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class Api {
  Api._();
  static final Api instance = Api._();

  final _box = GetStorage();

  String? _memoryToken;

  /// When "Stay signed in on this computer" is unticked the token lives only in
  /// memory, so the next launch asks for a password again. Remembering an email
  /// and never asking for a password again are different promises.
  bool persistToken = true;

  String? get token => _memoryToken ?? _box.read<String>('token');

  set token(String? v) {
    _memoryToken = v;
    if (v == null || !persistToken) {
      // Also clears a token an earlier "stay signed in" session left on disk.
      _box.remove('token');
    } else {
      _box.write('token', v);
    }
  }

  bool get isLoggedIn => (token ?? '').isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$kBaseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    final body = r.body.isEmpty ? '{}' : r.body;

    // An expired or missing token does not produce a JSON 401 — the server
    // answers with an HTML redirect to the web login page. Without this the
    // user would see a JSON parse error instead of "Session expired".
    if (body.trimLeft().startsWith('<')) {
      throw ApiException(401, 'Session expired — please sign in again');
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiException(r.statusCode, 'Unexpected response from server');
    }
    final msg = decoded is Map && decoded['message'] != null
        ? '${decoded['message']}'
        : 'Request failed';

    if (r.statusCode >= 400) throw ApiException(r.statusCode, msg);

    // This API signals failure in the BODY, not the status code — a wrong
    // password comes back as HTTP 200 with {"error": true}. Checking only the
    // status code would let a failed login look like a success.
    if (decoded is Map && decoded['error'] == true) {
      throw ApiException(r.statusCode, msg);
    }

    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  Future<Map<String, dynamic>> get(String path,
          [Map<String, String>? query]) async =>
      _decode(await http.get(_uri(path, query), headers: _headers));

  Future<Map<String, dynamic>> put(String path,
          [Map<String, dynamic> body = const {}]) async =>
      _decode(await http.put(_uri(path),
          headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> post(String path,
          [Map<String, dynamic> body = const {}]) async =>
      _decode(await http.post(_uri(path),
          headers: _headers, body: jsonEncode(body)));

  /// The endpoint this widget is named after. Added Feb 2024 and already
  /// exercised in production by the staff tablet app.
  Future<void> login(String email, String password) async {
    final res = await post(Urls.login, {
      'email': email,
      'password': password,
    });
    final data = res['data'] is Map ? res['data'] as Map : res;
    // The field is `api_token` (a Sanctum plainTextToken). Not `token`, not
    // `access_token` — checked against the widgetLogin controller.
    final t = (data['api_token'] ?? data['token'] ?? data['access_token'])
        ?.toString();
    if (t == null || t.isEmpty) {
      throw ApiException(200, 'Login succeeded but no token was returned');
    }
    token = t;
  }

  Future<void> signOut() async {
    try {
      await post(Urls.logout);
    } catch (_) {
      // Logging out locally matters more than the server round-trip.
    }
    token = null;
  }
}
