import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// A Dio interceptor that captures network events and sends them to PostHog.
class PostHogDioInterceptor extends Interceptor {
  final Posthog _posthog = Posthog();
  final bool attachPayloads;

  static const int _oneMbInBytes = 1024 * 1024;

  PostHogDioInterceptor({
    this.attachPayloads = false,
  });

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    super.onResponse(response, handler);

    final isSessionReplayActive =
        await _posthog.isSessionReplayActive();
    if (isSessionReplayActive) {
      await _captureNetworkEvent(
        response: response,
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    super.onError(err, handler);

    final isSessionReplayActive =
        await _posthog.isSessionReplayActive();
    if (isSessionReplayActive) {
      final Response<dynamic>? response = err.response;
      if (response != null) {
        await _captureNetworkEvent(response: response);
      }
    }
  }

  Future<void> _captureNetworkEvent({
    required Response<dynamic> response,
  }) async {
    final String url = response.requestOptions.uri.toString();
    final String method = response.requestOptions.method;
    final int statusCode = response.statusCode ?? 0;
    final [
      (Object? publishableRequest, int requestSizeLimit),
      (Object? publishableResponse, int responseSizeLimit),
    ] = await Future.wait([
      if (attachPayloads)
        _tryTransformDataToPublishableObject(
          data: response.requestOptions.data,
        ).then(
          (value) async {
            final sizeLimit = await _calculateSizeLimit(
              data: response.requestOptions.data,
              header: response.requestOptions.headers,
            );
            return (
              value,
              sizeLimit,
            );
          },
        ),
      if (attachPayloads)
        _tryTransformDataToPublishableObject(
          data: response.data,
        ).then(
          (value) async {
            final sizeLimit = await _calculateSizeLimit(
              data: response.data,
              header: response.headers.map,
            );
            return (
              value,
              sizeLimit,
            );
          },
        ),
    ]);

    final Map<String, Object> snapshotData = <String, Object>{
      'type': 6,
      'data': <String, Object>{
        'plugin': 'rrweb/network@1',
        'payload': <String, Object>{
          'url': url,
          'method': method,
          'status_code': statusCode,
          if (requestSizeLimit + responseSizeLimit <= _oneMbInBytes) ...{
            if (publishableRequest != null) 'request': publishableRequest,
            if (publishableResponse != null) 'response': publishableResponse,
          }
        },
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    Posthog().capture(
      eventName: r'$snapshot',
      properties: <String, Object>{
        r'$snapshot_source': 'mobile',
        r'$snapshot_data': snapshotData,
      },
    );
  }

  Future<int> _calculateSizeLimit({
    required dynamic data,
    required Map<String, dynamic> header,
  }) async {
    final contentLengthHeader = header['content-length'];
    final contentLength = _deriveContentLength(contentLengthHeader);
    if (contentLength != null) {
      return contentLength;
    }

    if (data == null) {
      return 0;
    }

    if (data is bool) {
      return 4;
    }

    if (data is num) {
      return 8;
    }

    try {
      final encodedData =
          await compute((data) => utf8.encode(jsonEncode(data)), data);
      return encodedData.length;
    } catch (e) {
      // Since we couldn't serialize the data, assume it exceeds the limit.
      return _oneMbInBytes + 1;
    }
  }

  int? _deriveContentLength(dynamic contentLengthHeader) {
    if (contentLengthHeader == null) {
      return null;
    }

    if (contentLengthHeader is Iterable<String>) {
      return int.tryParse(contentLengthHeader.first);
    }

    return int.tryParse(contentLengthHeader.toString());
  }

  Future<Object?> _tryTransformDataToPublishableObject(
      {required dynamic data}) async {
    if (data == null) {
      return null;
    }

    if (data is Map ||
        data is String ||
        data is num ||
        data is bool ||
        data is Iterable) {
      return data;
    }

    if (data is FormData) {
      return <String, List<MapEntry<String, String>>>{
        'fields': data.fields,
        'files': data.files
            .map(
              (MapEntry<String, MultipartFile> e) => MapEntry<String, String>(
                e.key,
                e.value.filename ?? 'unknown',
              ),
            )
            .toList(growable: false),
      };
    }

    try {
      // Use compute here to offload JSON serialization to a separate isolate, this is to avoid jank on the main thread for large payloads.
      final json = await compute((data) => jsonDecode(jsonEncode(data)), data);
      return json;
    } catch (e) {
      return '[unserializable data]';
    }
  }
}
