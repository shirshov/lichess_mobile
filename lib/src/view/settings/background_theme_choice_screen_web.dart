import 'dart:math' show max;

import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/background.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_color_utilities/score/score.dart';
import 'package:material_ui/material_ui.dart';

const colorChoices = BackgroundColor.values;
const itemsByRow = 3;

class BackgroundChoiceScreen extends StatelessWidget {
  const BackgroundChoiceScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BackgroundChoiceScreen());
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.background)),
      body: _Body(),
    );
  }
}

class _Body extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);

    return ListView(
      children: [
        ListSection(
          header: SettingsSectionTitle(context.l10n.mobileSettingsCustomBackgroundPresets),
          backgroundColor: ColorScheme.of(context).surfaceContainerLowest,
          children: [
            GridView.builder(
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: itemsByRow,
                crossAxisSpacing: 6.0,
                mainAxisSpacing: 6.0,
                childAspectRatio: 0.5,
              ),
              itemBuilder: (context, index) {
                final t = colorChoices[index];

                return GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true)
                      .push(
                        MaterialPageRoute<(int, bool)?>(
                          builder: (_) => ConfirmColorBackgroundScreen(
                            boardPrefs: boardPrefs,
                            initialIndex: index,
                          ),
                          fullscreenDialog: true,
                        ),
                      )
                      .then((value) {
                        if (context.mounted) {
                          if (value != null) {
                            final (index, _) = value;
                            final selected = colorChoices[index];
                            ref
                                .read(generalPreferencesProvider.notifier)
                                .setBackground(backgroundColor: (selected, true));
                            Navigator.pop(context);
                          }
                        }
                      }),
                  child: SizedBox.expand(child: ColoredBox(color: t.darker)),
                );
              },
              itemCount: colorChoices.length,
            ),
          ],
        ),
      ],
    );
  }
}

class ConfirmColorBackgroundScreen extends StatefulWidget {
  const ConfirmColorBackgroundScreen({
    required this.initialIndex,
    required this.boardPrefs,
    super.key,
  });

  final int initialIndex;
  final BoardPrefs boardPrefs;

  @override
  State<ConfirmColorBackgroundScreen> createState() => _ConfirmColorBackgroundScreenState();
}

class _ConfirmColorBackgroundScreenState extends State<ConfirmColorBackgroundScreen> {
  late PageController _controller;

  @override
  void initState() {
    _controller = PageController(initialPage: widget.initialIndex);
    _controller.addListener(() {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        colorChoices[(_controller.hasClients
                ? _controller.page ?? widget.initialIndex
                : widget.initialIndex)
            .toInt()];
    return _BackgroundTheme(
      baseTheme: BackgroundImage.getTheme(color.color),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final orientation = constraints.maxWidth > constraints.maxHeight
                ? Orientation.landscape
                : Orientation.portrait;
            final landscapeBoardPadding = MediaQuery.paddingOf(context).top + 60.0;
            return Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemBuilder: (context, index) {
                    final backgroundTheme = colorChoices[index];
                    return ColoredBox(
                      color: backgroundTheme.darker,
                      child: const SizedBox.expand(),
                    );
                  },
                  itemCount: colorChoices.length,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: orientation == Orientation.portrait
                          ? Alignment.center
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: orientation == Orientation.portrait ? 0 : 16.0,
                        ),
                        child: StaticChessboard(
                          size: orientation == Orientation.portrait
                              ? constraints.maxWidth
                              : constraints.maxHeight - landscapeBoardPadding * 2,
                          fen: kInitialFEN,
                          orientation: Side.white,
                          settings: StaticChessboardSettings.fromBoardSettings(
                            widget.boardPrefs.toBoardSettings(Variant.standard),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 16.0,
                  left: orientation == Orientation.portrait ? 0 : null,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      context.l10n.mobileSettingsPickAnImageSwipeToDisplay,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        persistentFooterButtons: [
          TextButton(
            child: Text(context.l10n.cancel),
            onPressed: () => Navigator.pop(context, null),
          ),
          TextButton(
            child: Text(context.l10n.accept),
            onPressed: () => Navigator.pop(
              context,
              _controller.hasClients ? (_controller.page!.toInt(), true) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundTheme extends StatelessWidget {
  const _BackgroundTheme({required this.baseTheme, required this.child});

  final ThemeData baseTheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: baseTheme.copyWith(splashFactory: Theme.of(context).splashFactory),
      child: child,
    );
  }
}
