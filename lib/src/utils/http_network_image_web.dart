import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class HttpNetworkImage extends ImageProvider<HttpNetworkImage> {
  const HttpNetworkImage(this.url, http.Client client, {this.scale = 1.0, this.headers})
    : _client = client;

  final http.Client _client;

  final String url;

  final double scale;

  final Map<String, String>? headers;

  @override
  Future<HttpNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<HttpNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(HttpNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode: decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<HttpNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(HttpNetworkImage key, {required ImageDecoderCallback decode}) async {
    try {
      assert(key == this);

      final Uri resolved = Uri.base.resolve(key.url);

      final response = await _client.get(resolved, headers: headers);

      if (response.statusCode != 200) {
        throw NetworkImageLoadException(statusCode: response.statusCode, uri: resolved);
      }

      if (response.bodyBytes.isEmpty) {
        throw NetworkImageLoadException(statusCode: response.statusCode, uri: resolved);
      }

      return await decode(await ui.ImmutableBuffer.fromUint8List(response.bodyBytes));
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is HttpNetworkImage && other.url == url && other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'HttpNetworkImage')}("$url", scale: ${scale.toStringAsFixed(1)})';
}
