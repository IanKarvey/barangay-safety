import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_text.dart';

class PhotoGalleryScreen extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoGalleryScreen({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;

  // Swipe-down-to-dismiss state
  double _dragOffset = 0;
  bool _isDragging = false;
  late final AnimationController _snapBackCtrl;
  late Animation<double> _snapBackAnim;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _snapBackCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  double get _bgOpacity =>
      (1.0 - (_dragOffset.abs() / 280)).clamp(0.0, 1.0);

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy.abs() < d.delta.dx.abs()) return; // mostly horizontal — ignore
    setState(() {
      _isDragging = true;
      _dragOffset += d.delta.dy;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_dragOffset > 90 || velocity > 600) {
      Navigator.of(context).pop();
      return;
    }
    // Snap back
    _snapBackAnim = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _snapBackCtrl, curve: Curves.easeOutCubic),
    )..addListener(() => setState(() => _dragOffset = _snapBackAnim.value));
    _snapBackCtrl.forward(from: 0).then((_) {
      setState(() => _isDragging = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // ── Black background that fades as user drags down ──────────
            AnimatedContainer(
              duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
              color: Colors.black.withValues(alpha: _bgOpacity),
            ),

            // ── Photo PageView ──────────────────────────────────────────
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.photoUrls.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) {
                  final url = widget.photoUrls[index];
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5.0,
                    child: Center(
                      child: Hero(
                        tag: 'photo_$url',
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white38,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Top bar: close + counter ────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Transform.translate(
                offset: Offset(0, _dragOffset * 0.4),
                child: Opacity(
                  opacity: _bgOpacity,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC000000), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            if (widget.photoUrls.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: AppText(
                                  '${_currentIndex + 1} / ${widget.photoUrls.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom dot indicators ───────────────────────────────────
            if (widget.photoUrls.length > 1)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _bgOpacity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.photoUrls.length, (i) {
                      final active = i == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
              ),

            // ── Swipe-down hint label ───────────────────────────────────
            if (_dragOffset > 30)
              const Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Release to close',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
