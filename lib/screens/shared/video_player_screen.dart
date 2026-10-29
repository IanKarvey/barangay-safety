import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_text.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title = 'Video',
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    // Force landscape for video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _isInitialized = true);
      _controller.play();
    } catch (e) {
      setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: AppText(widget.title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _hasError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 60),
                  const SizedBox(height: 16),
                  Text(context.s.couldNotPlayVideo, style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _hasError = false);
                      _initPlayer();
                    },
                    child: Text(context.s.retry, style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              )
            : !_isInitialized
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                    onTap: () => setState(() => _showControls = !_showControls),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                        // Controls overlay
                        AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            color: Colors.black38,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play/Pause + time
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          _controller.value.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                        onPressed: () {
                                          _controller.value.isPlaying
                                              ? _controller.pause()
                                              : _controller.play();
                                        },
                                      ),
                                      Text(
                                        _formatDuration(_controller.value.position),
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                      Expanded(
                                        child: VideoProgressIndicator(
                                          _controller,
                                          allowScrubbing: true,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          colors: const VideoProgressColors(
                                            playedColor: AppColors.primary,
                                            bufferedColor: Colors.white38,
                                            backgroundColor: Colors.white12,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(_controller.value.duration),
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          _controller.value.volume > 0
                                              ? Icons.volume_up_rounded
                                              : Icons.volume_off_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          _controller.setVolume(
                                            _controller.value.volume > 0 ? 0 : 1,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
