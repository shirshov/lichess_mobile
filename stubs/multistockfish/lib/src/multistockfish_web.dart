import 'dart:async';

import 'package:logging/logging.dart';

enum StockfishFlavor { sf16, latestNoNNUE, variant }

enum StockfishState { initial, starting, ready, error, disposed }

class StockfishDiagnostics {
  const StockfishDiagnostics({
    required this.phase,
    required this.step,
    required this.elapsed,
    required this.looksStuck,
    this.lastError,
  });

  factory StockfishDiagnostics.fromPhase(String phaseName) => StockfishDiagnostics(
    phase: phaseName,
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

class Stockfish {
  Stockfish._(this._stateController);

  static const latestBigNNUE = 'web_stockfish_big_nnue';
  static const latestSmallNNUE = 'web_stockfish_small_nnue';

  final ValueNotifier<StockfishState> _stateController;

  ValueNotifier<StockfishState> get state => _stateController;

  String? _stdin;

  set stdin(String? value) {
    if (_stateController.value == StockfishState.error ||
        _stateController.value == StockfishState.disposed) {
      throw StateError('Engine is gone');
    }
    _stdin = value;
  }

  static Future<Stockfish> create({
    required StockfishFlavor flavor,
    String? bigNetPath,
    String? smallNetPath,
    required void Function(String line) onStdout,
  }) async {
    final controller = ValueNotifier<StockfishState>(StockfishState.starting);
    await Future<void>.delayed(Duration.zero);
    controller.value = StockfishState.ready;
    return Stockfish._(controller);
  }

  Future<void> dispose() async {
    _stateController.value = StockfishState.disposed;
    await Future<void>.delayed(Duration.zero);
  }
}

class StockfishTransport implements EngineTransport {
  StockfishTransport._(this.spec, this._stockfish) {
    _controller.onListen = _replayStartupLines;
    _stockfish.state.addListener(_onStockfishStateChange);
  }

  final _logger = Logger('StockfishTransport');

  static Future<StockfishTransport> connect(StockfishSpec spec) async {
    final stockfish = await Stockfish.create(
      flavor: spec.flavor,
      bigNetPath: spec.bigNetPath,
      smallNetPath: spec.smallNetPath,
      onStdout: (_) {},
    );
    return StockfishTransport._(spec, stockfish);
  }

  @override
  final StockfishSpec spec;

  final Stockfish _stockfish;

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
  EngineDiagnostics? get diagnostics => EngineDiagnostics.stockfish(StockfishDiagnostics.fromPhase('uciLoop'));

  @override
  void send(String command) {
    if (_disposing || isDead) {
      _logger.fine('Dropping "$command": the engine is gone or on its way out.');
      return;
    }
    try {
      _stockfish.stdin = command;
    } catch (e, st) {
      _die(_failure(EngineFailureKind.command, 'The engine refused the command "$command"', error: e, stackTrace: st));
    }
  }

  @override
  Future<void> dispose() {
    if (_disposal case final d?) return d;
    _disposing = true;
    return _disposal = _stockfish.dispose().whenComplete(() {
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

  void _onStockfishStateChange() {
    switch (_stockfish.state.value) {
      case StockfishState.starting:
      case StockfishState.ready:
        break;
      case StockfishState.error:
        _die(_failure(EngineFailureKind.runtime, 'Stockfish engine failed'));
      case StockfishState.initial:
      case StockfishState.disposed:
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
    engineState: _stockfish.state.value.name,
    diagnostics: EngineDiagnostics.stockfish(StockfishDiagnostics.fromPhase('engineTeardown')),
    error: error,
    stackTrace: stackTrace,
  );
}
