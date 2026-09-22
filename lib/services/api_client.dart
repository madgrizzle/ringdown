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
    required this.refreshToken,
    required this.baseUrl,
    required this.onTokens,
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
        onError: (e, handler) async {
          final skip = e.requestOptions.extra['skipAuth'] == true ||
              e.requestOptions.extra['skipRefresh'] == true;
          if (e.response?.statusCode == 401 && !skip) {
            try {
              await _refreshSession();
              final req = e.requestOptions;
              req.extra['skipRefresh'] = true;
              final t = token();
              if (t != null) {
                req.headers['Authorization'] = 'Bearer $t';
              }
              final res = await _dio.fetch(req);
              handler.resolve(res);
              return;
            } catch (_) {
              onUnauthorized();
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  final Dio _dio;
  final String? Function() token;
  final String? Function() refreshToken;
  final String? Function() baseUrl;
  final Future<void> Function(String access, String refresh) onTokens;
  final void Function() onUnauthorized;

  Future<void>? _refreshing;

  Future<void> _refreshSession() async {
    if (_refreshing != null) {
      await _refreshing;
      return;
    }
    final pending = _doRefresh();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _doRefresh() async {
    final current = refreshToken();
    if (current == null || current.isEmpty || current == 'refresh-not-implemented') {
      throw ApiException('Not signed in', statusCode: 401);
    }
    final tokens = await refresh(current);
    final access = tokens.accessToken;
    final nextRefresh = tokens.refreshToken ?? current;
    await onTokens(access, nextRefresh);
  }

  static const defaultBaseUrl = 'https://api.phionalerter.com';

  Future<Map<String, dynamic>> appVersion() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/app/version',
        options: Options(extra: {'skipAuth': true, 'skipRefresh': true}),
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<({String accessToken, String? refreshToken})> login({
    required String username,
    required String password,
    String? deviceId,
    String? deviceName,
    String? platform,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'username': username,
          'password': password,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          if (deviceName != null && deviceName.isNotEmpty)
            'device_name': deviceName,
          if (platform != null && platform.isNotEmpty) 'platform': platform,
        },
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

  Future<({String accessToken, String? refreshToken})> refresh(
    String refreshToken,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true, 'skipRefresh': true}),
      );
      final data = res.data ?? const {};
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) {
        throw ApiException('Refresh did not return a token');
      }
      return (
        accessToken: access,
        refreshToken: data['refresh_token'] as String?,
      );
    } on DioException catch (e) {
      throw ApiException(_message(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> logout({
    required String refreshToken,
    String? fcmToken,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/logout',
        data: {
          'refresh_token': refreshToken,
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        },
        options: Options(extra: {'skipAuth': true, 'skipRefresh': true}),
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
