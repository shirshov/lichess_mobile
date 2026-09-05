import 'package:flutter/widgets.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';

class VariantLabel extends StatelessWidget {
  const VariantLabel(this.variant, {super.key});

  final Variant variant;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final alignment = CrossAxisAlignment.center;
    final descriptionStyle = Styles.subtitle.copyWith(color: textShade(context, Styles.subtitleOpacity));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(variant.icon, size: style.fontSize, color: style.color),
              ),
              const WidgetSpan(child: SizedBox(width: 8)),
              TextSpan(text: variant.label(context.l10n)),
            ],
          ),
        ),
        Text(variant.description(context.l10n), style: descriptionStyle),
      ],
    );
  }
}

class VariantAppBarTitle extends StatelessWidget {
  const VariantAppBarTitle({super.key, required this.variant, required this.title});

  final Variant variant;
  final String title;

  static const excludedIcons = [Variant.standard, Variant.fromPosition];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!excludedIcons.contains(variant)) ...[Icon(variant.icon), const SizedBox(width: 5.0)],
        Flexible(child: AppBarTitleText(title)),
      ],
    );
  }
}
