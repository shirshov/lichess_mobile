import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';

const String _kIosAppGroupId = 'group.org.lichess.mobileV2.LichessWidgets';
const List<String> _kIosBlogWidgetKinds = [
  'OfficialBlogWidget',
  'CommunityBlogWidget',
  'UserBlogFeedWidget',
];

void setupHomeWidget(WidgetRef ref) {
  if (Platform.isIOS) {
    HomeWidget.setAppGroupId(_kIosAppGroupId);
  }
  HomeWidget.saveWidgetData<String>('lichessHost', kLichessHost);

  if (Platform.isIOS) {
    ref.listenManual(kidModeProvider, (prev, state) {
      if (state.hasValue && prev?.value != state.value) {
        HomeWidget.saveWidgetData<bool>('isKidMode', state.value).then((_) {
          Future.wait([
            for (final kind in _kIosBlogWidgetKinds) HomeWidget.updateWidget(iOSName: kind),
          ]);
        });
      }
    }, fireImmediately: true);
    ref.listenManual(boardPreferencesProvider, (prev, state) {
      if (prev == null ||
          prev.boardTheme != state.boardTheme ||
          prev.pieceSet != state.pieceSet) {
        Future.wait([
          HomeWidget.saveWidgetData<String>('boardTheme', state.boardTheme.name),
          HomeWidget.saveWidgetData<String>('pieceSet', state.pieceSet.name),
        ]).then((_) {
          HomeWidget.updateWidget(iOSName: 'DailyPuzzleLargeWidget');
        });
      }
    }, fireImmediately: true);
  }
}
