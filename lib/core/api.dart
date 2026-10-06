import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'fmt.dart';
import 'json.dart';

/// Every error coming from the API (or the network) as one type.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details]);
  final int? status;
  final String code;
  final String message;
  final Json? details;

  /// No answer from the server (no internet, server down, timeout): nothing was saved, the user may retry.
  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';

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
      onResponse: (response, handler) {
        Fmt.syncServerNow(response.headers.value('x-business-now'));
        handler.next(response);
      },
      onError: (error, handler) {
        Fmt.syncServerNow(error.response?.headers.value('x-business-now'));
        final status = error.response?.statusCode;
        final path = error.requestOptions.path;
        final data = error.response?.data;
        final code = data is Map ? '${data['code'] ?? ''}' : '';
        if (status == 401 && !path.contains('/auth/login')) {
          onSessionEnded?.call(code == 'TOKEN_EXPIRED'
              ? 'Your session has expired. Please sign in again.'
              : code == 'TOKEN_REVOKED'
                  ? 'Your password was changed. Please sign in again.'
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
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.unknown:
          return ApiException(null, 'NETWORK', 'No connection to the server. Check the internet (Wi-Fi or mobile data) and try again. Nothing was saved.');
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return ApiException(null, 'TIMEOUT', 'The connection is slow and the server did not answer in time. Try again in a moment.');
        default:
          break;
      }
      return ApiException(e.response?.statusCode, 'HTTP_${e.response?.statusCode ?? 0}', _httpMessage(e.response?.statusCode, e.response?.headers.value('x-request-id')));
    }
    return ApiException(null, 'ERROR', 'Something went wrong. Please try again.');
  }

  /// Clear words for errors that come without a message from the server.
  static String _httpMessage(int? status, String? requestId) {
    final ref = requestId == null ? '' : ' (reference: ${requestId.length > 8 ? requestId.substring(0, 8) : requestId})';
    switch (status) {
      case 400: return 'Some information is missing or wrong. Check the form and try again.';
      case 401: return 'Please sign in again.';
      case 403: return 'Your account is not allowed to do this.';
      case 404: return 'This record was not found. It may have been deleted. Refresh the page.';
      case 409: return 'This was changed by someone else meanwhile. Refresh and try again.';
      case 413: return 'The file is too large. Use a smaller photo or PDF.';
      case 415: return 'This file type is not accepted. Use a PDF, JPG or PNG.';
      case 429: return 'Too many attempts. Wait a minute and try again.';
      case 502: case 503: case 504: return 'The server is restarting or busy. Try again in a minute.';
      default: return 'Something went wrong on the server. Try again; if it happens again, tell the administrator$ref.';
    }
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
  Future<dynamic> delete(String path, [Object? body]) async => (await request('DELETE', path, body: body))['data'];

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
          // UTF-8 (Arabic names and messages stay readable), then the normal JSON error envelope
          final body = jsonDecode(utf8.decode(raw, allowMalformed: true));
          if (body is Map) {
            final m = asJson(body);
            throw ApiException(e.response?.statusCode, m.str('code', 'ERROR'), _withFieldErrors(m), m.objOrNull('details'));
          }
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
