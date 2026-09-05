import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:clock/clock.dart' as clock_package;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/auth/bearer.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/web.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const kDefaultSocketRoute = '/socket/v5';

const _kDefaultConnectTimeout = Duration(seconds: 10);
const _kPingDelay = Duration(milliseconds: 2500);
const _kPingMaxLag = Duration(seconds: 9);
const _kAutoReconnectDelay = Duration(milliseconds: 3500);
const _kResendAckDelay = Duration(milliseconds: 1500);
const _kVersionGapRetryDelay = Duration(milliseconds: 200);
const _kIdleTimeout = Duration(seconds: 2);

const _kDisconnectOnBackgroundTimeout = Duration(minutes: 1);

final _logger = Logger('Socket');

const _globalSocketStreamAllowedTopics = {'n', 'message', 'challenges', 'announce'};

final _globalStreamController = StreamController<SocketEvent>.broadcast();

final socketGlobalStream = _globalStreamController.stream;

Uri lichessWSUri(String unencodedPath, [Map<String, String>? queryParameters]) =>
    kLichessWSHost.startsWith('localhost') ||
        kLichessWSHost.startsWith('10.') ||
        kLichessWSHost.startsWith('192.168.')
    ? Uri(
        scheme: 'ws',
        host: kLichessWSHost.split(':')[0],
        port: int.parse(kLichessWSHost.split(':')[1]),
        path: unencodedPath,
        queryParameters: queryParameters,
      )
    : Uri(
        scheme: 'wss',
        host: kLichessWSHost,
        path: unencodedPath,
        queryParameters: queryParameters,
      );

class SocketClient {
  SocketClient(
    this.route, {
    this.version,
    required this.channelFactory,
    required this.getSession,
    required this.packageInfo,
    required this.deviceInfo,
    required this.sri,
    this.onStreamListen,
    this.onStreamCancel,
    this.onEventGapFailure,
    this.pingDelay = _kPingDelay,
    this.pingMaxLag = _kPingMaxLag,
    this.autoReconnectDelay = _kAutoReconnectDelay,
    this.resendAckDelay = _kResendAckDelay,
  }) : assert(route.path.isNotEmpty, 'Route path must not be empty'),
       assert(pingDelay > Duration.zero, 'Ping delay must be greater than 0'),
       assert(pingMaxLag > Duration.zero, 'Ping max lag must be greater than 0'),
       assert(autoReconnectDelay > Duration.zero, 'Auto reconnect delay must be greater than 0'),
       assert(resendAckDelay > Duration.zero, 'Resend ack delay must be greater than 0');

  final WebSocketChannelFactory channelFactory;

  final AuthUser? Function() getSession;

  final PackageInfo packageInfo;

  final BaseDeviceInfo deviceInfo;

  final String sri;

  final Uri route;

  int? version;

  final Duration pingDelay;

  final Duration pingMaxLag;

  final Duration autoReconnectDelay;

  final Duration resendAckDelay;

  final VoidCallback? onStreamListen;

  final VoidCallback? onStreamCancel;

  final VoidCallback? onEventGapFailure;

  late final StreamController<SocketEvent> _streamController =
      StreamController<SocketEvent>.broadcast(onListen: onStreamListen, onCancel: onStreamCancel);

  late final StreamController<void> _socketOpenController = StreamController<void>.broadcast();

  Completer<void> _firstConnection = Completer<void>();

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _ackResendTimer;
  Timer? _versionGapRetryTimer;
  int _pongCount = 0;
  DateTime _lastPing = clock_package.clock.now();

  final _averageLag = ValueNotifier(Duration.zero);

  StreamSubscription<SocketEvent>? _socketStreamSubscription;

  final List<(DateTime, int, Map<String, dynamic>)> _acks = [];

  final List<(int?, String)> _resendWhenOpen = [];

  int nbConnectionAttempts = 0;

  int nbConnectionSuccess = 0;

  int _ackId = 1;

  WebSocketChannel? _channel;

  int _connectionEpoch = 0;

  StreamSink<String>? get _sink => _channel?.sink;

  Stream<SocketEvent> get stream => _streamController.stream;

  Stream<void> get connectedStream => _socketOpenController.stream;

  ValueListenable<Duration> get averageLag => _averageLag;

  bool get isActive => nbConnectionAttempts > 0;

  bool get isConnected => averageLag.value != Duration.zero;

  bool isDisposed = false;

  Future<void> get firstConnection => _firstConnection.future;

  Future<void> connect() async {
    if (isDisposed) {
      throw StateError('SocketClient is disposed, cannot connect.');
    }

    _disconnect();
    final epoch = _connectionEpoch;
    _pongCount = 0;
    _reconnectTimer?.cancel();
    _ackResendTimer?.cancel();
    _ackResendTimer = Timer.periodic(resendAckDelay, (_) => _resendAcks());

    final authUser = getSession();

    final queryParameters = Map<String, String>.from(route.queryParameters);
    if (version != null) {
      queryParameters['v'] = version.toString();
    }
    final uri = lichessWSUri(route.path, queryParameters.isNotEmpty ? queryParameters : null);

    final Map<String, String> headers = authUser != null
        ? {'Authorization': 'Bearer ${signBearerToken(authUser.token)}'}
        : {};

    _logger.info('Creating WebSocket connection to $route');

    nbConnectionAttempts++;

    try {
      final channel = await channelFactory.create(
        uri.toString(),
        headers: headers,
        timeout: _kDefaultConnectTimeout,
      );

      if (isDisposed || epoch != _connectionEpoch) {
        _logger.fine('Discarding stale WebSocket connection to $route.');
        if (!identical(channel, _channel)) {
          unawaited(channel.sink.close());
        }
        return;
      }

      _channel = channel;

      _socketStreamSubscription?.cancel();
      _socketStreamSubscription = channel.stream
          .map((raw) {
            if (raw == '0') {
              return SocketEvent.pong;
            }
            final event = SocketEvent.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
            return event;
          })
          .listen(_handleEvent);

      _logger.fine('WebSocket connection to $route established.');

      nbConnectionSuccess++;

      if (nbConnectionSuccess == 1) {
        _firstConnection.complete();
      }

      _averageLag.value = Duration.zero;
      _sendPing();
      _schedulePing(pingDelay);

      if (_socketOpenController.hasListener) {
        _socketOpenController.add(null);
      }

      if (_resendWhenOpen.isNotEmpty) {
        final pending = List<(int?, String)>.of(_resendWhenOpen);
        _resendWhenOpen.clear();
        final now = clock_package.clock.now();
        for (final (ackId, message) in pending) {
          _sink?.add(message);
          if (ackId != null) {
            final index = _acks.indexWhere((rec) => rec.$2 == ackId);
            if (index != -1) {
              _acks[index] = (now, _acks[index].$2, _acks[index].$3);
            }
          }
        }
      }

      _resendAcks();
    } catch (e, st) {
      if (isDisposed || epoch != _connectionEpoch) {
        _logger.fine('Stale WebSocket connection to $route failed:', e);
        return;
      }
      _logger.severe('WebSocket connection failed:', e, st);
      _averageLag.value = Duration.zero;
      _scheduleReconnect(autoReconnectDelay);
    }
  }

  void send(String topic, Object? data, {bool? ackable, bool? withLag}) {
    Map<String, Object> message;
    int? ackId;

    if (ackable == true) {
      ackId = _ackId++;
      message = {
        't': topic,
        'd': {
          if (data != null && data is Map<String, Object>) ...data,
          'a': ackId,
          if (withLag == true) 'l': _averageLag.value.inMilliseconds,
        },
      };
      _acks.add((clock_package.clock.now(), ackId, message));
    } else {
      message = {
        't': topic,
        if (data != null && data is Map<String, Object>)
          'd': {...data, if (withLag == true) 'l': _averageLag.value.inMilliseconds}
        else if (data != null)
          'd': data,
      };
    }

    final encoded = jsonEncode(message);
    final sink = _sink;
    if (sink != null) {
      sink.add(encoded);
    } else {
      _resendWhenOpen.add((ackId, encoded));
    }
  }

  void dispose() {
    _socketStreamSubscription?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _ackResendTimer?.cancel();
    _versionGapRetryTimer?.cancel();
    _streamController.close();
    _averageLag.dispose();
    isDisposed = true;
    _disconnect();
  }

  Future<void> close() {
    nbConnectionAttempts = 0;
    nbConnectionSuccess = 0;
    _firstConnection = Completer<void>();
    return _disconnect();
  }

  Future<void> _disconnect() {
    _connectionEpoch++;
    _socketStreamSubscription?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _ackResendTimer?.cancel();

    final future =
        _sink
            ?.close()
            .then((_) {
              _logger.fine('WebSocket connection to $route was properly closed.');
              if (isDisposed) {
                return;
              }
              _averageLag.value = Duration.zero;
            })
            .catchError((Object? error) {
              _logger.warning('WebSocket connection to $route could not be closed:', error);
              if (isDisposed) {
                return;
              }
              _averageLag.value = Duration.zero;
            }) ??
        Future.value();
    _channel = null;

    return future;
  }

  void _handleEvent(SocketEvent event, [int retries = 10]) {
    if (event.version != null && version != null) {
      if (event.version! <= version!) {
        _logger.fine('Already has event ${event.version}');
        return;
      }
      if (event.version! > version! + 1) {
        if (retries > 0) {
          _logger.warning(
            'Version gap, retrying... event: ${event.version}, socket: $version, retries: $retries',
          );
          _versionGapRetryTimer?.cancel();
          _versionGapRetryTimer = Timer(
            _kVersionGapRetryDelay,
            () => _handleEvent(event, retries - 1),
          );
        } else {
          onEventGapFailure?.call();
          _logger.severe(
            'Cannot solve event gap: version incoming ${event.version} vs current $version',
          );
          LichessBinding.instance.firebaseCrashlytics.recordError(
            'Cannot solve event gap: version incoming ${event.version} vs current $version',
            null,
            information: ['socket.route: $route', 'event.topic: ${event.topic}'],
          );
        }
        return;
      }
      version = event.version;
    }

    switch (event.topic) {
      case '_pong':
        _handlePong(pingDelay);
      case 'n':
        _handlePong(pingDelay);
        continue addToStream;
      case 'ack':
        _onServerAck(event);
      case 'batch':
        _handleBatch(event);
      addToStream:
      case _:
        if (_streamController.hasListener) {
          _streamController.add(event);
        }
        if (_globalStreamController.hasListener &&
            _globalSocketStreamAllowedTopics.contains(event.topic)) {
          _globalStreamController.add(event);
        }
    }
  }

  void _schedulePing(Duration delay) {
    _pingTimer?.cancel();
    _pingTimer = Timer(delay, _sendPing);
  }

  void _sendPing() {
    _sink?.add(
      _pongCount % 10 == 2
          ? jsonEncode({'t': 'p', 'l': (_averageLag.value.inMilliseconds * 0.1).round()})
          : 'p',
    );
    _lastPing = clock_package.clock.now();
    _scheduleReconnect(pingMaxLag);
  }

  void _handlePong(Duration pingDelay) {
    if (isDisposed) return;

    _reconnectTimer?.cancel();
    if (_pongCount == 0) {
      _logger.fine('Ping/pong protocol for $route established.');
    }
    _schedulePing(pingDelay);
    _pongCount++;
    final currentLag = Duration(
      milliseconds: math.min(clock_package.clock.now().difference(_lastPing).inMilliseconds, 10000),
    );

    final mix = _pongCount > 4 ? 0.1 : 1 / _pongCount;
    _averageLag.value += (currentLag - _averageLag.value) * mix;
  }

  void _scheduleReconnect(Duration delay) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!isDisposed) {
        _logger.fine('Reconnecting WebSocket.');
        _averageLag.value = Duration.zero;
        connect();
      } else {
        _logger.warning('Scheduled reconnect after $delay failed since client is disposed.');
      }
    });
  }

  void _onServerAck(SocketEvent event) {
    if (event.data is! int) {
      return;
    }
    _acks.removeWhere((rec) => rec.$2 == event.data);
  }

  void _resendAcks() {
    final resendCutoff = clock_package.clock.now().subtract(const Duration(milliseconds: 2500));
    for (final (at, _, ack) in _acks) {
      if (at.isBefore(resendCutoff)) {
        _sink?.add(jsonEncode(ack));
      }
    }
  }

  void _handleBatch(SocketEvent batchEvent) {
    final jsonEventList = batchEvent.data as List<dynamic>;

    for (final jsonEvent in jsonEventList) {
      final event = SocketEvent.fromJson(jsonEvent as Map<String, dynamic>);

      _streamController.add(event);
    }
  }
}

class SocketPool {
  SocketPool(this._ref, {this.idleTimeout = _kIdleTimeout}) {
    final client = SocketClient(
      _currentRoute,
      sri: _ref.read(preloadedDataProvider).requireValue.sri,
      channelFactory: _ref.read(webSocketChannelFactoryProvider),
      getSession: () => _ref.read(authControllerProvider),
      packageInfo: _ref.read(preloadedDataProvider).requireValue.packageInfo,
      deviceInfo: _ref.read(preloadedDataProvider).requireValue.deviceInfo,
      pingDelay: const Duration(seconds: 25),
    );

    client.averageLag.addListener(() {
      if (_currentRoute == client.route) {
        _averageLag.value = client.averageLag.value;
      }
    });

    _pool[_currentRoute] = client;
  }

  final Ref _ref;

  final Duration idleTimeout;

  final _averageLag = ValueNotifier(Duration.zero);

  ValueListenable<Duration> get averageLag => _averageLag;

  bool _isDisposed = false;

  Uri _currentRoute = Uri(path: kDefaultSocketRoute);

  SocketClient get currentClient => _pool[_currentRoute]!;

  final Map<Uri, SocketClient> _pool = {};
  final Map<Uri, Timer?> _disposeTimers = {};

  SocketClient open(
    Uri route, {
    int? version,
    bool? forceReconnect,
    VoidCallback? onEventGapFailure,
  }) {
    if (_isDisposed) {
      throw StateError('SocketPool is disposed, cannot open new socket.');
    }

    _currentRoute = route;

    if (_pool[route] == null) {
      final newClient = SocketClient(
        route,
        version: version,
        channelFactory: _ref.read(webSocketChannelFactoryProvider),
        getSession: () => _ref.read(authControllerProvider),
        packageInfo: _ref.read(preloadedDataProvider).requireValue.packageInfo,
        deviceInfo: _ref.read(preloadedDataProvider).requireValue.deviceInfo,
        sri: _ref.read(preloadedDataProvider).requireValue.sri,
        onStreamListen: () {
          if (_isDisposed) return;
          _disposeTimers[route]?.cancel();
        },
        onStreamCancel: () {
          if (_isDisposed) return;
          _disposeTimers[route]?.cancel();
          _disposeTimers[route] = Timer(idleTimeout, () {
            _logger.fine('Disposing idle socket on $route.');
            _pool[route]?.dispose();
            _pool.remove(route);
            if (route == _currentRoute) {
              _currentRoute = Uri(path: kDefaultSocketRoute);
              if (!currentClient.isActive) {
                currentClient.connect();
              }
            }
          });
        },
        onEventGapFailure: onEventGapFailure,
      );
      newClient.averageLag.addListener(() {
        if (_currentRoute == newClient.route) {
          _averageLag.value = newClient.averageLag.value;
        }
      });
      _pool[route] = newClient;
    }

    _pool.forEach((k, c) {
      if (k != route) {
        c.close();
      }
    });

    final client = _pool[route]!;
    if (forceReconnect == true || !client.isActive) {
      client.connect();
    }

    return client;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _averageLag.dispose();
    _disposeTimers.forEach((_, t) => t?.cancel());
    _pool.forEach((_, c) => c.dispose());
  }
}

final socketPoolProvider = Provider<SocketPool>((Ref ref) {
  final pool = SocketPool(ref);
  Timer? closeInBackgroundTimer;

  pool.currentClient.connect();

  final subscription = authEventsStream.listen((_) {
    pool.currentClient.connect();
  });

  final appLifecycleListener = AppLifecycleListener(
    onHide: () {
      closeInBackgroundTimer?.cancel();
      closeInBackgroundTimer = Timer(_kDisconnectOnBackgroundTimeout, () {
        _logger.info(
          'App is in background for ${_kDisconnectOnBackgroundTimeout.inMinutes}m, closing socket.',
        );
        pool.currentClient.close();
      });
    },
    onShow: () {
      closeInBackgroundTimer?.cancel();
      if (!pool.currentClient.isActive) {
        pool.currentClient.connect();
      }
    },
  );

  ref.onDispose(() {
    subscription.cancel();
    pool.dispose();
    closeInBackgroundTimer?.cancel();
    appLifecycleListener.dispose();
  });

  return pool;
}, name: 'SocketPoolProvider');

typedef SocketPingState = ({Duration averageLag, int rating, bool isActive});

final socketPingProvider = NotifierProvider.autoDispose
    .family<SocketPingNotifier, SocketPingState, Uri?>(
      SocketPingNotifier.new,
      name: 'SocketPingProvider',
    );

class SocketPingNotifier extends Notifier<SocketPingState> {
  SocketPingNotifier(this.route);
  final Uri? route;

  @override
  SocketPingState build({Uri? route}) {
    final pool = ref.watch(socketPoolProvider);

    pool.averageLag.addListener(_listener);

    ref.onDispose(() {
      pool.averageLag.removeListener(_listener);
    });

    return _getPing(_currentRouteLag);
  }

  Duration get _currentRouteLag {
    final pool = ref.read(socketPoolProvider);
    return route != null
        ? route == pool.currentClient.route
              ? pool.averageLag.value
              : Duration.zero
        : pool.averageLag.value;
  }

  bool get _currentRouteIsActive {
    final pool = ref.read(socketPoolProvider);
    return route != null
        ? route == pool.currentClient.route && pool.currentClient.isActive
        : pool.currentClient.isActive;
  }

  SocketPingState _getPing(Duration lag) => (
    averageLag: lag,
    isActive: _currentRouteIsActive,
    rating: lag.inMicroseconds == 0
        ? 0
        : lag.inMicroseconds < 150000
        ? 4
        : lag.inMicroseconds < 300000
        ? 3
        : lag.inMicroseconds < 500000
        ? 2
        : 1,
  );

  void _listener() {
    final newState = _getPing(_currentRouteLag);
    if (state != newState) {
      state = newState;
    }
  }
}

final webSocketChannelFactoryProvider = Provider<WebSocketChannelFactory>((Ref ref) {
  return const WebSocketChannelFactory();
});

class WebSocketChannelFactory {
  const WebSocketChannelFactory();

  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return WebSocketChannel.connect(
      Uri.parse(url),
      headers: headers?.cast<String, String>(),
    ).timeout(timeout);
  }
}
