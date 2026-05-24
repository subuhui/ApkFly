import 'dart:io';

import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/services/app_logger.dart';
import 'package:dio/dio.dart' hide ProgressCallback;

class HttpChannelClient {
  HttpChannelClient([Dio? dio])
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 2),
              sendTimeout: const Duration(minutes: 10),
              validateStatus: (status) => status != null && status < 500,
            ),
          ) {
    _installErrorLogging();
  }

  final Dio dio;

  void _installErrorLogging() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          AppLogger.instance
              .error('Dio', _formatDioError(error), error.stackTrace)
              .whenComplete(() => handler.next(error));
        },
      ),
    );
  }

  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    final response = await dio.get<Object?>(
      url,
      queryParameters: query,
      options: Options(headers: headers),
    );
    return _map(response, url);
  }

  Future<Map<String, dynamic>> postJson(
    String url, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    final response = await dio.post<Object?>(
      url,
      data: data,
      queryParameters: query,
      options: Options(headers: headers),
    );
    return _map(response, url);
  }

  Future<Map<String, dynamic>> postForm(
    String url, {
    required Map<String, dynamic> data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    final response = await dio.post<Object?>(
      url,
      data: data,
      queryParameters: query,
      options: Options(
        headers: headers,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    return _map(response, url);
  }

  Future<Map<String, dynamic>> putJson(
    String url, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    final response = await dio.put<Object?>(
      url,
      data: data,
      queryParameters: query,
      options: Options(headers: headers),
    );
    return _map(response, url);
  }

  Future<void> putFile(
    String url,
    File file, {
    Map<String, dynamic>? headers,
    required ProgressCallback progress,
  }) async {
    await dio.put<Object?>(
      url,
      data: file.openRead(),
      options: Options(
        headers: headers,
        contentType: 'application/octet-stream',
      ),
      onSendProgress: (sent, total) =>
          progress(total <= 0 ? 0 : (sent * 100 / total).round()),
    );
  }

  Future<Map<String, dynamic>> postMultipart(
    String url, {
    required File file,
    required String fileField,
    Map<String, File>? extraFiles,
    Map<String, dynamic>? fields,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    required ProgressCallback progress,
  }) async {
    final formMap = <String, Object?>{
      ...?fields,
      fileField: await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
      ),
    };
    for (final entry
        in extraFiles?.entries ?? const <MapEntry<String, File>>[]) {
      formMap[entry.key] = await MultipartFile.fromFile(
        entry.value.path,
        filename: entry.value.uri.pathSegments.last,
      );
    }
    final form = FormData.fromMap(formMap);
    final response = await dio.post<Object?>(
      url,
      data: form,
      queryParameters: query,
      options: Options(headers: headers),
      onSendProgress: (sent, total) =>
          progress(total <= 0 ? 0 : (sent * 100 / total).round()),
    );
    return _map(response, url);
  }

  Future<Map<String, dynamic>> _map(
    Response<Object?> response,
    String action,
  ) async {
    if (response.statusCode == null || response.statusCode! >= 400) {
      await AppLogger.instance.error(
        'HTTP',
        'HTTP ${response.statusCode} ${response.requestOptions.method} '
            '${_redactedUri(response.requestOptions.uri)}\n'
            'response: ${_shorten(response.data)}',
      );
      throw ApiException(
        response.statusCode ?? -1,
        action,
        response.statusMessage ?? 'HTTP error',
      );
    }
    final data = response.data;
    if (data is Map) return data.cast<String, dynamic>();
    await AppLogger.instance.info(
      'HTTP',
      '$action returned ${data.runtimeType}',
    );
    return {'data': data};
  }

  String _formatDioError(DioException error) {
    final request = error.requestOptions;
    final response = error.response;
    return [
      '${error.type.name}: ${error.message}',
      '${request.method} ${_redactedUri(request.uri)}',
      if (request.data != null) 'request: ${_shorten(request.data)}',
      if (response != null)
        'status: ${response.statusCode} ${response.statusMessage}',
      if (response?.data != null) 'response: ${_shorten(response?.data)}',
    ].join('\n');
  }

  String _redactedUri(Uri uri) {
    const secretNames = {
      'client_secret',
      'clientSecret',
      'access_secret',
      'accessSecret',
      'privateKey',
      'password',
      'SIG',
      'sign',
      'api_sign',
      'access_token',
    };
    if (uri.queryParameters.isEmpty) return uri.toString();
    final query = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      query[entry.key] = secretNames.contains(entry.key) ? '***' : entry.value;
    }
    return uri.replace(queryParameters: query).toString();
  }

  String _shorten(Object? value) {
    const max = 6000;
    final text = value.toString();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...<truncated ${text.length - max} chars>';
  }
}
