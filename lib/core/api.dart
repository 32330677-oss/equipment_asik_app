import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'json.dart';

/// Every error coming from the API (or the network) as one type.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details]);
  final int? status;
  final String code;
  final String message;
  final Json? details;

  bool get isNetwork => code == 'NETWORK';

  @override
  String toString() => message;
}

/// A file to upload (works on web, mobile and desktop: bytes only).
class UploadFile {
  UploadFile(this.bytes, this.fileName);
  final Uint8List bytes;
  final String fileName;
}

/// The single HTTP client of the app. JWT is attached to every request.
class Api {
  Api._() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = _token;
        if (t != null && t.isNotEmpty) options.headers['Authorization'] = 'Bearer $t';
        handler.next(options);
      },
      onError: (error, handler) {
        final status = error.response?.statusCode;
        final path = error.requestOptions.path;
        final data = error.response?.data;
        final code = data is Map ? '${data['code'] ?? ''}' : '';
        if (status == 401 && !path.contains('/auth/login')) {
          onSessionEnded?.call(code == 'TOKEN_EXPIRED'
              ? 'Your session has expired. Please sign in again.'
              : 'Please sign in again.');
        } else if (status == 403 && code == 'PASSWORD_CHANGE_REQUIRED') {
          onPasswordChangeRequired?.call();
        }
        handler.next(error);
      },
    ));
  }

  static final Api I = Api._();
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'eqflow_token';

  final Dio dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    sendTimeout: const Duration(seconds: 120),
    headers: {'Accept': 'application/json'},
  ));

  String? _token;
  void Function(String message)? onSessionEnded;
  void Function()? onPasswordChangeRequired;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> loadToken() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
  }

  Future<void> setToken(String? token) async {
    _token = token;
    try {
      if (token == null) {
        await _storage.delete(key: _tokenKey);
      } else {
        await _storage.write(key: _tokenKey, value: token);
      }
    } catch (_) {/* storage not available: keep the token in memory */}
  }

  ApiException _toApiException(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final m = asJson(data);
        return ApiException(
          e.response?.statusCode,
          m.str('code', 'ERROR'),
          _withFieldErrors(m),
          m.objOrNull('details'),
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.unknown) {
        return ApiException(null, 'NETWORK',
            'Cannot reach the server (${AppConfig.apiBaseUrl}). Check your connection - nothing was saved.');
      }
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        return ApiException(null, 'TIMEOUT', 'The server took too long to answer. Please try again.');
      }
      return ApiException(e.response?.statusCode, 'HTTP_${e.response?.statusCode ?? 0}', 'Request failed (${e.response?.statusCode ?? '-'}).');
    }
    return ApiException(null, 'ERROR', e.toString());
  }

  /// "Some fields are invalid." + the first field messages.
  String _withFieldErrors(Json m) {
    final msg = m.str('message', 'Request failed.');
    final fields = m.obj('details').obj('fields');
    if (fields.isEmpty) return msg;
    final parts = fields.entries.take(3).map((e) => '${e.key.replaceAll('_', ' ')} ${e.value}');
    return '$msg ${parts.join('; ')}.';
  }

  Future<Json> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return asJson(r.data);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Full envelope { status, data, meta, message, warnings }.
  Future<Json> request(String method, String path, {Object? body, Map<String, dynamic>? query}) {
    final q = query == null ? null : (Map<String, dynamic>.from(query)..removeWhere((k, v) => v == null || v == ''));
    return _send(() => dio.request<dynamic>(path, data: body, queryParameters: q, options: Options(method: method)));
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => (await request('GET', path, query: query))['data'];
  Future<dynamic> post(String path, [Object? body]) async => (await request('POST', path, body: body ?? <String, dynamic>{}))['data'];
  Future<dynamic> put(String path, [Object? body]) async => (await request('PUT', path, body: body ?? <String, dynamic>{}))['data'];
  Future<dynamic> patch(String path, [Object? body]) async => (await request('PATCH', path, body: body ?? <String, dynamic>{}))['data'];
  Future<dynamic> delete(String path) async => (await request('DELETE', path))['data'];

  Future<List<Json>> getList(String path, {Map<String, dynamic>? query}) async => asJsonList(await get(path, query: query));
  Future<Json> getObj(String path, {Map<String, dynamic>? query}) async => asJson(await get(path, query: query));

  /// Binary download (PDF / Excel / images).
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    try {
      final q = query == null ? null : (Map<String, dynamic>.from(query)..removeWhere((k, v) => v == null || v == ''));
      final r = await dio.get<List<int>>(path,
          queryParameters: q,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)));
      return Uint8List.fromList(r.data ?? <int>[]);
    } on DioException catch (e) {
      // error bodies of byte requests are bytes: decode them to show the server message
      final raw = e.response?.data;
      if (raw is List<int>) {
        try {
          final text = String.fromCharCodes(raw);
          final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
          final c = RegExp(r'"code"\s*:\s*"([^"]+)"').firstMatch(text);
          if (m != null) throw ApiException(e.response?.statusCode, c?.group(1) ?? 'ERROR', m.group(1)!);
        } on ApiException {
          rethrow;
        } catch (_) {}
      }
      throw _toApiException(e);
    }
  }

  /// Multipart upload. [fileField] is 'file' (single) or 'files' (several).
  Future<dynamic> upload(String path, List<UploadFile> files, {String fileField = 'file', Map<String, dynamic>? fields}) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry(fileField, MultipartFile.fromBytes(f.bytes, filename: f.fileName)));
    }
    fields?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) form.fields.add(MapEntry(k, '$v'));
    });
    final res = await _send(() => dio.post<dynamic>(path, data: form));
    return res['data'];
  }
}
