import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/model/log/app_log_storage.dart';
import 'package:lichess_mobile/src/model/settings/log_preferences.dart';
import 'package:lichess_mobile/src/utils/lru_list.dart';
import 'package:logging/logging.dart';

const _loggersToShowInTerminal = {'HttpClient', 'Socket', 'PositionEvaluator', 'Stockfish', 'Lc0'};

const _loggersReportedToCrashlytics = {'Stockfish', 'Lc0'};

final appLogServiceProvider = Provider<AppLogService>(
  (Ref ref) => AppLogService(ref),
  name: 'AppLogServiceProvider',
);

class AppLogService {
  AppLogService(this.ref);

  final Ref ref;
  final _logs = LRUList<LogRecord>(capacity: 1024);

  Iterable<LogRecord> get logs => _logs.values;

  void start() {
    if (kDebugMode) {
      Logger.root.level = Level.ALL;
    } else {
      ref.listen(logPreferencesProvider.select((prefs) => prefs.level), (prev, next) {
        if (next != prev) {
          Logger.root.level = next;
        }
      }, fireImmediately: true);
    }

    Logger.root.onRecord.listen((record) {
      if (kDebugMode) {
        developer.log(
          record.message,
          time: record.time,
          name: record.loggerName,
          level: record.level.value,
          error: record.error,
          stackTrace: record.stackTrace,
        );

        if (_loggersToShowInTerminal.contains(record.loggerName) &&
            record.level >= Level.FINE) {
          debugPrint(
            '[${record.loggerName}] ${record.message}${record.error != null ? ' (${record.error})' : ''}',
          );
        }
      } else {
        if (_loggersReportedToCrashlytics.contains(record.loggerName) &&
            record.level >= Level.SEVERE) {
          LichessBinding.instance.firebaseCrashlytics.recordError(
            record.error ?? record.message,
            record.stackTrace,
            reason: '[${record.loggerName}] ${record.message}',
            fatal: false,
          );
        }
      }

      _logs.put(record);

      scheduleMicrotask(() {
        try {
          ref
              .read(appLogStorageProvider.future)
              .then((storage) => storage.save(AppLogEntry.fromLogRecord(record)), onError: (_) {});
        } catch (_) {}
      });
    });
  }

  void clear() {
    _logs.clear();
  }
}

final class ProviderLogger extends ProviderObserver {
  final _logger = Logger('Provider');

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _logger.finer('${context.provider.name ?? context.provider.runtimeType} initialized', value);
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _logger.finer('${context.provider.name ?? context.provider.runtimeType} disposed or rebuilt');
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    _logger.severe(
      '${context.provider.name ?? context.provider.runtimeType} error',
      error,
      stackTrace,
    );
  }
}
