import 'dart:async';

import 'package:lichess_mobile/src/model/engine/engine_diagnostics.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:logging/logging.dart';

abstract class EngineTransport {
  EngineSpec get spec;

  Stream<String> get lines;

  void send(String command);

  Future<EngineFailure?> get death;

  bool get isDead;

  EngineDiagnostics? get diagnostics;

  Future<void> dispose();
}

class StockfishTransport implements EngineTransport {
  StockfishTransport._(this.spec, dynamic _stockfish) {
    throw UnsupportedError('Not available on web');
  }

  final _logger = Logger('StockfishTransport');

  static Future<StockfishTransport> connect(StockfishSpec spec) async {
    throw UnsupportedError('Not available on web');
  }

  @override
  final StockfishSpec spec;

  final StreamController<String> _controller = StreamController<String>.broadcast();
  final _death = Completer<EngineFailure?>();

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<EngineFailure?> get death => _death.future;

  @override
  bool get isDead => _death.isCompleted;

  @override
  EngineDiagnostics? get diagnostics => null;

  @override
  void send(String command) {
    throw UnsupportedError('Not available on web');
  }

  @override
  Future<void> dispose() async {
    throw UnsupportedError('Not available on web');
  }
}

class Lc0Transport implements EngineTransport {
  Lc0Transport._(this.spec, dynamic _lc0) {
    throw UnsupportedError('Not available on web');
  }

  final _logger = Logger('Lc0Transport');

  static Future<Lc0Transport> connect(Lc0Spec spec) async {
    throw UnsupportedError('Not available on web');
  }

  @override
  final Lc0Spec spec;

  final StreamController<String> _controller = StreamController<String>.broadcast();
  final _death = Completer<EngineFailure?>();

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<EngineFailure?> get death => _death.future;

  @override
  bool get isDead => _death.isCompleted;

  @override
  EngineDiagnostics? get diagnostics => null;

  @override
  void send(String command) {
    throw UnsupportedError('Not available on web');
  }

  @override
  Future<void> dispose() async {
    throw UnsupportedError('Not available on web');
  }
}
