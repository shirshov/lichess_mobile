import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:material_ui/material_ui.dart';

import 'background_native.dart' if (dart.library_html) 'background_web.dart';

const kBackgroundImageBlurFactor = 8.0;

class FullScreenBackground extends ConsumerWidget {
  const FullScreenBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generalPrefs = ref.watch(generalPreferencesProvider);
    final appDocumentsDirectory = ref
        .read(preloadedDataProvider)
        .requireValue
        .appDocumentsDirectory;

    if (generalPrefs.backgroundImage != null && appDocumentsDirectory != null) {
      return FullScreenBackgroundImage(
        backgroundImage: generalPrefs.backgroundImage!,
        viewport: MediaQuery.sizeOf(context),
        appDocumentsDirectory: appDocumentsDirectory,
        child: child,
      );
    } else if (generalPrefs.backgroundColor != null) {
      return _FullScreenBackgroundColorTheme(
        backgroundColor: generalPrefs.backgroundColor!,
        child: child,
      );
    } else {
      return child;
    }
  }
}

class FullScreenBackgroundImage extends StatefulWidget {
  const FullScreenBackgroundImage({
    required this.backgroundImage,
    required this.viewport,
    required this.appDocumentsDirectory,
    required this.child,
  });

  final BackgroundImage backgroundImage;
  final Size viewport;
  final dynamic appDocumentsDirectory;
  final Widget child;

  static Size imageFitSize(BoxFit boxFit, Size imageSize, Size viewportSize) => switch (boxFit) {
    BoxFit.fitWidth => Size(
      viewportSize.width,
      imageSize.height * viewportSize.width / imageSize.width,
    ),
    BoxFit.fitHeight => Size(
      imageSize.width * viewportSize.height / imageSize.height,
      viewportSize.height,
    ),
    _ => Size(imageSize.width, imageSize.height),
  };

  @override
  State<FullScreenBackgroundImage> createState() => _FullScreenBackgroundImageState();
}

class _FullScreenBackgroundImageState extends State<FullScreenBackgroundImage> {
  final TransformationController _controller = TransformationController();

  Size get pickedImageViewport =>
      Size(widget.backgroundImage.viewportWidth, widget.backgroundImage.viewportHeight);

  @override
  void initState() {
    _updateMatrix(widget.viewport);
    super.initState();
  }

  @override
  void didUpdateWidget(FullScreenBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.backgroundImage.transform != oldWidget.backgroundImage.transform ||
        widget.viewport != oldWidget.viewport) {
      _updateMatrix(widget.viewport);
    }
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  void _updateMatrix(Size viewport) {
    final matrix = viewport == pickedImageViewport
        ? widget.backgroundImage.transform
        : Matrix4.identity();
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final viewportOrientation = widget.viewport.width > widget.viewport.height
        ? Orientation.landscape
        : Orientation.portrait;
    final imageOrientation = widget.backgroundImage.width > widget.backgroundImage.height
        ? Orientation.landscape
        : Orientation.portrait;
    final boxFit = imageOrientation == viewportOrientation
        ? BoxFit.cover
        : imageOrientation == Orientation.portrait
        ? BoxFit.fitWidth
        : BoxFit.fitHeight;

    final imageFitSize = FullScreenBackgroundImage.imageFitSize(
      boxFit,
      Size(widget.backgroundImage.width, widget.backgroundImage.height),
      widget.viewport,
    );

    final decorationImage = buildBackgroundDecorationImage(widget.appDocumentsDirectory, widget.backgroundImage);

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          minScale: 1,
          maxScale: 2,
          panEnabled: false,
          scaleEnabled: false,
          child: Container(
            width: switch (boxFit) {
              BoxFit.fitHeight => imageFitSize.width,
              _ => widget.viewport.width,
            },
            height: switch (boxFit) {
              BoxFit.fitWidth => imageFitSize.height,
              _ => widget.viewport.height,
            },
            decoration: BoxDecoration(
              color: widget.backgroundImage.seedColor,
              image: decorationImage,
            ),
            child: ClipRect(
              child: BackdropFilter(
                enabled: widget.backgroundImage.isBlurred,
                filter: ImageFilter.blur(
                  sigmaX: kBackgroundImageBlurFactor,
                  sigmaY: kBackgroundImageBlurFactor,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _FullScreenBackgroundColorTheme extends StatelessWidget {
  const _FullScreenBackgroundColorTheme({required this.backgroundColor, required this.child});

  final (BackgroundColor, bool) backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (color, _) = backgroundColor;
    return Stack(
      children: [
        ColoredBox(color: color.darker, child: const SizedBox.expand()),
        Positioned.fill(child: child),
      ],
    );
  }
}
