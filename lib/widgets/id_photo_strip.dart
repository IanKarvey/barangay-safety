import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/user_model.dart';
import '../screens/shared/photo_gallery_screen.dart';
import '../services/id_verification_service.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

/// §8 — the three ID photographs, signed and shown together.
///
/// ## Why this is a shared widget
///
/// The superadmin screen rendered `Image.network(user.idPhotoUrl!)` directly.
/// That could never have worked: `id_photo_url` holds a **storage path**, not a
/// URL, because the `id-verification` bucket is private — a government ID is
/// sensitive personal information under RA 10173 and a permanent public link
/// would quietly undo that. So the superadmin saw a broken frame while the
/// officials' screen, which signs the path first, worked correctly.
///
/// It also only ever showed the *front*. The three photos only mean anything
/// together: the front says who they claim to be, the back says the document
/// is real, and the selfie says the person holding it is the person on it.
/// Reviewing the front alone invites approving on the weakest of the three.
///
/// Putting it in one widget is what stops the two screens diverging again.
class IdPhotoStrip extends StatefulWidget {
  const IdPhotoStrip({super.key, required this.user, this.height = 96});

  final UserModel user;
  final double height;

  @override
  State<IdPhotoStrip> createState() => _IdPhotoStripState();
}

class _IdPhotoStripState extends State<IdPhotoStrip> {
  late Future<List<(IdSlot, String?)>> _future;

  @override
  void initState() {
    super.initState();
    _future = _sign();
  }

  @override
  void didUpdateWidget(covariant IdPhotoStrip old) {
    super.didUpdateWidget(old);
    // A re-sign is needed when the reviewer moves to a different applicant, or
    // when a resubmission replaces the paths.
    if (old.user.id != widget.user.id ||
        old.user.idPhotoUrl != widget.user.idPhotoUrl ||
        old.user.idBackUrl != widget.user.idBackUrl ||
        old.user.idSelfieUrl != widget.user.idSelfieUrl) {
      _future = _sign();
    }
  }

  /// Signs all three at once — one round trip, not three spinners.
  Future<List<(IdSlot, String?)>> _sign() async {
    final svc = IdVerificationService();
    final paths = <(IdSlot, String?)>[
      (IdSlot.front, widget.user.idPhotoUrl),
      (IdSlot.back, widget.user.idBackUrl),
      (IdSlot.selfie, widget.user.idSelfieUrl),
    ];
    final signed = await Future.wait([
      for (final (_, path) in paths)
        path == null ? Future<String?>.value() : svc.signedUrlFor(path),
    ]);
    return [
      for (var i = 0; i < paths.length; i++) (paths[i].$1, signed[i]),
    ];
  }

  String _slotLabel(AppStrings t, IdSlot slot) => switch (slot) {
        IdSlot.front => t.idFrontTitle,
        IdSlot.back => t.idBackTitle,
        IdSlot.selfie => t.idSelfieTitle,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.s;

    return FutureBuilder<List<(IdSlot, String?)>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final entries = snap.data ?? const <(IdSlot, String?)>[];
        final usable = entries.where((e) => e.$2 != null).toList();

        // Nothing signed. Almost always the storage policy declining rather
        // than a missing photo — say so plainly instead of rendering three
        // broken frames the reviewer has to interpret.
        if (usable.isEmpty) {
          return Container(
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: AppText(
              entries.every((e) => e.$2 == null &&
                      _pathFor(e.$1) == null)
                  ? t.notSubmittedYet
                  : 'You do not have access to these photos.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          );
        }

        final urls = usable.map((e) => e.$2!).toList();

        return SizedBox(
          height: widget.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: usable.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (slot, url) = usable[i];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PhotoGalleryScreen(
                      photoUrls: urls,
                      initialIndex: i,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: CachedNetworkImage(
                        imageUrl: url!,
                        width: widget.height * 1.25,
                        height: widget.height - 16,
                        fit: BoxFit.cover,
                        // Decoded at tile size — ID photos are captured at up
                        // to 1600px, which is ~10MB of bitmap each at full
                        // resolution, in a scrolling list of applicants.
                        memCacheWidth: 480,
                        placeholder: (_, __) => Container(
                          width: widget.height * 1.25,
                          height: widget.height - 16,
                          color: AppColors.divider,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: widget.height * 1.25,
                          height: widget.height - 16,
                          color: AppColors.background,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_rounded,
                              size: 18, color: AppColors.textTertiary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(_slotLabel(t, slot), style: AppTextStyles.caption),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String? _pathFor(IdSlot slot) => switch (slot) {
        IdSlot.front => widget.user.idPhotoUrl,
        IdSlot.back => widget.user.idBackUrl,
        IdSlot.selfie => widget.user.idSelfieUrl,
      };
}
