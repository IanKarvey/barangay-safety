import 'supabase_service.dart';

/// A reporter's history, summarised.
class TrustScore {
  /// 0..100, starting from a neutral 70.
  final int score;
  final int totalReports;
  final int resolvedReports;
  final int flaggedReports;
  final int strikes;
  final bool isVerified;
  final bool isLocked;

  const TrustScore({
    required this.score,
    required this.totalReports,
    required this.resolvedReports,
    required this.flaggedReports,
    required this.strikes,
    required this.isVerified,
    required this.isLocked,
  });

  /// What a reporter with no history at all looks like. Deliberately neutral,
  /// not low: a first-time reporter has done nothing wrong.
  const TrustScore.neutral()
      : score = 70,
        totalReports = 0,
        resolvedReports = 0,
        flaggedReports = 0,
        strikes = 0,
        isVerified = false,
        isLocked = false;

  factory TrustScore.fromJson(Map<String, dynamic> json) => TrustScore(
        score: (json['score'] as num?)?.toInt() ?? 70,
        totalReports: (json['total_reports'] as num?)?.toInt() ?? 0,
        resolvedReports: (json['resolved_reports'] as num?)?.toInt() ?? 0,
        flaggedReports: (json['flagged_reports'] as num?)?.toInt() ?? 0,
        strikes: (json['strikes'] as num?)?.toInt() ?? 0,
        isVerified: json['is_verified'] as bool? ?? false,
        isLocked: json['is_locked'] as bool? ?? false,
      );

  /// Only three bands, on purpose. A number like 63 invites an official to
  /// treat it as a measurement; "established / new / check this one" is what
  /// the data can actually support.
  TrustBand get band {
    if (score >= 80) return TrustBand.established;
    if (score >= 50) return TrustBand.ordinary;
    return TrustBand.caution;
  }

  /// True when there is genuinely nothing to say, so the UI can stay quiet
  /// rather than badge every first-time reporter.
  bool get isUnremarkable =>
      band == TrustBand.ordinary && strikes == 0 && flaggedReports == 0;
}

enum TrustBand { established, ordinary, caution }

/// §4.5 — how much weight to give a report, from the reporter's own history.
///
/// ## What this is not
///
/// **It is not a gate.** Nothing in this app refuses, delays, or deprioritises
/// a report because of a score, and nothing should. The person with the worst
/// history in the barangay can still be the one watching a house burn down,
/// and a system that learns to disbelieve them will eventually be wrong about
/// something that matters.
///
/// It annotates. An official seeing "3 false reports on record" alongside a
/// report reads it differently — that is the whole intended effect.
///
/// ## Why the scoring lives in SQL
///
/// `get_trust_score` is SECURITY DEFINER, so an official gets the summary
/// without needing SELECT permission on every incident row that reporter ever
/// filed. Computing it client-side would have meant either loosening the RLS
/// policies or shipping an incomplete count that silently reads low.
class TrustScoreService {
  final _supabase = SupabaseService.instance;

  /// Cached per screen session. The score moves on the scale of days; fetching
  /// it once per incident card in a list of forty would be forty round trips
  /// for a number that will not have changed.
  final Map<String, TrustScore> _cache = {};

  /// Returns a neutral score rather than throwing.
  ///
  /// A failed lookup must never blank an incident card or block a queue — the
  /// annotation is an enhancement, and its absence should look like "nothing
  /// notable", which is also what a neutral score means.
  Future<TrustScore> forUser(String? userId) async {
    // Non-resident reports have no profile and therefore no history. That is
    // not suspicious; it is how the one-time flow works.
    if (userId == null) return const TrustScore.neutral();

    final cached = _cache[userId];
    if (cached != null) return cached;

    try {
      final data = await _supabase.client
          .rpc('get_trust_score', params: {'p_user_id': userId});

      final rows = data as List;
      if (rows.isEmpty) return const TrustScore.neutral();

      final score = TrustScore.fromJson(rows.first as Map<String, dynamic>);
      _cache[userId] = score;
      return score;
    } catch (_) {
      return const TrustScore.neutral();
    }
  }

  /// Drops the cache — call after a strike is applied, or the badge keeps
  /// showing the reporter's standing from before the decision.
  void invalidate(String userId) => _cache.remove(userId);

  void clear() => _cache.clear();
}
