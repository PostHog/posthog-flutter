/// HTTP fetch options for PostHog API requests.
class PostHogFetchOptions {
  final String method;
  final Map<String, String> headers;
  final String? body;

  const PostHogFetchOptions({
    required this.method,
    this.headers = const {},
    this.body,
  });
}

/// HTTP fetch response from PostHog API.
class PostHogFetchResponse {
  final int status;
  final String body;

  const PostHogFetchResponse({required this.status, required this.body});
}
