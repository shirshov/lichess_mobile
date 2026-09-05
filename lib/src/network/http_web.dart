import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart'
    show
        BaseClient,
        BaseRequest,
        BaseResponse,
        Client,
        ClientException,
        Request,
        Response,
        StreamedResponse;
import 'package:http/retry.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/auth/bearer.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/log/http_log_storage.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/server_status.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _logger = Logger('HttpClient');

const _maxCacheSize = 2 * 1024 * 1024;

const kQuietRequestHeader = 'x-quiet-request';

Uri lichessUri(String unencodedPath, [Map<String, dynamic>? queryParameters]) =>
    kLichessHost.startsWith('localhost') ||
        kLichessHost.startsWith('10.') ||
        kLichessHost.startsWith('192.168.')
    ? Uri.http(kLichessHost, unencodedPath, queryParameters)
    : Uri.https(kLichessHost, unencodedPath, queryParameters);

final _lichessMainHost = lichessUri('/').host;

class HttpClientFactory {
  const HttpClientFactory({this.wrapper});

  final Client Function(Client client)? wrapper;

  Client _createClient() {
    const userAgent = 'Lichess Mobile';
    return Client();
  }

  Client call() {
    final client = _createClient();
    return wrapper?.call(client) ?? client;
  }
}

final httpClientFactoryProvider = Provider<HttpClientFactory>((Ref ref) {
  return HttpClientFactory(
    wrapper: (client) {
      return _RegisterCallbackClient(
        client,
        onRequest: (request) async {
          if (request.method == 'HEAD') return;
          final httpLogStorage = await ref.read(httpLogStorageProvider.future);
          httpLogStorage.save(
            HttpLogEntry(
              httpLogId: request.hashCode.toString(),
              requestDateTime: DateTime.now(),
              requestMethod: request.method,
              requestUrl: request.url,
            ),
          );
        },
        onResponse: (response) async {
          if (response.request != null) {
            final httpLogStorage = await ref.read(httpLogStorageProvider.future);
            httpLogStorage.updateWithResponse(
              response.request!.hashCode.toString(),
              responseCode: response.statusCode,
              responseDateTime: DateTime.now(),
            );
          }
        },
        onError: (request, error, [st]) async {
          if (request.method == 'HEAD') return;
          final httpLogStorage = await ref.read(httpLogStorageProvider.future);
          if (error is ClientException) {
            httpLogStorage.updateWithError(request.hashCode.toString(), errorMessage: error.message);
          } else {
            httpLogStorage.updateWithError(
              request.hashCode.toString(),
              errorMessage: error.toString(),
            );
          }
        },
      );
    },
  );
});

final defaultClientProvider = Provider<DefaultClient>((Ref ref) {
  final userAgent = makeUserAgent(
    ref.read(preloadedDataProvider).requireValue.packageInfo,
    ref.read(preloadedDataProvider).requireValue.deviceInfo,
    ref.read(preloadedDataProvider).requireValue.sri,
    null,
  );
  final client = DefaultClient(ref.read(httpClientFactoryProvider)(), userAgent: userAgent);
  ref.onDispose(() => client.close());
  return client;
}, name: 'DefaultHttpClientProvider');

final lichessClientProvider = Provider<LichessClient>((Ref ref) {
  final client = LichessClient(
    RetryClient(
      ref.read(httpClientFactoryProvider)(),
      retries: 1,
      delay: _defaultDelay,
      when: shouldRetryOn429,
    ),
    ref,
  );
  ref.onDispose(() => client.close());
  return client;
}, name: 'LichessHttpClientProvider');

@visibleForTesting
bool shouldRetryOn429(BaseResponse response) {
  if (response.statusCode != 429) return false;
  final request = response.request;
  final isPuzzleBatch = request != null && request.url.path.startsWith('/api/puzzle/batch/');
  return !isPuzzleBatch;
}

Duration _defaultDelay(int retryCount) =>
    const Duration(milliseconds: 900) * math.pow(1.5, retryCount);

final userAgentProvider = Provider<String>((Ref ref) {
  final authUser = ref.watch(authControllerProvider);

  return makeUserAgent(
    ref.read(preloadedDataProvider).requireValue.packageInfo,
    ref.read(preloadedDataProvider).requireValue.deviceInfo,
    ref.read(preloadedDataProvider).requireValue.sri,
    authUser?.user,
  );
});

String makeUserAgent(PackageInfo info, BaseDeviceInfo deviceInfo, String sri, LightUser? user) {
  final base = 'Lichess Mobile/${info.version} as:${user?.id ?? 'anon'} sri:$sri';

  if (deviceInfo is AndroidDeviceInfo) {
    return '$base os:Android/${deviceInfo.version.release} dev:${deviceInfo.model}';
  } else if (deviceInfo is IosDeviceInfo) {
    return '$base os:iOS/${deviceInfo.systemVersion} dev:${deviceInfo.model}';
  }

  return base;
}

class _RegisterCallbackClient extends BaseClient {
  _RegisterCallbackClient(this._inner, {this.onRequest, this.onResponse, this.onError});

  final Client _inner;

  final void Function(BaseRequest request)? onRequest;
  final void Function(BaseResponse response)? onResponse;
  final void Function(BaseRequest request, Object error, [StackTrace? stackTrace])? onError;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    try {
      onRequest?.call(request);
      final response = await _inner.send(request);
      onResponse?.call(response);
      return response;
    } catch (error, st) {
      onError?.call(request, error, st);
      rethrow;
    }
  }
}

class LichessClient implements Client {
  LichessClient(this._inner, this._ref);

  static const defaultRequestTimeout = Duration(seconds: 15);

  final Ref _ref;
  final Client _inner;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final authUser = _ref.read(authControllerProvider);

    if (authUser != null && !request.headers.containsKey('Authorization')) {
      final bearer = signBearerToken(authUser.token);
      request.headers['Authorization'] = 'Bearer $bearer';
    }
    request.headers['User-Agent'] = makeUserAgent(
      _ref.read(preloadedDataProvider).requireValue.packageInfo,
      _ref.read(preloadedDataProvider).requireValue.deviceInfo,
      _ref.read(preloadedDataProvider).requireValue.sri,
      authUser?.user,
    );

    final quiet = request.headers.remove(kQuietRequestHeader) != null;

    _logger.log(
      quiet ? Level.FINEST : Level.INFO,
      '${request.method} ${request.url} ${request.headers['User-Agent']}',
    );

    try {
      final response = await _inner.send(request).timeout(defaultRequestTimeout);

      _logIfError(response, quiet: quiet);

      if (_ref.mounted && request.url.host == _lichessMainHost) {
        _ref.read(serverStatusProvider.notifier).handleHttpResponse(response.statusCode);
      }

      if (response.statusCode == 401 && authUser != null) {
        _ref.read(authControllerProvider.notifier).checkToken();
      }

      return response;
    } catch (e, st) {
      _logger.log(quiet ? Level.FINEST : Level.WARNING, 'Request to ${request.url} failed:', e, st);
      rethrow;
    }
  }

  void _logIfError(BaseResponse response, {required bool quiet}) {
    if (response.request != null && response.statusCode >= 400) {
      final request = response.request!;
      final method = request.method;
      final url = request.url;
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        '$method $url responded with status ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }

  @override
  void close() {
    _inner.close();
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) async {
    final request = Request(
      method,
      url.host.isNotEmpty ? url : lichessUri(url.path, url.hasQuery ? url.queryParameters : null),
    );

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return Response.fromStream(await send(request));
  }
}

class DefaultClient implements Client {
  DefaultClient(this._inner, {required this._userAgent});

  final Client _inner;
  final String _userAgent;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    request.headers['User-Agent'] = _userAgent;

    final quiet = request.headers.remove(kQuietRequestHeader) != null;

    _logger.log(
      quiet ? Level.FINEST : Level.INFO,
      '${request.method} ${request.url} ${request.headers['User-Agent']}',
    );

    try {
      final response = await _inner.send(request);

      _logIfError(response, quiet: quiet);

      return response;
    } catch (e, st) {
      _logger.log(quiet ? Level.FINEST : Level.WARNING, 'Request to ${request.url} failed:', e, st);
      rethrow;
    }
  }

  void _logIfError(BaseResponse response, {required bool quiet}) {
    if (response.request != null && response.statusCode >= 400) {
      final request = response.request!;
      final method = request.method;
      final url = request.url;
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        '$method $url responded with status ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }

  @override
  void close() {
    _inner.close();
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) async {
    final request = Request(method, url);

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return Response.fromStream(await send(request));
  }
}

class ServerException extends ClientException {
  final int statusCode;
  final Map<String, dynamic>? jsonError;

  ServerException(this.statusCode, super.message, Uri super.url, this.jsonError);
}

void _checkResponseSuccess(Uri url, Response response) {
  if (response.statusCode < 400) return;
  var message = 'Request to $url failed with status ${response.statusCode}';
  Map<String, dynamic>? jsonError;
  if (response.body.isNotEmpty) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        jsonError = json;
        if (json.containsKey('error')) {
          message = '$message: ${json['error']}';
        }
      }
    } catch (_) {
      message = '$message: ${response.body}';
    }
  }
  throw ServerException(response.statusCode, message, url, jsonError);
}

final jsonUtf8Decoder = const Utf8Decoder().fuse(const JsonDecoder());

extension ClientExtension on Client {
  Future<String> postRead(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  Future<Response> readResponse(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response;
  }

  Future<String> deleteRead(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await delete(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  Future<T> readJson<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      _logger.severe('Could not read JSON object as $T: expected an object.');
      throw ClientException('Could not read JSON object as $T: expected an object.', url);
    }
    try {
      return mapper(json);
    } catch (e, st) {
      _logger.severe('Could not read JSON object as $T:', e, st);
      throw ClientException('Could not read JSON object as $T: $e\n$st', url);
    }
  }

  Future<IList<T>> readJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    required T? Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! List<dynamic>) {
      _logger.severe('Could not read JSON object as List: expected a list.');
      throw ClientException('Could not read JSON object as List: expected a list.', url);
    }

    final List<T> list = [];
    for (final e in json) {
      if (e is! Map<String, dynamic>) {
        _logger.severe('Could not read JSON object as $T: expected an object.');
        throw ClientException('Could not read JSON object as $T: expected an object.', url);
      }
      try {
        final mapped = mapper(e);
        if (mapped != null) {
          list.add(mapped);
        }
      } catch (e, st) {
        _logger.severe('Could not read JSON object as $T:', e, st);
        throw ClientException('Could not read JSON object as $T: $e', url);
      }
    }
    return IList(list);
  }

  Future<IList<T>> readNdJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return _readNdJsonList(response, mapper);
  }

  Future<Stream<T>> readNdJsonStream<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final request = Request('GET', url);
    if (headers != null) request.headers.addAll(headers);
    final response = await send(request);
    if (response.statusCode >= 400) {
      var message = 'Request to $url failed with status ${response.statusCode}';
      if (response.reasonPhrase != null) {
        message = '$message: ${response.reasonPhrase}';
      }
      throw ServerException(response.statusCode, '$message.', url, null);
    }
    try {
      return response.stream.map(utf8.decode).where((e) => e.isNotEmpty && e != '\n').map((e) {
        final json = jsonDecode(e) as Map<String, dynamic>;
        return mapper(json);
      });
    } catch (e, st) {
      _logger.severe('Could not read nd-json object as $T.', e, st);
      throw ClientException('Could not read nd-json object as $T: $e', url);
    }
  }

  Future<T> postReadJson<T>(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      _logger.severe('Could not read json object as $T: expected an object.');
      throw ClientException('Could not read json object as $T: expected an object.', url);
    }
    try {
      return mapper(json);
    } catch (e, st) {
      _logger.severe('Could not read json as $T:', e, st);
      throw ClientException('Could not read json as $T: $e\n$st', url);
    }
  }

  Future<IList<T>> postReadNdJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return _readNdJsonList(response, mapper);
  }

  IList<T> _readNdJsonList<T>(Response response, T Function(Map<String, dynamic>) mapper) {
    try {
      return IList(
        LineSplitter.split(
          utf8.decode(response.bodyBytes),
        ).where((e) => e.isNotEmpty && e != '\n').map((e) {
          final json = jsonDecode(e) as Map<String, dynamic>;
          return mapper(json);
        }),
      );
    } catch (e, st) {
      _logger.severe('Could not read nd-json objects as List<$T>.', e, st);
      throw ClientException(
        'Could not read nd-json objects as List<$T>: $e',
        response.request?.url,
      );
    }
  }
}

extension ClientRefExtension on Ref {
  Future<T> withClient<T>(Future<T> Function(LichessClient) fn) async {
    final client = read(lichessClientProvider);
    return await fn(client);
  }

  Future<U> withClientCacheFor<U>(Future<U> Function(LichessClient) fn, Duration duration) async {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    final client = read(lichessClientProvider);
    onDispose(() {
      timer.cancel();
    });
    try {
      return await fn(client);
    } on ServerException {
      rethrow;
    } on Exception {
      link.close();
      rethrow;
    }
  }

  Future<U> withAggregatorCacheFor<U>(
    Future<U> Function(LichessClient, Aggregator) fn,
    Duration duration,
  ) async {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    final client = read(lichessClientProvider);
    final aggregator = read(aggregatorProvider);
    onDispose(() {
      timer.cancel();
    });
    try {
      return await fn(client, aggregator);
    } on ServerException {
      rethrow;
    } on Exception {
      link.close();
      rethrow;
    }
  }
}
