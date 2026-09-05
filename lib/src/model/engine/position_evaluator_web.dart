import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/engine/engine.dart';
import 'package:lichess_mobile/src/model/engine/engine_budget.dart';
import 'package:lichess_mobile/src/model/engine/engine_factory.dart';
import 'package:lichess_mobile/src/model/engine/engine_failure.dart';
import 'package:lichess_mobile/src/model/engine/engine_providers.dart';
import 'package:lichess_mobile/src/model/engine/engine_slot.dart';
import 'package:lichess_mobile/src/model/engine/engine_spec.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/engine/weights_service.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PositionEvaluator');

const kEngineEvalEmissionThrottleDelay = Duration(milliseconds: 200);

const minDepth = 6;

const kEnginePauseDelay = Duration(seconds: 3);

const _kUserNotificationThrottle = Duration(seconds: 10);

const _kUnrecoverableEngineMessage =
    'The chess engine stopped responding. Please restart the app to use it again.';

final positionEvaluatorProvider = NotifierProvider.autoDispose
    .family<PositionEvaluator, EngineEvaluationState, EvaluationContext>(
      PositionEvaluator.new,
      name: 'PositionEvaluatorProvider',
    );

StockfishFlavor evaluatorFlavorFor(Ref ref, Variant variant) =>
    officialStockfishVariants.contains(variant)
    ? ref.read(engineEvaluationPreferencesProvider).enginePref.flavor
    : StockfishFlavor.variant;

EngineSlot evaluatorEngineSlotFor(Ref ref, Variant variant) =>
    switch (evaluatorFlavorFor(ref, variant)) {
      StockfishFlavor.variant => EngineSlot.fairy,
      StockfishFlavor.sf16 => EngineSlot.sf16,
      StockfishFlavor.latestNoNNUE => EngineSlot.sfLatest,
    };

class PositionEvaluator extends Notifier<EngineEvaluationState> {
  PositionEvaluator(this.context);

  final EvaluationContext context;

  static const defaultState = (engine: null, eval: null, isComputing: false, currentWork: null);

  @override
  EngineEvaluationState build() {
    ref.onDispose(_dispose);
    return defaultState;
  }

  EngineBudget get budget => ref.read(engineBudgetProvider);

  StockfishNnueService get _nnueService => ref.read(stockfishNnueServiceProvider);

  Engine? _engine;

  EngineSpec? _spec;

  ProviderSubscription<AsyncValue<Engine>>? _engineSubscription;

  StockfishFlavor? _engineFlavor;

  bool _resolvingSpec = false;

  bool _paused = false;

  Timer? _pauseTimer;

  int _generation = 0;

  Search? _accumulatingFor;

  Search? _currentSearch;

  LocalEval? _currentEval;
  int _expectedPvs = 1;

  EngineFailure? _unrecoverableFailure;

  DateTime? _lastUserNotification;

  Timer? _evalThrottleTimer;
  EvalResult? _pendingEvalResult;

  final _evalController = StreamController<EvalResult>.broadcast();

  Stream<EvalResult> get evalStream => _evalController.stream;

  Stream<EvalResult>? evaluate(EvalWork work, {bool goDeeper = false}) {
    _setEval(null);

    if (!work.threatMode) {
      switch (work.evalCache) {
        case final LocalEval localEval when localEval.searchTime >= work.searchTime:
        case CloudEval _ when goDeeper == false:
          stop();
          return null;
        case _:
          break;
      }
    }

    _logger.info(
      'Starting evaluation at ply ${work.position.ply} with options: '
      'multiPv=${work.multiPv}, cores=${work.threads}, '
      'searchTime=${work.searchTime.inMilliseconds}ms, threatMode=${work.threatMode}',
    );

    _startWork(work);

    return evalStream.where((result) => result.$1 == work);
  }

  EvalWork? get currentWork => state.currentWork;

  void stop() {
    _currentSearch?.stop();
    _setEvalWork(null);
  }

  void release() {
    if (_spec == null && !_resolvingSpec) {
      _logger.fine('Engine already released or never asked for. Ignoring duplicate release call.');
      return;
    }
    _logger.info('Pausing the engine');
    _paused = true;
    _currentSearch?.stop();
    _currentSearch = null;
    _cancelEvalThrottle();
    _currentEval = null;
    _accumulatingFor = null;

    _pauseTimer?.cancel();
    _pauseTimer = Timer(kEnginePauseDelay, () {
      _pauseTimer = null;
      _logger.info('Releasing the engine nobody turned back on');
      _releaseEngine();
    });

    if (ref.mounted) state = defaultState;
  }

  void _startWork(EvalWork work) {
    _paused = false;
    _pauseTimer?.cancel();
    _pauseTimer = null;

    if (_unrecoverableFailure case final failure?) {
      _logger.severe('Refusing engine work: the engine is unusable. $failure');
      _abandonPendingWork();
      _releaseEngine();
      _setEngine(AsyncError(failure, StackTrace.current));
      _notifyUser(failure);
      return;
    }

    _setEvalWork(work);

    final flavor = _flavorFor(work.variant);

    if (_engineFlavor == flavor) {
      if (_engine case final engine?) {
        _setEngine(AsyncData(engine.name.value));
        _compute(work);
      }
      return;
    }

    if (_resolvingSpec) {
      _logger.fine('Work requested while the engine is being chosen; it will run when it is ready');
      return;
    }

    unawaited(_acquireEngine(flavor));
  }

  Future<void> _acquireEngine(StockfishFlavor flavor) async {
    final generation = _generation;
    _resolvingSpec = true;
    _setEngine(const AsyncLoading());

    try {
      final spec = await _resolveSpec(flavor);
      if (generation != _generation) return;

      _logger.fine('Using engine: $spec, budget: $budget');
      _engineFlavor = flavor;
      _watchEngine(spec);
    } finally {
      if (generation == _generation) _resolvingSpec = false;
    }
  }

  void _watchEngine(EngineSpec spec) {
    if (_spec == spec) return;

    _detachEngine();
    _engineSubscription?.close();
    _spec = spec;
    _engineSubscription = ref.listen<AsyncValue<Engine>>(
      engineProvider(spec),
      (_, next) => _onEngineChanged(spec, next),
      fireImmediately: true,
    );
  }

  void _onEngineChanged(EngineSpec spec, AsyncValue<Engine> value) {
    if (_spec != spec) return;

    if (value case AsyncError(:final error, :final stackTrace)) {
      _detachEngine();
      _handleFailure(_asFailure(error, stackTrace, spec));
      _releaseEngine(invalidate: true);
      _setEngine(AsyncError(error, stackTrace));
      _abandonPendingWork();
      return;
    }

    if (value.value case final Engine engine) {
      _attachEngine(engine);
      _computeCurrentWork();
      return;
    }

    _detachEngine();
    _setEngine(const AsyncLoading());
  }

  void _attachEngine(Engine engine) {
    if (identical(_engine, engine)) return;
    _detachEngine();
    _engine = engine;
    engine.name.addListener(_onEngineNameChange);
    engine.isSearching.addListener(_onSearchingChange);
    _setEngine(AsyncData(engine.name.value));
  }

  void _detachEngine() {
    final engine = _engine;
    if (engine == null) return;
    _engine = null;
    _accumulatingFor = null;
    engine.name.removeListener(_onEngineNameChange);
    engine.isSearching.removeListener(_onSearchingChange);
  }

  void _releaseEngine({bool invalidate = false}) {
    _pauseTimer?.cancel();
    _pauseTimer = null;

    _currentSearch?.stop();
    _currentSearch = null;
    _detachEngine();
    _engineSubscription?.close();
    _engineSubscription = null;
    final spec = _spec;
    _spec = null;
    _engineFlavor = null;
    _resolvingSpec = false;
    if (invalidate && spec != null) ref.invalidate(engineProvider(spec));
  }

  EngineFailure _asFailure(Object error, StackTrace stackTrace, EngineSpec spec) => switch (error) {
    final EngineCreationException creation => creation.failure,
    final EngineFailure failure => failure,
    _ => EngineFailure(
      kind: EngineFailureKind.start,
      message: 'The engine failed to start',
      engine: spec.label,
      error: error,
      stackTrace: stackTrace,
    ),
  }.withContext(maxMemoryInMb: budget.maxMemoryInMb);

  Future<EngineSpec> _resolveSpec(StockfishFlavor flavor) async {
    switch (flavor) {
      case StockfishFlavor.variant:
        return const StockfishSpec.fairy();
      case StockfishFlavor.sf16:
        return const StockfishSpec.sf16();
      case StockfishFlavor.latestNoNNUE:
        if (await _nnueService.checkNNUEFiles()) {
          final files = _nnueService.nnueFiles;
          return StockfishSpec.latest(
            bigNetPath: files.bigNet.path,
            smallNetPath: files.smallNet.path,
          );
        }
        _logger.warning('NNUE files not found or corrupted. Falling back to SF16.');
        return const StockfishSpec.sf16();
    }
  }

  StockfishFlavor _flavorFor(Variant variant) => evaluatorFlavorFor(ref, variant);

  void _computeCurrentWork() {
    final work = state.currentWork;
    if (work != null) _startWork(work);
  }

  void _abandonPendingWork() {
    _generation++;
    _setEvalWork(null);
    _currentEval = null;
    _accumulatingFor = null;
    _cancelEvalThrottle();
  }

  void _compute(EvalWork work) {
    final engine = _engine;
    if (engine == null) return;

    final search = engine.search(_searchRequestFor(work));
    _currentSearch = search;

    search.infos.listen((info) => _onSearchInfo(work, search, info));
    unawaited(search.bestMove.then((_) => _onEvalSearchDone(work, search)));
  }

  SearchRequest _searchRequestFor(EvalWork work) {
    final threatMode = work.threatMode;
    return SearchRequest(
      initialPosition: work.initialPosition,
      moves: IList(work.steps.map((step) => step.sanMove.normalizeUci(work.variant))),
      variant: work.variant,
      limit: SearchLimit.movetime(work.searchTime),
      fenOverride: threatMode ? threatModePosition(work.position).fen : null,
      threads: work.threads,
      multiPv: work.multiPv,
      game: context,
    );
  }

  void _onSearchInfo(EvalWork work, Search search, UciInfo info) {
    if (_engine == null) return;

    if (!identical(_accumulatingFor, search)) {
      _accumulatingFor = search;
      _currentEval = null;
      _expectedPvs = 1;
    }

    if (_expectedPvs < info.multiPv) _expectedPvs = info.multiPv;

    if (info.depth < minDepth && info.pv.isNotEmpty) return;

    final isMate = info.mate != null;
    final povEv = info.mate ?? info.cp!;

    final pivot = work.threatMode ? Side.black : Side.white;
    final ev = work.position.turn == pivot ? povEv : -povEv;

    if ((info.isLowerBound || info.isUpperBound) && info.multiPv == 1) return;

    final pvData = PvData(moves: info.pv, cp: isMate ? null : ev, mate: isMate ? ev : null);

    if (info.multiPv == 1) {
      _currentEval = LocalEval(
        position: work.threatMode ? threatModePosition(work.position) : work.position,
        searchTime: info.elapsed,
        depth: info.depth,
        nodes: info.nodes,
        cp: isMate ? null : ev,
        mate: isMate ? ev : null,
        pvs: IList([pvData]),
        millis: info.elapsed.inMilliseconds,
        threatMode: work.threatMode,
      );
    } else if (_currentEval != null) {
      _currentEval = _currentEval!.copyWith(
        pvs: _currentEval!.pvs.add(pvData),
        depth: math.min(_currentEval!.depth, info.depth),
      );
    }

    if (info.multiPv == _expectedPvs && _currentEval != null) {
      _onEvalResult((work, _currentEval!));

      if (info.elapsed > work.searchTime) {
        search.stop();
      }
    }
  }

  void _onEvalSearchDone(EvalWork work, Search search) {
    if (!identical(_accumulatingFor, search)) return;
    if (_currentEval case final eval?) _onEvalResult((work, eval));
  }

  void _onEvalResult(EvalResult result) {
    if (_evalThrottleTimer == null) {
      _emitEval(result);
      _evalThrottleTimer = Timer(kEngineEvalEmissionThrottleDelay, _onThrottleExpired);
    } else {
      _pendingEvalResult = result;
    }
  }

  void _onThrottleExpired() {
    _evalThrottleTimer = null;
    final pending = _pendingEvalResult;
    if (pending != null) {
      _pendingEvalResult = null;
      _emitEval(pending);
      _evalThrottleTimer = Timer(kEngineEvalEmissionThrottleDelay, _onThrottleExpired);
    }
  }

  void _emitEval(EvalResult result) {
    if (_evalController.isClosed) return;
    _evalController.add(result);
    if (result.$1 == state.currentWork) _setEval(result.$2);
  }

  void _cancelEvalThrottle() {
    _evalThrottleTimer?.cancel();
    _evalThrottleTimer = null;
    _pendingEvalResult = null;
  }

  void _handleFailure(EngineFailure failure) {
    _logger.severe(failure.toString(), failure.error, failure.stackTrace);

    if (failure.isUnrecoverable) {
      _unrecoverableFailure = failure;
    }

    reportEngineFailure(failure);

    _notifyUser(failure);
  }

  void _notifyUser(EngineFailure failure) {
    if (!failure.isUnrecoverable) return;

    final now = DateTime.now();
    if (_lastUserNotification != null &&
        now.difference(_lastUserNotification!) < _kUserNotificationThrottle) {
      return;
    }

    try {
      final navigatorContext = ref.read(currentNavigatorKeyProvider).currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;

      showSnackBar(navigatorContext, _kUnrecoverableEngineMessage, type: SnackBarType.error);
      _lastUserNotification = now;
    } catch (e) {
      _logger.fine('Could not show the engine failure message: $e');
    }
  }

  void _setEngine(AsyncValue<String?> engine) {
    if (_paused) return;
    _setState(engineFn: () => engine);
  }

  void _setEval(LocalEval? eval) {
    _setState(evalFn: () => eval);
  }

  void _setEvalWork(EvalWork? work) {
    _setState(workFn: () => work);
  }

  void _setState({
    AsyncValue<String?>? Function()? engineFn,
    LocalEval? Function()? evalFn,
    EvalWork? Function()? workFn,
  }) {
    if (!ref.mounted) return;
    final current = state;
    final newState = (
      engine: engineFn != null ? engineFn() : current.engine,
      eval: evalFn != null ? evalFn() : current.eval,
      isComputing: _engine?.isSearching.value ?? false,
      currentWork: workFn != null ? workFn() : current.currentWork,
    );
    if (current != newState) state = newState;
  }

  void _onSearchingChange() => _setState();

  void _onEngineNameChange() {
    final engine = _engine;
    if (engine == null) return;
    _setEngine(AsyncData(engine.name.value));
  }

  void _dispose() {
    _generation++;
    _cancelEvalThrottle();
    _releaseEngine();
    _evalController.close();
  }
}

typedef EngineEvaluationState = ({
  AsyncValue<String?>? engine,
  LocalEval? eval,
  bool isComputing,
  EvalWork? currentWork,
});

final engineEvaluationProvider = Provider.autoDispose
    .family<EngineEvaluationState, EngineEvaluationFilters>((ref, filters) {
      final state = ref.watch(positionEvaluatorProvider(filters.context));
      final work = state.currentWork;
      if (work == null || filters.path == null || work.path == filters.path) return state;
      return PositionEvaluator.defaultState;
    }, name: 'EngineEvaluationProvider');

typedef EngineEvaluationFilters = ({EvaluationContext context, UciPath? path});
