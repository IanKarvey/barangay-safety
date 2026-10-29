import 'dart:io';

import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import 'supabase_service.dart';

/// §8 — remote ID verification, replacing the trip to the barangay hall.
///
/// ## Why this doesn't use a public URL
///
/// Incident photos live in a public bucket behind a plain URL, which is fine
/// for a photo of a flooded street. A government ID is **sensitive personal
/// information** under RA 10173 — it carries an ID number and a face — so the
/// bucket is private and there is no `getPublicUrl` call anywhere in this file.
/// Reviewers fetch a short-lived signed URL, and the storage policies
/// independently enforce who is allowed to ask for one.
///
/// ## The path is the permission
///
/// Files are stored as `<user_id>/<filename>`. Every storage policy derives
/// ownership from that first segment, so a user physically cannot write into
/// someone else's folder — the rule is enforced by the database, not by this
/// client remembering to behave.
class IdVerificationService {
  final _supabase = SupabaseService.instance;

  /// How long a reviewer's link to an ID photo stays valid.
  ///
  /// Long enough to work through a queue in one sitting, short enough that a
  /// link pasted into a chat stops working the same day.
  static const _signedUrlTtl = Duration(hours: 1);

  /// Uploads one photograph into [slot] for the signed-in user.
  ///
  /// Overwrites whatever was in that slot before: a resident whose first
  /// attempt came out blurry should be able to simply retake it, not leave
  /// discarded copies of their ID sitting in storage.
  ///
  /// Each slot is a separate upload rather than one atomic three-photo
  /// submission. That is deliberate — people photograph an ID on a phone in a
  /// low-signal barangay, and losing two good photos because the third failed
  /// would be its own reason to give up and walk to the hall instead.
  Future<void> submitIdPhoto(File photo, IdSlot slot) async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You need to be signed in to submit an ID.');
    }

    final mimeType = lookupMimeType(photo.path) ?? 'image/jpeg';
    final extension = photo.path.split('.').last.toLowerCase();
    final path = '$userId/${slot.fileStem}.$extension';

    await _supabase.storage.from(AppConfig.idVerificationBucket).upload(
          path,
          photo,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );

    // Stores the object path, not a URL. A URL would either be public (wrong
    // for this data) or expire (wrong for a database column).
    //
    // `id_submitted_at` is stamped on every slot, so the review queue orders
    // by the most recent activity on a submission rather than by whenever the
    // first photo happened to land.
    await _supabase.client.from('profiles').update({
      slot.column: path,
      'id_submitted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  /// Records which document the resident is presenting.
  ///
  /// Kept separate from the uploads because the choice is made before the
  /// camera opens — and because a school ID changes what else the form has to
  /// ask for (§8 guardian details).
  Future<void> setIdType(String idType) async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.client
        .from('profiles')
        .update({'id_type': idType}).eq('id', userId);
  }

  /// A temporary link a reviewing official can open.
  ///
  /// Returns null rather than throwing when the caller isn't permitted to see
  /// it — an official of another barangay should get an empty space, not an
  /// error dialog naming a resident's file.
  Future<String?> signedUrlFor(String storedPath) async {
    try {
      return await _supabase.storage
          .from(AppConfig.idVerificationBucket)
          .createSignedUrl(storedPath, _signedUrlTtl.inSeconds);
    } catch (_) {
      return null;
    }
  }

  /// Removes a resident's ID photo when an RA 10173 erasure request is
  /// actioned. Verification status is unaffected — an approved resident stays
  /// approved; the barangay simply stops holding the image it approved them on.
  Future<void> deleteId(String storedPath) async {
    await _supabase.storage
        .from(AppConfig.idVerificationBucket)
        .remove([storedPath]);
  }

  /// Removes every ID photograph a user holds, in one call.
  ///
  /// An erasure request that cleared only the front would leave the back and
  /// the selfie — the selfie being the one with their face in it — sitting in
  /// the bucket. Nulls the columns too, so the app does not keep offering a
  /// review link to an object that no longer exists.
  Future<void> deleteAllIdPhotos(String userId) async {
    final row = await _supabase.client
        .from('profiles')
        .select('id_photo_url, id_back_url, id_selfie_url')
        .eq('id', userId)
        .single();

    final paths = [
      row['id_photo_url'] as String?,
      row['id_back_url'] as String?,
      row['id_selfie_url'] as String?,
    ].whereType<String>().toList();

    if (paths.isNotEmpty) {
      await _supabase.storage
          .from(AppConfig.idVerificationBucket)
          .remove(paths);
    }

    await _supabase.client.from('profiles').update({
      'id_photo_url': null,
      'id_back_url': null,
      'id_selfie_url': null,
      'id_submitted_at': null,
    }).eq('id', userId);
  }
}

/// The three photographs that make up an ID submission.
///
/// ## Why three, and why not face recognition
///
/// The question being answered is "is the person holding this ID the person on
/// it?". Face recognition answers it with a biometric template — which under
/// RA 10173 is sensitive personal information carrying its own consent,
/// retention and breach-notification duties. For a barangay with no data
/// protection officer that is a liability, not a feature.
///
/// A selfie holding the ID answers the same question with a human glance and
/// stores no biometric template at all. It is what GCash and the banks
/// actually do. The back is what makes the front checkable: security features,
/// signature panel and control numbers live there.
enum IdSlot {
  /// Name, photo, address — the half people think of as "the ID".
  front(column: 'id_photo_url', fileStem: 'id_front'),

  /// Security features and control numbers. The half that makes the front
  /// verifiable rather than merely legible.
  back(column: 'id_back_url', fileStem: 'id_back'),

  /// The holder, with the ID, in one frame.
  selfie(column: 'id_selfie_url', fileStem: 'id_selfie');

  const IdSlot({required this.column, required this.fileStem});

  /// Column on `profiles` this slot writes to. `front` maps to the original
  /// `id_photo_url` so every submission made before 2026-08-18 stays valid —
  /// renaming it would have been tidier and would have silently invalidated
  /// every ID already on file.
  final String column;

  /// Filename stem inside the user's storage folder.
  final String fileStem;
}
