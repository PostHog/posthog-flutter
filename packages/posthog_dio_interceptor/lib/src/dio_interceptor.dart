import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// A Dio interceptor that captures network events and sends them to PostHog.
class PostHogDioInterceptor extends Interceptor {
  final NativeCommunicator _nativeCommunicator = NativeCommunicator();
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
        await _nativeCommunicator.isSessionReplayActive();
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
        await _nativeCommunicator.isSessionReplayActive();
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
      (Object? publishableRequest, bool requestExceededLimit),
      (Object? publishableResponse, bool responseExceededLimit),
    ] = await Future.wait([
      if (attachPayloads)
        _tryTransformDataToPublishableObject(
          data: response.requestOptions.data,
        ).then(
          (value) async {
            final hasExceededLimit = await _hasExceededSizeLimit(
              data: response.requestOptions.data,
              header: response.requestOptions.headers,
            );
            return (
              value,
              hasExceededLimit,
            );
          },
        ),
      if (attachPayloads)
        _tryTransformDataToPublishableObject(
          data: response.data,
        ).then(
          (value) async {
            final hasExceededLimit = await _hasExceededSizeLimit(
              data: response.data,
              header: response.headers.map,
            );
            return (
              value,
              hasExceededLimit,
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
          if (publishableRequest != null && !requestExceededLimit)
            'request': publishableRequest,
          if (publishableResponse != null && !responseExceededLimit)
            'response': publishableResponse,
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

  Future<bool> _hasExceededSizeLimit({
    required dynamic data,
    required Map<String, dynamic> header,
  }) async {
    final contentLengthHeader = header['content-length'];
    final contentLength =
        _deriveContentLength(contentLengthHeader);
    if (contentLength != null) {
      return contentLength > _oneMbInBytes;
    }

    if (data == null) {
      return false;
    }

    if (data is num || data is bool) {
      return false;
    }

    try {
      final encodedData =
          await compute((data) => utf8.encode(jsonEncode(data)), data);
      return encodedData.length > _oneMbInBytes;
    } catch (e) {
      return false;
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
