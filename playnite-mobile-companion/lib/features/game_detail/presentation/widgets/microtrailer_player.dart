import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:video_player/video_player.dart';

/// Microtrailer preview player that auto-plays a muted, looping video header.
/// Features an auto-fading touch overlay with Play/Pause, Mute/Unmute, and a scrub bar.
/// For heavy full trailers, protects mobile bandwidth by showing static background artwork
/// with an on-demand floating [Watch Trailer] play pill unless autoStreamTrailersInHero is enabled.
class MicrotrailerPlayer extends StatefulWidget {
  final String? gameId;
  final String? microtrailerDriveFileId;
  final String? microtrailerWebUrl;
  final String? trailerDriveFileId;
  final String? trailerWebUrl;
  final String? backgroundDriveFileId;
  final String? logoDriveFileId;
  final double height;
  final GallerySettings? gallerySettings;
  final bool autoStreamTrailersInHero;
  final VoidCallback? onTrailerStreamInitiated;

  @visibleForTesting
  static bool enableInTests = false;

  @visibleForTesting
  static VideoPlayerController Function(Uri uri, Map<String, String>? headers)? testControllerFactory;

  const MicrotrailerPlayer({
    super.key,
    this.gameId,
    this.microtrailerDriveFileId,
    this.microtrailerWebUrl,
    this.trailerDriveFileId,
    this.trailerWebUrl,
    this.backgroundDriveFileId,
    this.logoDriveFileId,
    this.height = 220,
    this.gallerySettings,
    this.autoStreamTrailersInHero = false,
    this.onTrailerStreamInitiated,
  });

  @override
  State<MicrotrailerPlayer> createState() => MicrotrailerPlayerState();
}

class MicrotrailerPlayerState extends State<MicrotrailerPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isMuted = true;
  bool _hasAudio = false;
  bool _isDisposed = false;
  bool _showOverlay = false;
  bool _isTrailerStreamInitiated = false;
  bool _isBufferingTrailer = false;
  Timer? _overlayTimer;

  bool get isStreamInitiated => _isTrailerStreamInitiated;
  bool get isVideoInitialized => _isInitialized;
  VideoPlayerController? get controller => _controller;

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  GallerySettings? get _effectiveSettings => widget.gallerySettings;

  bool get _autoPlay => _effectiveSettings?.autoPlayMicrotrailers ?? true;
  bool get _defaultMuted => _effectiveSettings?.microtrailerMuted ?? true;
  bool get _showScrubBar => _effectiveSettings?.showVideoScrubBar ?? true;

  File? _getCachedMicrotrailerFile() {
    final loader = PlayniteImageLoader.instance;
    if (widget.microtrailerDriveFileId != null && widget.microtrailerDriveFileId!.isNotEmpty) {
      final f = loader.getCachedFileSync(widget.microtrailerDriveFileId!);
      if (f != null && f.existsSync() && f.lengthSync() > 0) return f;
    }
    if (widget.gameId != null && widget.gameId!.isNotEmpty) {
      final f = loader.getCachedFileSync('media/microtrailers/${widget.gameId}.mp4');
      if (f != null && f.existsSync() && f.lengthSync() > 0) return f;
    }
    return null;
  }

  File? _getCachedFullTrailerFile() {
    final loader = PlayniteImageLoader.instance;
    if (widget.trailerDriveFileId != null && widget.trailerDriveFileId!.isNotEmpty) {
      final f = loader.getCachedFileSync(widget.trailerDriveFileId!);
      if (f != null && f.existsSync() && f.lengthSync() > 0) return f;
    }
    if (widget.gameId != null && widget.gameId!.isNotEmpty) {
      final f = loader.getCachedFileSync('media/trailers/${widget.gameId}.mp4');
      if (f != null && f.existsSync() && f.lengthSync() > 0) return f;
    }
    return null;
  }

  bool get _hasMicrotrailer =>
      (widget.microtrailerDriveFileId != null && widget.microtrailerDriveFileId!.isNotEmpty) ||
      (widget.microtrailerWebUrl != null && widget.microtrailerWebUrl!.isNotEmpty) ||
      _getCachedMicrotrailerFile() != null;

  bool get _hasFullTrailer =>
      (widget.trailerDriveFileId != null && widget.trailerDriveFileId!.isNotEmpty) ||
      (widget.trailerWebUrl != null && widget.trailerWebUrl!.isNotEmpty) ||
      _getCachedFullTrailerFile() != null;

  bool get _effectiveAutoStreamTrailers => widget.autoStreamTrailersInHero;

  bool get _showWatchTrailerPill =>
      !_hasMicrotrailer &&
      _hasFullTrailer &&
      !_effectiveAutoStreamTrailers &&
      !_isInitialized;

  @override
  void initState() {
    super.initState();
    _isMuted = _defaultMuted;
    _checkAndInitVideo();
  }

  void _checkAndInitVideo() {
    if (_isDisposed || _controller != null) return;
    // If only heavy trailer exists and autoStream is disabled, don't auto-init
    if (!_hasMicrotrailer && _hasFullTrailer && !_effectiveAutoStreamTrailers) {
      return;
    }
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant MicrotrailerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gallerySettings != widget.gallerySettings ||
        oldWidget.autoStreamTrailersInHero != widget.autoStreamTrailersInHero) {
      setState(() {});
    }
    if (oldWidget.autoStreamTrailersInHero != widget.autoStreamTrailersInHero) {
      _checkAndInitVideo();
    }
    if (oldWidget.microtrailerDriveFileId != widget.microtrailerDriveFileId ||
        oldWidget.microtrailerWebUrl != widget.microtrailerWebUrl ||
        oldWidget.trailerWebUrl != widget.trailerWebUrl ||
        oldWidget.trailerDriveFileId != widget.trailerDriveFileId ||
        oldWidget.gameId != widget.gameId) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _hasError = false;
      _isTrailerStreamInitiated = false;
      _checkAndInitVideo();
    }
  }

  static Future<bool> _detectMp4HasAudio(File file) async {
    if (_isTesting) return true;
    try {
      final length = await file.length();
      final sampleSize = length > 262144 ? 262144 : length; // read first 256KB
      final bytes = await file.openRead(0, sampleSize).fold<List<int>>([], (p, e) => p..addAll(e));
      // ASCII 'soun' (0x73, 0x6F, 0x75, 0x6E) marks the sound media handler atom in MP4 moov/trak
      final pattern = [0x73, 0x6F, 0x75, 0x6E];
      final limit = bytes.length - 3;
      for (int i = 0; i < limit; i++) {
        if (bytes[i] == pattern[0] &&
            bytes[i + 1] == pattern[1] &&
            bytes[i + 2] == pattern[2] &&
            bytes[i + 3] == pattern[3]) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _startTrailerStream() {
    setState(() {
      _isTrailerStreamInitiated = true;
      _isBufferingTrailer = true;
    });
    widget.onTrailerStreamInitiated?.call();
    _initVideo(playImmediately: true);
  }

  Future<void> _initVideo({bool playImmediately = false}) async {
    if (_isTesting && !MicrotrailerPlayer.enableInTests) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isBufferingTrailer = false;
        });
      }
      return;
    }

    File? localFile;
    String? streamUrl;
    Map<String, String>? streamHeaders;
    bool hasAudio = false;

    // 1. Resolve Microtrailer if available
    final cachedMicro = _getCachedMicrotrailerFile();
    if (cachedMicro != null) {
      localFile = cachedMicro;
      hasAudio = false;
    } else if (widget.microtrailerWebUrl != null && widget.microtrailerWebUrl!.isNotEmpty) {
      streamUrl = widget.microtrailerWebUrl;
      hasAudio = false;
    } else if (widget.microtrailerDriveFileId != null && widget.microtrailerDriveFileId!.isNotEmpty) {
      streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(widget.microtrailerDriveFileId!);
      streamHeaders = {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ...MediaUrlResolver.getAuthHeaders(),
      };
      hasAudio = false;
    }

    // 2. Fall back to Full Trailer only if allowed (auto-stream enabled or user initiated)
    if (localFile == null && streamUrl == null && _hasFullTrailer) {
      if (_effectiveAutoStreamTrailers || _isTrailerStreamInitiated) {
        final cachedTrailer = _getCachedFullTrailerFile();
        if (cachedTrailer != null) {
          localFile = cachedTrailer;
          hasAudio = true;
        } else if (widget.trailerWebUrl != null && widget.trailerWebUrl!.isNotEmpty) {
          streamUrl = widget.trailerWebUrl;
          hasAudio = true;
        } else if (widget.trailerDriveFileId != null && widget.trailerDriveFileId!.isNotEmpty) {
          streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(widget.trailerDriveFileId!);
          streamHeaders = {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            ...MediaUrlResolver.getAuthHeaders(),
          };
          hasAudio = true;
        }
      }
    }

    if (localFile == null && streamUrl == null) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isBufferingTrailer = false;
        });
      }
      return;
    }

    try {
      VideoPlayerController controller;

      if (localFile != null) {
        if (MicrotrailerPlayer.testControllerFactory != null) {
          controller = MicrotrailerPlayer.testControllerFactory!(Uri.file(localFile.path), null);
        } else {
          controller = VideoPlayerController.file(localFile);
        }
        hasAudio = await _detectMp4HasAudio(localFile);
      } else {
        final headers = streamHeaders ??
            <String, String>{
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            };

        if (MicrotrailerPlayer.testControllerFactory != null) {
          controller = MicrotrailerPlayer.testControllerFactory!(Uri.parse(streamUrl!), headers);
        } else {
          controller = VideoPlayerController.networkUrl(
            Uri.parse(streamUrl!),
            httpHeaders: headers,
          );
        }
      }

      _controller = controller;
      await controller.initialize();

      if (_isDisposed || !mounted) {
        await controller.dispose();
        return;
      }

      controller.setLooping(true);
      controller.setVolume(_isMuted ? 0.0 : 1.0);
      if (_autoPlay || playImmediately) {
        controller.play();
      }

      controller.addListener(_onVideoControllerTick);

      setState(() {
        _isInitialized = true;
        _isBufferingTrailer = false;
        _hasError = false;
        _hasAudio = hasAudio;
      });
    } catch (e) {
      debugPrint('Microtrailer playback warning: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
          _isBufferingTrailer = false;
          _isTrailerStreamInitiated = false;
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
    } else {
      _overlayTimer?.cancel();
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

          // Floating Watch Trailer Pill (bottom-right corner of hero banner for on-demand trailer stream)
          if (_showWatchTrailerPill)
            Positioned(
              bottom: 16,
              right: 16,
              child: _buildWatchTrailerPill(),
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
                                      onChangeStart: (val) {
                                        _overlayTimer?.cancel();
                                      },
                                      onChanged: (val) {
                                        final targetMs = (val * _controller!.value.duration.inMilliseconds).round();
                                        _controller!.seekTo(Duration(milliseconds: targetMs));
                                      },
                                      onChangeEnd: (val) {
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
                                if (_hasAudio) ...[
                                  const SizedBox(width: 8),
                                  _buildMuteButton(),
                                ],
                              ],
                            ),
                          )
                        else if (_hasAudio)
                          Positioned(
                            bottom: 8,
                            right: 12,
                            child: _buildMuteButton(),
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

  Widget _buildWatchTrailerPill() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('hero_watch_trailer_pill'),
        onTap: _isBufferingTrailer ? null : _startTrailerStream,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBufferingTrailer) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Loading...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Watch Trailer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMuteButton() {
    return GestureDetector(
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
