import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/game/offline_computer_game.dart';
import 'package:logging/logging.dart';

part 'offline_computer_game_storage.freezed.dart';
part 'offline_computer_game_storage.g.dart';

final _logger = Logger('OfflineComputerGameStorage');

@Freezed(fromJson: true, toJson: true)
sealed class SavedOfflineComputerGame with _$SavedOfflineComputerGame {
  const SavedOfflineComputerGame._();

  factory SavedOfflineComputerGame({required OfflineComputerGame game}) = _SavedOfflineComputerGame;

  factory SavedOfflineComputerGame.fromJson(Map<String, dynamic> json) =>
      _$SavedOfflineComputerGameFromJson(json);
}

final offlineComputerGameStorageProvider = Provider<OfflineComputerGameStorage>((Ref ref) {
  return OfflineComputerGameStorage(ref);
}, name: 'OfflineComputerGameStorageProvider');

const kOfflineComputerGameFileName = 'offline_computer_game.json';

class OfflineComputerGameStorage {
  const OfflineComputerGameStorage(this.ref);
  final Ref ref;

  Future<SavedOfflineComputerGame?> fetchGame() async {
    return null;
  }

  Future<void> save(SavedOfflineComputerGame savedGame) async {}
}
