import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class DiscordHttpResponse {
  const DiscordHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

abstract interface class DiscordHttpTransport {
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  });

  void close();
}

final class IoDiscordHttpTransport implements DiscordHttpTransport {
  IoDiscordHttpTransport({
    HttpClient? client,
    this.requestTimeout = _defaultTimeout,
  }) : _ownsClient = client == null,
       _client = client ?? HttpClient() {
    // A connect that never completes is hung the same way a response is, and
    // only the client knows about that stage.
    if (_ownsClient) _client.connectionTimeout = requestTimeout;
  }

  static const _defaultTimeout = Duration(seconds: 30);

  /// The slowest upload that still finishes: about 256 kbit/s.
  static const _slowestUploadBytesPerSecond = 32 * 1024;

  /// One request's budget before its body: connect, response headers and body.
  /// Without it a server that accepts and never answers holds its caller
  /// forever, and a serialized caller holds every request behind it.
  final Duration requestTimeout;

  /// The whole budget of a request that sends [bodyLength] bytes. A body takes
  /// time to send in proportion to its size, so one fixed limit would fail every
  /// large upload on a slow connection.
  Duration _budgetFor(int bodyLength) =>
      requestTimeout +
      Duration(
        microseconds:
            bodyLength *
            Duration.microsecondsPerSecond ~/
            _slowestUploadBytesPerSecond,
      );

  final HttpClient _client;
  final bool _ownsClient;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) {
    HttpClientRequest? request;
    Future<DiscordHttpResponse> attempt() async {
      request = await _client.openUrl(method, uri);
      headers.forEach(request!.headers.set);
      // A fixed length rather than Dart's default chunked encoding, so the
      // body arrives whole and framed the way a browser sends it.
      request!.contentLength = body?.length ?? 0;
      if (body != null) request!.add(body);
      final response = await request!.close();
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      return DiscordHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: await utf8.decoder.bind(response).join(),
      );
    }

    final budget = _budgetFor(body?.length ?? 0);
    return attempt().timeout(
      budget,
      onTimeout: () {
        // The socket is in an unknown state: aborting releases it instead of
        // leaving a half-read connection in the client's pool.
        request?.abort();
        throw TimeoutException(
          'Discord request to ${uri.host} timed out after '
          '${budget.inSeconds}s',
          budget,
        );
      },
    );
  }

  @override
  void close() => _client.close(force: true);
}

/// One successful HTTP answer, with the parts a caller needs when the status
/// line is itself part of the protocol.
///
/// Message search is why this exists: Discord answers a query whose corpus it
/// has not finished indexing with `202 Accepted` and a `Retry-After` header,
/// which is a step of the flow rather than a failure. Neither the status nor
/// the header survives a call that hands back only the decoded body, and a
/// client that cannot tell 202 from 200 shows "no results" for a search the
/// server never ran.
final class DiscordApiResponse {
  const DiscordApiResponse({
    required this.statusCode,
    required this.headers,
    required this.payload,
  });

  final int statusCode;

  /// Header names are lower-cased by the transport, so lookups are too.
  final Map<String, String> headers;
  final Object? payload;

  /// The `Retry-After` header in whole seconds, or null when the server sent
  /// none, sent something unparseable, or asked for zero.
  ///
  /// Discord's own client reads this with `parseInt`, which takes the leading
  /// integer and ignores the rest, so `"3.5"` means three seconds and not a
  /// parse failure. A zero is treated as absent by every caller, so it is
  /// folded in here rather than at each of them.
  Duration? get retryAfter {
    final match = _leadingInteger.firstMatch(headers['retry-after'] ?? '');
    final seconds = match == null ? null : int.tryParse(match.group(0)!);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  static final _leadingInteger = RegExp(r'^\s*\d+');
}

base class DiscordApiException implements Exception {
  const DiscordApiException({
    required this.statusCode,
    required this.message,
    this.responsePayload,
  });

  final int statusCode;
  final String message;
  final Map<String, Object?>? responsePayload;

  bool get isUnauthorized => statusCode == HttpStatus.unauthorized;
  bool get isForbidden => statusCode == HttpStatus.forbidden;

  @override
  String toString() => 'Discord API $statusCode: $message';
}

/// Discord refused the request for now, and the wait is too long to sit through.
///
/// Nothing was sent and nothing will be sent later by itself. The caller decides
/// what to do, which for a message means telling the person.
final class DiscordRateLimitedException extends DiscordApiException {
  const DiscordRateLimitedException({
    required super.message,
    required this.retryAfter,
    super.responsePayload,
  }) : super(statusCode: HttpStatus.tooManyRequests);

  /// How long Discord asked to wait.
  final Duration retryAfter;
}

sealed class DiscordRestAuthorization {
  DiscordRestAuthorization._(String credential, String argumentName)
    : _credential = credential.trim() {
    if (_credential.isEmpty) {
      throw ArgumentError.value(
        credential,
        argumentName,
        'Credential cannot be empty',
      );
    }
  }

  final String _credential;

  String get _headerValue;

  @override
  String toString() => '$runtimeType(<redacted>)';
}

final class DiscordBotAuthorization extends DiscordRestAuthorization {
  DiscordBotAuthorization(String token) : super._(token, 'token');

  @override
  String get _headerValue => 'Bot $_credential';
}

final class DiscordBearerAuthorization extends DiscordRestAuthorization {
  DiscordBearerAuthorization(String accessToken)
    : super._(accessToken, 'accessToken');

  @override
  String get _headerValue => 'Bearer $_credential';
}

final class DiscordDesktopAuthorization extends DiscordRestAuthorization {
  DiscordDesktopAuthorization(String authorization)
    : super._(authorization, 'authorization');

  @override
  String get _headerValue => _credential;
}

typedef DelayFunction = Future<void> Function(Duration duration);

final class DiscordHttpExecutor {
  DiscordHttpExecutor({
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _transport = transport ?? IoDiscordHttpTransport(),
       _delay = delay ?? Future<void>.delayed,
       _baseUri = baseUri ?? Uri.parse('https://discord.com/api/v10');

  static const _maxAttempts = 3;

  /// The longest one request waits between its attempts, in total.
  ///
  /// A send holds the composer while it waits, so a wait must stay short enough
  /// that a person would still call it one send. A longer one is an error.
  ///
  /// This assumes `retry_after` means seconds in the JSON body, as Discord
  /// documents, with the `Retry-After` header as the fallback. What Discord
  /// really sends in slowmode has not been checked on a live account yet.
  static const _maxRetryWait = Duration(seconds: 10);

  /// The wait before the first repeat after a server error. It grows with each
  /// attempt.
  static const _serverErrorWait = Duration(seconds: 1);

  final DiscordHttpTransport _transport;
  final DelayFunction _delay;
  final Uri _baseUri;

  Future<Object?> execute(
    String method,
    String path, {
    Map<String, Object?>? query,
    required Map<String, String> headers,
    List<int>? body,
    bool guardedByNonce = false,
  }) async => (await send(
    method,
    path,
    query: query,
    headers: headers,
    body: body,
    guardedByNonce: guardedByNonce,
  )).payload;

  /// Like [execute], but hands back the status and headers as well.
  ///
  /// [query] takes `String` values, or `List<String>` for a parameter Discord
  /// repeats — `has=image&has=video` — which is how every list-valued search
  /// filter travels.
  ///
  /// A server error is repeated, unless it answers a POST. The server may have
  /// done the work before it failed, and a second POST could create a second
  /// thing. [guardedByNonce] marks a POST that cannot: its body carries a nonce
  /// with `enforce_nonce`, so Discord answers a repeat with the first result.
  Future<DiscordApiResponse> send(
    String method,
    String path, {
    Map<String, Object?>? query,
    required Map<String, String> headers,
    List<int>? body,
    bool guardedByNonce = false,
  }) async {
    final uri = Uri.parse(
      '${_baseUri.toString()}$path',
    ).replace(queryParameters: _queryParameters(query));
    return sendTo(
      method,
      uri,
      headers: headers,
      body: body,
      guardedByNonce: guardedByNonce,
    );
  }

  /// Like [send], for a full [uri] outside Discord's API, such as the storage
  /// URL of an upload slot.
  Future<DiscordApiResponse> sendTo(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
    bool guardedByNonce = false,
  }) async {
    final repeatsServerErrors = method != 'POST' || guardedByNonce;
    var waited = Duration.zero;
    for (var attempt = 1; ; attempt++) {
      final response = await _transport.send(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
      );
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return DiscordApiResponse(
          statusCode: status,
          headers: response.headers,
          payload: response.body.isEmpty ? null : jsonDecode(response.body),
        );
      }
      final payload = _errorPayload(response.body);
      final wait = switch (status) {
        HttpStatus.tooManyRequests => _retryAfter(payload, response.headers),
        >= 500 when repeatsServerErrors => _serverErrorWait * attempt,
        _ => null,
      };
      if (wait == null ||
          attempt == _maxAttempts ||
          waited + wait > _maxRetryWait) {
        throw _failure(status, payload, wait);
      }
      waited += wait;
      await _delay(wait);
    }
  }

  /// The body of a refusal. Proxies and load balancers answer in HTML, so a body
  /// that is not JSON is expected here and says nothing: the status is the answer.
  static Object? _errorPayload(String body) {
    try {
      return body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static DiscordApiException _failure(
    int status,
    Object? payload,
    Duration? wait,
  ) {
    final message = _errorMessage(payload);
    final details = payload is Map
        ? Map<String, Object?>.unmodifiable(payload.cast<String, Object?>())
        : null;
    if (status == HttpStatus.tooManyRequests && wait != null) {
      return DiscordRateLimitedException(
        message: message,
        retryAfter: wait,
        responsePayload: details,
      );
    }
    return DiscordApiException(
      statusCode: status,
      message: message,
      responsePayload: details,
    );
  }

  /// Renders a query map the way Discord's own client does.
  ///
  /// Three rules, all of them load-bearing:
  ///
  /// * `null` values are **deleted**, not sent as the string "null". The
  ///   renderer strips them before every request, and a literal `null` in a
  ///   query is a filter nobody asked for — `action_type=null` is not the same
  ///   request as an unfiltered audit log.
  /// * A list repeats the key, which is how `include_roles` and `user_ids`
  ///   travel.
  /// * Booleans render lowercase, and everything else through `toString`, so an
  ///   `int` limit does not have to be pre-stringified at every call site.
  static Map<String, dynamic>? _queryParameters(Map<String, Object?>? query) {
    if (query == null) return null;
    final parameters = <String, dynamic>{};
    for (final entry in query.entries) {
      final value = entry.value;
      switch (value) {
        case null:
          continue;
        case final Iterable<Object?> items:
          final rendered = [
            for (final item in items)
              if (item != null) '$item',
          ];
          if (rendered.isNotEmpty) parameters[entry.key] = rendered;
        case final bool flag:
          parameters[entry.key] = flag ? 'true' : 'false';
        default:
          parameters[entry.key] = '$value';
      }
    }
    return parameters;
  }

  static Duration _retryAfter(Object? payload, Map<String, String> headers) {
    final inBody = payload is Map ? payload['retry_after'] : null;
    // The body is more exact than the header, but a zero there must not
    // undercut a wait the header asks for.
    final seconds = inBody is num && inBody > 0
        ? inBody
        : num.tryParse(headers['retry-after'] ?? '');
    return Duration(milliseconds: ((seconds ?? 1) * 1000).ceil());
  }

  static String _errorMessage(Object? payload) {
    if (payload is Map) {
      for (final key in const ['message', 'error_description', 'error']) {
        final value = payload[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final details = <String>[];
      _collectErrorDetails(payload, '', details);
      if (details.isNotEmpty) return details.take(3).join('; ');
    }
    return 'Request failed';
  }

  static void _collectErrorDetails(
    Object? value,
    String path,
    List<String> details,
  ) {
    if (details.length >= 3) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (const {'message', 'error_description', 'error'}.contains(key)) {
          continue;
        }
        final childPath = path.isEmpty ? key : '$path.$key';
        _collectErrorDetails(entry.value, childPath, details);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _collectErrorDetails(item, path, details);
      }
      return;
    }
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      final looksLikeSecret =
          normalized.length > 32 &&
          RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(normalized);
      details.add('$path: ${looksLikeSecret ? '<redacted>' : normalized}');
      return;
    }
    if (value is num || value is bool) details.add('$path: $value');
  }

  void close() => _transport.close();
}

final class DiscordRestClient {
  DiscordRestClient({
    required this._authorization,
    Map<String, String> additionalHeaders = const {},
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _additionalHeaders = Map.unmodifiable({...additionalHeaders}),
       _executor = DiscordHttpExecutor(
         transport: transport,
         delay: delay,
         baseUri: baseUri,
       );

  static const _userAgent = 'Flucord/0.1.0 (native Flutter client)';

  final DiscordRestAuthorization _authorization;
  final Map<String, String> _additionalHeaders;
  final DiscordHttpExecutor _executor;

  /// The header Discord attributes a moderation action by in the audit log.
  static const auditLogReasonHeader = 'X-Audit-Log-Reason';

  Future<Map<String, Object?>> getObject(String path) =>
      requestObject('GET', path);

  Future<List<Map<String, Object?>>> getList(
    String path, {
    Map<String, Object?>? query,
  }) async {
    final payload = await request('GET', path, query: query);
    return _asList(payload);
  }

  Future<Map<String, Object?>> requestObject(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    String? auditLogReason,
    bool guardedByNonce = false,
  }) async {
    final payload = await request(
      method,
      path,
      query: query,
      body: body,
      auditLogReason: auditLogReason,
      guardedByNonce: guardedByNonce,
    );
    if (payload is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return payload.cast<String, Object?>();
  }

  /// Sends a bare JSON **array** body and reads an array back.
  ///
  /// The role and channel reorder routes take a top-level array, not an object
  /// wrapping one, so they cannot go through [requestObject] at all.
  Future<List<Map<String, Object?>>> requestJsonArray(
    String method,
    String path, {
    required List<Object?> body,
    String? auditLogReason,
  }) async {
    final payload = await _execute(
      method,
      path,
      encodedBody: utf8.encode(jsonEncode(body)),
      auditLogReason: auditLogReason,
    );
    return payload == null ? const [] : _asList(payload);
  }

  /// [headers] are added to this request only, such as a solved captcha.
  Future<void> requestEmpty(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    String? auditLogReason,
    Map<String, String> headers = const {},
  }) async {
    await request(
      method,
      path,
      query: query,
      body: body,
      auditLogReason: auditLogReason,
      headers: headers,
    );
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    List<int>? rawBody,
    String contentType = 'application/json',
    String? auditLogReason,
    bool guardedByNonce = false,
    Map<String, String> headers = const {},
  }) => _execute(
    method,
    path,
    query: query,
    encodedBody:
        rawBody ?? (body == null ? null : utf8.encode(jsonEncode(body))),
    contentType: contentType,
    auditLogReason: auditLogReason,
    guardedByNonce: guardedByNonce,
    headers: headers,
  );

  Future<Object?> _execute(
    String method,
    String path, {
    Map<String, Object?>? query,
    List<int>? encodedBody,
    String contentType = 'application/json',
    String? auditLogReason,
    bool guardedByNonce = false,
    Map<String, String> headers = const {},
  }) => _executor.execute(
    method,
    path,
    query: query,
    headers: {
      ..._headers(
        contentType: encodedBody == null ? null : contentType,
        auditLogReason: auditLogReason,
      ),
      ...headers,
    },
    body: encodedBody,
    guardedByNonce: guardedByNonce,
  );

  /// PUTs [bytes] to the storage [url] of an upload slot. The URL is signed,
  /// so this request carries no Discord credentials.
  Future<void> uploadTo(
    Uri url,
    List<int> bytes, {
    required String contentType,
  }) => _executor.sendTo(
    'PUT',
    url,
    headers: {HttpHeaders.contentTypeHeader: contentType},
    body: bytes,
  );

  /// A request whose status and headers the caller needs, for the routes where
  /// a non-200 success carries meaning of its own.
  Future<DiscordApiResponse> requestDetailed(
    String method,
    String path, {
    Map<String, Object?>? query,
  }) => _executor.send(method, path, query: query, headers: _headers());

  /// A request without a body carries no content type, as the desktop client
  /// sends it. Discord parses the body of a request that names JSON, and an
  /// empty one is refused as invalid JSON (code 50109) on routes such as
  /// `GET /channels/{id}/call`.
  Map<String, String> _headers({
    String? contentType,
    String? auditLogReason,
  }) => {
    HttpHeaders.acceptHeader: 'application/json',
    HttpHeaders.contentTypeHeader: ?contentType,
    HttpHeaders.userAgentHeader: _userAgent,
    ..._additionalHeaders,
    // Percent-encoded whole, the way the desktop client does it. A reason is
    // free text a moderator typed, and a raw newline or non-Latin-1 byte in
    // an HTTP header is either rejected outright or, worse, splits the
    // request — so it is encoded here rather than trusted to the socket.
    if (auditLogReason != null && auditLogReason.trim().isNotEmpty)
      auditLogReasonHeader: Uri.encodeComponent(auditLogReason.trim()),
    HttpHeaders.authorizationHeader: _authorization._headerValue,
  };

  static List<Map<String, Object?>> _asList(Object? payload) {
    if (payload is! List) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON array',
      );
    }
    return payload
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  void close() => _executor.close();

  @override
  String toString() => 'DiscordRestClient($_authorization)';
}
