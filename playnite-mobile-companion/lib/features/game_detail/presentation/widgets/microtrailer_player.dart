import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:video_player/video_player.dart';

/// Microtrailer preview player that auto-plays a muted, looping video header.
/// Features an auto-fading touch overlay with Play/Pause, Mute/Unmute, and a scrub bar.
class MicrotrailerPlayer extends StatefulWidget {
  final String? microtrailerDriveFileId;
  final String? trailerDriveFileId;
  final String? trailerWebUrl;
  final String? backgroundDriveFileId;
  final String? logoDriveFileId;
  final double height;
  final GallerySettings? gallerySettings;

  const MicrotrailerPlayer({
    super.key,
    this.microtrailerDriveFileId,
    this.trailerDriveFileId,
    this.trailerWebUrl,
    this.backgroundDriveFileId,
    this.logoDriveFileId,
    this.height = 220,
    this.gallerySettings,
  });

  @override
  State<MicrotrailerPlayer> createState() => _MicrotrailerPlayerState();
}

class _MicrotrailerPlayerState extends State<MicrotrailerPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isMuted = true;
  bool _isDisposed = false;
  bool _showOverlay = true;
  Timer? _overlayTimer;

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  bool get _autoPlay => widget.gallerySettings?.autoPlayMicrotrailers ?? true;
  bool get _defaultMuted => widget.gallerySettings?.microtrailerMuted ?? true;
  bool get _showScrubBar => widget.gallerySettings?.showVideoScrubBar ?? true;

  @override
  void initState() {
    super.initState();
    _isMuted = _defaultMuted;
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant MicrotrailerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.microtrailerDriveFileId != widget.microtrailerDriveFileId ||
        oldWidget.trailerWebUrl != widget.trailerWebUrl ||
        oldWidget.trailerDriveFileId != widget.trailerDriveFileId) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _hasError = false;
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final videoSource = (widget.microtrailerDriveFileId != null && widget.microtrailerDriveFileId!.isNotEmpty)
        ? widget.microtrailerDriveFileId
        : ((widget.trailerWebUrl != null && widget.trailerWebUrl!.isNotEmpty)
            ? widget.trailerWebUrl
            : widget.trailerDriveFileId);

    if (videoSource == null || videoSource.isEmpty || _isTesting) return;

    try {
      final isDirectHttp = videoSource.startsWith('http://') || videoSource.startsWith('https://');
      final streamUrl = isDirectHttp ? videoSource : MediaUrlResolver.getDriveMediaStreamUrl(videoSource);
      final headers = (isDirectHttp && !streamUrl.contains('googleapis.com'))
          ? <String, String>{}
          : MediaUrlResolver.getAuthHeaders();

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: headers,
      );

      _controller = controller;
      await controller.initialize();

      if (_isDisposed || !mounted) {
        await controller.dispose();
        return;
      }

      controller.setLooping(true);
      controller.setVolume(_isMuted ? 0.0 : 1.0);
      if (_autoPlay) {
        controller.play();
      }

      controller.addListener(_onVideoControllerTick);

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      _startOverlayTimer();
    } catch (e) {
      debugPrint('Microtrailer playback warning: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _onVideoControllerTick() {
    if (mounted && !_isDisposed && _showOverlay) {
      setState(() {});
    }
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDisposed && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
    if (_showOverlay) {
      _startOverlayTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized || _isDisposed || !mounted) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showOverlay = true;
        _overlayTimer?.cancel();
      } else {
        _controller!.play();
        _startOverlayTimer();
      }
    });
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized || _isDisposed || !mounted) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
    _startOverlayTimer();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _overlayTimer?.cancel();
    _controller?.removeListener(_onVideoControllerTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base layer: Static Background Fanart or Gradient (always visible during loading & streaming)
          if (widget.backgroundDriveFileId != null && widget.backgroundDriveFileId!.isNotEmpty)
            _buildBackgroundImage(widget.backgroundDriveFileId!)
          else
            _buildFallbackGradient(),

          // Video Layer: Smoothly cross-fades over the background fanart once frames are playing
          if (_isInitialized && _controller != null && !_hasError)
            AnimatedOpacity(
              opacity: _controller!.value.isPlaying ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 16,
                  height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 9,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),

          // Dark gradient vignette overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black38,
                  Colors.transparent,
                  AppTheme.background,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // Transparent Game Title Logo (if available) centered/bottom
          if (widget.logoDriveFileId != null && widget.logoDriveFileId!.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 65),
                child: _buildLogo(widget.logoDriveFileId!),
              ),
            ),

          // Interactive Tap Area for Overlay
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleOverlay,
            ),
          ),

          // Auto-fading touch controls overlay
          if (_isInitialized && _controller != null && !_hasError)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: AnimatedOpacity(
                  opacity: _showOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Stack(
                      children: [
                        // Center Play/Pause button
                        Center(
                          child: IconButton(
                            iconSize: 48,
                            icon: Icon(
                              _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                        ),

                        // Bottom Scrub Bar, Duration & Mute Controls (safe from status bar)
                        if (_showScrubBar)
                          Positioned(
                            bottom: 8,
                            left: 12,
                            right: 12,
                            child: Row(
                              children: [
                                Text(
                                  _formatDuration(_controller!.value.position),
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                      trackHeight: 3,
                                      activeTrackColor: AppTheme.primary,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: AppTheme.primary,
                                    ),
                                    child: Slider(
                                      value: _controller!.value.duration.inMilliseconds > 0
                                          ? (_controller!.value.position.inMilliseconds /
                                                  _controller!.value.duration.inMilliseconds)
                                              .clamp(0.0, 1.0)
                                          : 0.0,
                                      onChanged: (val) {
                                        final targetMs = (val * _controller!.value.duration.inMilliseconds).round();
                                        _controller!.seekTo(Duration(milliseconds: targetMs));
                                        _startOverlayTimer();
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDuration(_controller!.value.duration),
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                const SizedBox(width: 8),
                                // Mute / Unmute Button right beside progress bar
                                GestureDetector(
                                  onTap: _toggleMute,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.white24, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isMuted ? Icons.volume_off : Icons.volume_up,
                                          size: 15,
                                          color: _isMuted ? Colors.white70 : AppTheme.primaryLight,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isMuted ? 'MUTE' : 'UNMUTE',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundImage(String bgId) {
    return PlayniteCachedImage(
      mediaId: bgId,
      fit: BoxFit.cover,
      isPriority: true,
      memCacheWidth: 1280,
      memCacheHeight: 720,
      placeholder: _buildFallbackGradient(),
      errorWidget: _buildFallbackGradient(),
    );
  }

  Widget _buildLogo(String logoId) {
    return PlayniteCachedImage(
      mediaId: logoId,
      fit: BoxFit.contain,
      isPriority: true,
      memCacheWidth: 400,
      placeholder: const SizedBox.shrink(),
      errorWidget: const SizedBox.shrink(),
    );
  }

  Widget _buildFallbackGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E272E),
            Color(0xFF0F141C),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.videogame_asset, size: 48, color: Colors.white12),
      ),
    );
  }
}
