import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/over_the_board_game.dart';
import 'package:logging/logging.dart';

part 'over_the_board_game_storage.freezed.dart';
part 'over_the_board_game_storage.g.dart';

final _logger = Logger('OverTheBoardGameStorage');

@Freezed(fromJson: true, toJson: true)
sealed class SavedOtbGame with _$SavedOtbGame {
  const SavedOtbGame._();

  factory SavedOtbGame({
    required OverTheBoardGame game,
    required TimeIncrement timeIncrement,
    Duration? whiteTimeLeft,
    Duration? blackTimeLeft,
  }) = _SavedOtbGame;

  factory SavedOtbGame.fromJson(Map<String, dynamic> json) => _$SavedOtbGameFromJson(json);
}

final overTheBoardGameStorageProvider = Provider<OverTheBoardGameStorage>((Ref ref) {
  return OverTheBoardGameStorage(ref);
}, name: 'OverTheBoardGameStorageProvider');

const kOtbGameFileName = 'otb_game.json';

class OverTheBoardGameStorage {
  const OverTheBoardGameStorage(this.ref);
  final Ref ref;

  Future<SavedOtbGame?> fetchOngoingGame() async {
    return null;
  }

  Future<void> save(
    OverTheBoardGame game, {
    required TimeIncrement timeIncrement,
    required Duration? whiteTimeLeft,
    required Duration? blackTimeLeft,
  }) async {}
}
