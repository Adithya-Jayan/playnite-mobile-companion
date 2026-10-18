import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';

/// High-performance priority cached image widget for Playnite assets.
///
/// Features:
/// - LIFO Priority (visible items load first instead of waiting for a 300-item sequential queue)
/// - Off-screen request cancellation (aborts in-flight TCP requests when scrolled past)
/// - Persistent local flash disk cache with synchronous O(1) 0ms hits on revisit
/// - Memory downsampling (memCacheWidth / memCacheHeight)
/// - Transparent support for Google Drive file IDs, direct HTTP URLs, and local file:// paths
/// - Instant display when cached; smooth 150ms fade-in on first arrival
class PlayniteCachedImage extends StatefulWidget {
  final String? mediaId;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const PlayniteCachedImage({
    super.key,
    required this.mediaId,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  State<PlayniteCachedImage> createState() => _PlayniteCachedImageState();
}

class _PlayniteCachedImageState extends State<PlayniteCachedImage> {
  File? _file;
  bool _isLoading = false;
  bool _hasFailed = false;

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(PlayniteCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) {
      _cancelOldRequest(oldWidget.mediaId);
      _resolveImage();
    } else if (_hasFailed && widget.mediaId != null) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    if (_isLoading && widget.mediaId != null) {
      _cancelOldRequest(widget.mediaId);
    }
    super.dispose();
  }

  void _cancelOldRequest(String? mediaId) {
    if (mediaId == null || mediaId.trim().isEmpty) return;
    PlayniteImageLoader.instance.cancel(mediaId, _onImageLoaded);
    _isLoading = false;
  }

  void retry() {
    if (_isLoading) return;
    setState(() {
      _hasFailed = false;
      _resolveImage();
    });
  }

  void _resolveImage() {
    final mediaId = widget.mediaId;
    if (mediaId == null || mediaId.trim().isEmpty) {
      _file = null;
      _isLoading = false;
      _hasFailed = false;
      return;
    }

    if (_isTesting) {
      _file = null;
      _isLoading = false;
      _hasFailed = false;
      return;
    }

    // Fast O(1) synchronous check for local flash disk hit (0ms latency)
    final cached = PlayniteImageLoader.instance.getCachedFileSync(mediaId);
    if (cached != null) {
      _file = cached;
      _isLoading = false;
      _hasFailed = false;
      return;
    }

    // Enqueue LIFO request (visible items pushed to top)
    _file = null;
    _isLoading = true;
    _hasFailed = false;
    PlayniteImageLoader.instance.load(
      mediaId: mediaId,
      onComplete: _onImageLoaded,
    );
  }

  void _onImageLoaded(File? file) {
    if (!mounted) {
      _isLoading = false;
      if (file != null) {
        _file = file;
        _hasFailed = false;
      } else {
        _hasFailed = true;
      }
      return;
    }

    setState(() {
      _isLoading = false;
      if (file != null) {
        _file = file;
        _hasFailed = false;
      } else {
        _hasFailed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaId == null || widget.mediaId!.trim().isEmpty || _isTesting) {
      return _wrapBorder(_buildPlaceholder());
    }

    if (_file != null) {
      return _wrapBorder(
        Image.file(
          _file!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: widget.memCacheWidth,
          cacheHeight: widget.memCacheHeight,
          errorBuilder: (ctx, err, stack) => widget.errorWidget ?? _buildPlaceholder(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                if (frame == null) _buildPlaceholder(),
                AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: child,
                ),
              ],
            );
          },
        ),
      );
    }

    if (_hasFailed) {
      return GestureDetector(
        onTap: retry,
        behavior: HitTestBehavior.opaque,
        child: _wrapBorder(widget.errorWidget ?? _buildPlaceholder()),
      );
    }

    return _wrapBorder(widget.placeholder ?? _buildPlaceholder());
  }

  Widget _wrapBorder(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }
    return child;
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ??
        Container(
          color: AppTheme.surfaceLight,
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: Icon(Icons.sports_esports, color: AppTheme.textMuted, size: 28),
          ),
        );
  }
}
