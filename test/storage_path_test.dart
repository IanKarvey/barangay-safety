import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/services/incident_service.dart';

/// `incident-photos` was a public bucket until 2026-08-21 — every photograph
/// was fetchable with no credentials at all, and the bucket listed itself so
/// nobody even had to guess a URL.
///
/// The fix stores the storage *path* instead of a public URL and signs on
/// demand. [IncidentService.storagePathOf] is the shim that lets both shapes
/// coexist, because an APK can reach a phone before the backfill migration
/// reaches the database. If it gets this wrong, photographs silently stop
/// resolving — which is why it is pinned here rather than trusted.
void main() {
  const bare = 'a1b2c3d4-0000-0000-0000-000000000000/photo-1.jpg';

  group('storagePathOf', () {
    test('a bare path is returned untouched', () {
      expect(IncidentService.storagePathOf(bare), bare);
    });

    test('a legacy public URL is reduced to its path', () {
      const url =
          'https://your-project-ref.supabase.co/storage/v1/object/public/incident-photos/$bare';
      expect(IncidentService.storagePathOf(url), bare);
    });

    test('a query string is dropped', () {
      // Old rows can carry cache-busting or download params.
      const url =
          'https://x.supabase.co/storage/v1/object/public/incident-photos/$bare?t=123&download=';
      expect(IncidentService.storagePathOf(url), bare);
    });

    test('percent-encoding is decoded, so signing matches the real object', () {
      const encoded =
          'https://x.supabase.co/storage/v1/object/public/incident-photos/folder%20name/a%20photo.jpg';
      expect(IncidentService.storagePathOf(encoded), 'folder name/a photo.jpg');
    });

    test('the non-resident proof layout survives', () {
      // Proof photos share the bucket under non-resident/<sessionId>/<file>.
      const p = 'non-resident/11111111-2222-3333-4444-555555555555/proof.jpg';
      const url = 'https://x.supabase.co/storage/v1/object/public/incident-photos/$p';
      expect(IncidentService.storagePathOf(url), p);
      expect(IncidentService.storagePathOf(p), p);
    });

    test('an already-signed URL still yields the path', () {
      // Signed URLs use /object/sign/. This must not silently return the whole
      // URL as a "path" — re-signing garbage produces a dead link.
      const signed =
          'https://x.supabase.co/storage/v1/object/sign/incident-photos/$bare?token=abc.def';
      expect(IncidentService.storagePathOf(signed), bare);
    });

    test('an unrecognised URL is returned as-is rather than mangled', () {
      // Better to hand back something that fails visibly than to invent a path
      // that points at the wrong object.
      const foreign = 'https://example.com/some/other/image.jpg';
      expect(IncidentService.storagePathOf(foreign), foreign);
    });

    test('an empty string does not throw', () {
      expect(IncidentService.storagePathOf(''), '');
    });
  });
}
