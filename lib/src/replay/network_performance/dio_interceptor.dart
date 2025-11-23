import 'package:dio/dio.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class PosthogDioInterceptor extends Interceptor {
  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    await _captureNetworkEvent(
      response: response,
    );
    super.onResponse(response, handler);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final Response<dynamic>? response = err.response;
    if (response != null) {
      await _captureNetworkEvent(response: response);
    }
    super.onError(err, handler);
  }

  Future<void> _captureNetworkEvent({
    required Response<dynamic> response,
  }) async {
    final String url = response.requestOptions.uri.toString();
    final String method = response.requestOptions.method;
    final int statusCode = response.statusCode ?? 0;
    final Object? publishableRequest = _tryTransformDataToPublishableObject(
      data: response.requestOptions.data,
    );
    final Object? publishableResponse = _tryTransformDataToPublishableObject(
      data: response.data,
    );
    final Map<String, Object> snapshotData = <String, Object>{
      'type': 6,
      'data': <String, Object>{
        'plugin': 'rrweb/network@1',
        'payload': <String, Object>{
          'url': url,
          'method': method,
          'status_code': statusCode,
          if (publishableRequest != null) 'request': publishableRequest,
          if (publishableResponse != null) 'response': publishableResponse,
        },
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await Posthog().capture(
      eventName: r'$snapshot',
      properties: <String, Object>{
        r'$snapshot_source': 'mobile',
        r'$snapshot_data': snapshotData,
      },
    );
  }

  Object? _tryTransformDataToPublishableObject({required dynamic data}) {
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

    return data.toString();
  }
}
