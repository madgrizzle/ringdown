import 'package:dio/dio.dart';

import '../models/alarm.dart';
import '../models/auth_state.dart';
import '../models/filters.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required this.token,
    required this.baseUrl,
    required this.onUnauthorized,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                headers: const {'Content-Type': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final url = baseUrl();
          if (url != null && url.isNotEmpty) {
            options.baseUrl = url;
          }
          final skipAuth = options.extra['skipAuth'] == true;
          final t = token();
          if (!skipAuth && t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
        onError: (e, handler) {
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['skipAuth'] != true) {
            onUnauthorized();
          }
          handler.next(e);
        },
      ),
    );
  }

  final Dio _dio;
  final String? Function() token;
  final String? Function() baseUrl;
  final void Function() onUnauthorized;

  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.contains('://')) url = 'https://$url';
    return url;
  }

  Future<void> checkHealth(String serverUrl) async {
    final url = normalizeBaseUrl(serverUrl);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$url/health',
        options: Options(extra: {'skipAuth': true}),
      );
      final status = res.data?['status']?.toString().toLowerCase();
      if (status != 'healthy') {
        throw ApiException('Server is not healthy');
      }
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<({String accessToken, String? refreshToken})> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = res.data ?? const {};
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) {
        throw ApiException('Login did not return a token');
      }
      return (
        accessToken: access,
        refreshToken: data['refresh_token'] as String?,
      );
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Me> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/me');
      return Me.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/devices/register',
        data: {'fcm_token': fcmToken, 'platform': platform},
      );
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<AlarmListPage> listAlarms({
    required AlarmFilters filters,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      'sort': filters.sort.apiSort,
      'order': filters.sort.apiOrder,
    };
    if (filters.hideCleared) {
      query['state'] = 'active';
    } else {
      query['state'] = 'all';
    }
    if (filters.unackedOnly) query['acked'] = false;
    if (filters.siteContains.trim().isNotEmpty) {
      query['site_id'] = filters.siteContains.trim();
    }
    if (filters.deviceContains.trim().isNotEmpty) {
      query['device'] = filters.deviceContains.trim();
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/alarms',
        queryParameters: query,
      );
      return AlarmListPage.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Alarm> getAlarm(int id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/alarms/$id');
      return Alarm.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> ack(int id) async {
    try {
      await _dio.post<Map<String, dynamic>>('/alarms/$id/ack');
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  static String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach server';
    }
    return e.message ?? 'Request failed';
  }
}
