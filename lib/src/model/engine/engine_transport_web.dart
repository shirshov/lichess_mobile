import 'dart:async';

import 'package:lichess_mobile/src/model/engine/engine_diagnostics.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:logging/logging.dart';

/// A running native engine, seen as a line-oriented pipe with a lifetime.
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
  StockfishTransport._(this.spec, dynamic _stockfish);

  @override
  final StockfishSpec spec;

  @override
  Stream<String> get lines => throw UnsupportedError('lines');

  @override
  Future<EngineFailure?> get death => throw UnsupportedError('death');

  @override
  bool get isDead => throw UnsupportedError('isDead');

  @override
  EngineDiagnostics? get diagnostics => throw UnsupportedError('diagnostics');

  static Future<StockfishTransport> connect(StockfishSpec spec) async {
    throw UnsupportedError('StockfishTransport.connect');
  }

  @override
  void send(String command) {
    throw UnsupportedError('send');
  }

  @override
  Future<void> dispose() {
    throw UnsupportedError('dispose');
  }
}

class Lc0Transport implements EngineTransport {
  Lc0Transport._(this.spec, dynamic _lc0);

  @override
  final Lc0Spec spec;

  @override
  Stream<String> get lines => throw UnsupportedError('lines');

  @override
  Future<EngineFailure?> get death => throw UnsupportedError('death');

  @override
  bool get isDead => throw UnsupportedError('isDead');

  @override
  EngineDiagnostics? get diagnostics => throw UnsupportedError('diagnostics');

  static Future<Lc0Transport> connect(Lc0Spec spec) async {
    throw UnsupportedError('Lc0Transport.connect');
  }

  @override
  void send(String command) {
    throw UnsupportedError('send');
  }

  @override
  Future<void> dispose() {
    throw UnsupportedError('dispose');
  }
}
