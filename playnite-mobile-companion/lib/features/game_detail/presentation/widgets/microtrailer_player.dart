import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:video_player/video_player.dart';

/// Microtrailer preview player that auto-plays a muted, looping 6-second video.
/// Falls back to background fanart or colored placeholder if trailer is absent or fails to load.
class MicrotrailerPlayer extends StatefulWidget {
  final String? microtrailerDriveFileId;
  final String? backgroundDriveFileId;
  final String? logoDriveFileId;
  final double height;

  const MicrotrailerPlayer({
    super.key,
    this.microtrailerDriveFileId,
    this.backgroundDriveFileId,
    this.logoDriveFileId,
    this.height = 220,
  });

  @override
  State<MicrotrailerPlayer> createState() => _MicrotrailerPlayerState();
}

class _MicrotrailerPlayerState extends State<MicrotrailerPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant MicrotrailerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.microtrailerDriveFileId != widget.microtrailerDriveFileId) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _hasError = false;
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final videoId = widget.microtrailerDriveFileId;
    if (videoId == null || videoId.isEmpty) return;

    try {
      final streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(videoId);
      final headers = MediaUrlResolver.getAuthHeaders();

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: headers,
      );

      await _controller!.initialize();
      _controller!.setLooping(true);
      _controller!.setVolume(0.0); // Muted preview loop
      _controller!.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Microtrailer playback warning: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
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
          // Background media: Video or Static Image or Fallback Gradient
          if (_isInitialized && _controller != null && !_hasError)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (widget.backgroundDriveFileId != null && widget.backgroundDriveFileId!.isNotEmpty)
            Image.network(
              MediaUrlResolver.getDriveMediaStreamUrl(widget.backgroundDriveFileId!),
              headers: MediaUrlResolver.getAuthHeaders(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallbackGradient(),
            )
          else
            _buildFallbackGradient(),

          // Dark gradient vignette overlay for high-contrast text and logo legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black26,
                  Colors.transparent,
                  AppTheme.background,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Looping video badge indicator
          if (_isInitialized && !_hasError)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 12, color: AppTheme.primaryLight),
                    SizedBox(width: 4),
                    Text(
                      'PREVIEW',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Transparent Game Title Logo (if available) centered/bottom
          if (widget.logoDriveFileId != null && widget.logoDriveFileId!.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 70),
                child: Image.network(
                  MediaUrlResolver.getDriveMediaStreamUrl(widget.logoDriveFileId!),
                  headers: MediaUrlResolver.getAuthHeaders(),
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
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
