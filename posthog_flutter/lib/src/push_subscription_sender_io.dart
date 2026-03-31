import 'dart:convert';
import 'dart:io';

Future<void> sendPushSubscription({
  required String host,
  required String apiKey,
  required String distinctId,
  required String token,
  required String platform,
  required String appId,
}) async {
  final uri = Uri.parse('$host/api/push_subscriptions/');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode({
      'api_key': apiKey,
      'distinct_id': distinctId,
      'token': token,
      'platform': platform,
      'app_id': appId,
    }));
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw HttpException(
        'Push subscription request failed with status ${response.statusCode}',
        uri: uri,
      );
    }
  } finally {
    client.close();
  }
}
