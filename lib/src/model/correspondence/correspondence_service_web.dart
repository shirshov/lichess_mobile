import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/model/correspondence/correspondence_game_storage.dart';
import 'package:lichess_mobile/src/model/correspondence/offline_correspondence_game.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/game/game_socket_events.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/notifications/notification_service.dart';
import 'package:lichess_mobile/src/model/notifications/notifications.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/tab_navigation.dart' show currentNavigatorKeyProvider;
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:logging/logging.dart';

final correspondenceServiceProvider = Provider<CorrespondenceService>((Ref ref) {
  final service = CorrespondenceService(Logger('CorrespondenceService'), ref: ref);
  ref.onDispose(() => service.dispose());
  return service;
}, name: 'CorrespondenceServiceProvider');

class CorrespondenceService {
  CorrespondenceService(this._log, {required this.ref});

  final Ref ref;
  final Logger _log;

  StreamSubscription<ParsedLocalNotification>? _notificationResponseSubscription;
  StreamSubscription<ReceivedFcmMessage>? _fcmSubscription;

  void start() {
    _fcmSubscription = NotificationService.fcmMessageStream.listen((data) {
      final (message: fcmMessage, fromBackground: fromBackground) = data;
      switch (fcmMessage) {
        case CorresGameUpdateFcmMessage(fullId: final fullId, game: final game):
          if (game != null) {
            _onServerUpdateEvent(fullId, game, fromBackground: fromBackground);
          }

        case _:
          break;
      }
    });

    _notificationResponseSubscription = NotificationService.responseStream.listen((data) {
      final (_, notification) = data;
      switch (notification) {
        case CorresGameUpdateNotification(:final fullId):
          _onNotificationResponse(fullId);
        case _:
          break;
      }
    });
  }

  void dispose() {
    _fcmSubscription?.cancel();
    _notificationResponseSubscription?.cancel();
  }

  Future<void> _onNotificationResponse(GameFullId fullId) async {
    final context = ref.read(currentNavigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) return;

    final rootNavState = Navigator.of(context, rootNavigator: true);
    if (rootNavState.canPop()) {
      rootNavState.popUntil((route) => route.isFirst);
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).push(GameScreen.buildRoute(source: ExistingGameSource(fullId)));
  }

  Future<void> syncGames() async {
    if (_authUser == null) {
      return;
    }

    _log.info('Syncing correspondence games...');

    await playRegisteredMoves();

    final storedOngoingGames = await (await _storage).fetchOngoingGames(_authUser?.user.id);

    try {
      final gameRepository = ref.read(gameRepositoryProvider);
      final ongoingGames = await ref.read(ongoingGamesProvider.future);
      for (final sg in storedOngoingGames) {
        final game = ongoingGames.firstWhereOrNull((e) => e.id == sg.$2.id);
        if (game == null) {
          _log.info(
            'Deleting correspondence game ${sg.$2.id} because it is not present on the server anymore',
          );
          (await _storage).delete(sg.$2.id);
        }
      }

      final playableGames = await gameRepository.getMyGamesByIds(
        ISet(ongoingGames.map((e) => e.id)),
      );

      await Future.wait([
        for (final playableGame in playableGames)
          updateStoredGame(
            ongoingGames.firstWhere((e) => e.id == playableGame.id).fullId,
            playableGame,
          ),
      ]);
    } catch (e, st) {
      _log.warning('Failed to sync correspondence games', e, st);
    }
  }

  Future<int> playRegisteredMoves() async {
    throw UnsupportedError('Not available on web');
  }

  Future<void> _onServerUpdateEvent(
    GameFullId fullId,
    PlayableGame game, {
    required bool fromBackground,
  }) async {
    await updateStoredGame(fullId, game);
  }

  Future<void> updateStoredGame(GameFullId fullId, PlayableGame game) async {
    return (await ref.read(correspondenceGameStorageProvider.future)).save(
      OfflineCorrespondenceGame(
        id: game.id,
        fullId: fullId,
        meta: game.meta,
        rated: game.meta.rated,
        steps: game.steps,
        initialFen: game.initialFen,
        status: game.status,
        variant: game.meta.variant,
        speed: game.meta.speed,
        perf: game.meta.perf,
        white: game.white,
        black: game.black,
        youAre: game.youAre,
        daysPerTurn: game.meta.daysPerTurn,
        clock: game.correspondenceClock,
        winner: game.winner,
        isThreefoldRepetition: game.isThreefoldRepetition,
      ),
    );
  }

  AuthUser? get _authUser => ref.read(authControllerProvider);

  Future<CorrespondenceGameStorage> get _storage =>
      ref.read(correspondenceGameStorageProvider.future);
}
