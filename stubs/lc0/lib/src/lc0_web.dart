import 'dart:async';

import 'package:logging/logging.dart';

enum Lc0State { initial, starting, ready, error, disposed }

enum Lc0DiagnosticPhase {
  engineBooting,
  engineRunning,
  engineTeardown,
}

class Lc0Diagnostics {
  const Lc0Diagnostics({
    required this.phase,
    required this.step,
    required this.elapsed,
    required this.looksStuck,
    this.lastError,
  });

  factory Lc0Diagnostics.fromPhase(Lc0DiagnosticPhase phase) => Lc0Diagnostics(
    phase: phase,
    step: '',
    elapsed: Duration.zero,
    looksStuck: false,
  );

  final String phase;
  final String step;
  final Duration elapsed;
  final bool looksStuck;
  final String? lastError;
}

class Lc0 {
  Lc0._(this._stateController);

  final ValueNotifier<Lc0State> _stateController;

  ValueNotifier<Lc0State> get state => _stateController;

  String? _stdin;

  set stdin(String? value) {
    if (_stateController.value == Lc0State.error ||
        _stateController.value == Lc0State.disposed) {
      throw StateError('Engine is gone');
    }
    _stdin = value;
  }

  static Future<Lc0> create({
    required void Function(String line) onStdout,
  }) async {
    final controller = ValueNotifier<Lc0State>(Lc0State.starting);
    await Future<void>.delayed(Duration.zero);
    controller.value = Lc0State.ready;
    return Lc0._(controller);
  }

  Future<void> dispose() async {
    _stateController.value = Lc0State.disposed;
    await Future<void>.delayed(Duration.zero);
  }
}

class Lc0Transport implements EngineTransport {
  Lc0Transport._(this.spec, this._lc0) {
    _controller.onListen = _replayStartupLines;
    _lc0.state.addListener(_onLc0StateChange);
  }

  final _logger = Logger('Lc0Transport');

  static Future<Lc0Transport> connect(Lc0Spec spec) async {
    final lc0 = await Lc0.create(onStdout: (_) {});
    return Lc0Transport._(spec, lc0);
  }

  @override
  final Lc0Spec spec;

  final Lc0 _lc0;

  final _controller = StreamController<String>.broadcast();
  final _death = Completer<EngineFailure?>();

  final List<String> _startupLines = [];
  bool _replayed = false;
  bool _disposing = false;
  Future<void>? _disposal;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<EngineFailure?> get death => _death.future;

  @override
  bool get isDead => _death.isCompleted;

  @override
  EngineDiagnostics? get diagnostics => EngineDiagnostics.lc0(Lc0Diagnostics.fromPhase(Lc0DiagnosticPhase.engineRunning));

  @override
  void send(String command) {
    if (_disposing || isDead) {
      _logger.fine('Dropping "$command": the engine is gone or on its way out.');
      return;
    }
    try {
      _lc0.stdin = command;
    } catch (e, st) {
      _die(_failure(EngineFailureKind.command, 'The engine refused the command "$command"', error: e, stackTrace: st));
    }
  }

  @override
  Future<void> dispose() {
    if (_disposal case final d?) return d;
    _disposing = true;
    return _disposal = _lc0.dispose().whenComplete(() {
      _die(null);
    });
  }

  void _replayStartupLines() {
    if (_replayed) return;
    _replayed = true;
    for (final line in _startupLines) _receive(line);
    _startupLines.clear();
  }

  void _receive(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (_replayed) {
      _controller.add(trimmed);
    } else {
      _startupLines.add(trimmed);
    }
  }

  void _onLc0StateChange() {
    switch (_lc0.state.value) {
      case Lc0State.ready:
      case Lc0State.starting:
        break;
      case Lc0State.error:
        _die(_failure(EngineFailureKind.runtime, 'LC0 engine failed'));
      case Lc0State.initial:
      case Lc0State.disposed:
        _die(null);
    }
  }

  void _die(EngineFailure? failure) {
    if (_death.isCompleted) return;
    _death.complete(failure);
    if (!_controller.isClosed) _controller.close();
  }

  EngineFailure _failure(EngineFailureKind kind, String message, {Object? error, StackTrace? stackTrace}) => EngineFailure(
    kind: kind,
    message: message,
    engine: spec.label,
    engineState: _lc0.state.value.name,
    diagnostics: EngineDiagnostics.lc0(Lc0Diagnostics.fromPhase(Lc0DiagnosticPhase.engineTeardown)),
    error: error,
    stackTrace: stackTrace,
  );
}
