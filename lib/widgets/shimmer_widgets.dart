import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/constants.dart';

// ── Shared box helper ────────────────────────────────────────────────────────
Widget _shimmerBox({
  required double width,
  required double height,
  double radius = 6,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

// ── Single IncidentCard shimmer skeleton ─────────────────────────────────────
class IncidentCardShimmer extends StatelessWidget {
  const IncidentCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _shimmerBox(width: 130, height: 15),
                  const Spacer(),
                  _shimmerBox(width: 62, height: 22, radius: 20),
                ],
              ),
              const SizedBox(height: 10),
              _shimmerBox(width: double.infinity, height: 12),
              const SizedBox(height: 6),
              _shimmerBox(width: 200, height: 12),
              const SizedBox(height: 14),
              Row(
                children: [
                  _shimmerBox(width: 72, height: 20, radius: 20),
                  const Spacer(),
                  _shimmerBox(width: 90, height: 11),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shimmer list of N cards ──────────────────────────────────────────────────
class IncidentListShimmer extends StatelessWidget {
  final int count;
  const IncidentListShimmer({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      itemBuilder: (_, __) => const IncidentCardShimmer(),
    );
  }
}

// ── Notification list shimmer ────────────────────────────────────────────────
class NotificationListShimmer extends StatelessWidget {
  final int count;
  const NotificationListShimmer({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(width: 42, height: 42, radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 160, height: 13),
                    const SizedBox(height: 7),
                    _shimmerBox(width: double.infinity, height: 11),
                    const SizedBox(height: 5),
                    _shimmerBox(width: 200, height: 11),
                    const SizedBox(height: 8),
                    _shimmerBox(width: 70, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── User list shimmer ─────────────────────────────────────────────────────────
class UserListShimmer extends StatelessWidget {
  final int count;
  const UserListShimmer({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              _shimmerBox(width: 44, height: 44, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 130, height: 14),
                    const SizedBox(height: 7),
                    _shimmerBox(width: 90, height: 11),
                  ],
                ),
              ),
              _shimmerBox(width: 60, height: 24, radius: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Analytics shimmer ─────────────────────────────────────────────────────────
class AnalyticsShimmer extends StatelessWidget {
  const AnalyticsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stat row
            Row(
              children: [
                Expanded(child: _statCardBox()),
                const SizedBox(width: 12),
                Expanded(child: _statCardBox()),
                const SizedBox(width: 12),
                Expanded(child: _statCardBox()),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statCardBox()),
                const SizedBox(width: 12),
                Expanded(child: _statCardBox()),
                const SizedBox(width: 12),
                Expanded(child: _statCardBox()),
              ],
            ),
            const SizedBox(height: 20),
            // Chart placeholder
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
            const SizedBox(height: 20),
            // Second chart
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
            const SizedBox(height: 20),
            // List rows
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      _shimmerBox(width: 32, height: 32, radius: 16),
                      const SizedBox(width: 12),
                      Expanded(child: _shimmerBox(width: double.infinity, height: 13)),
                      const SizedBox(width: 12),
                      _shimmerBox(width: 40, height: 13),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCardBox() => Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      );
}

// ── Audit log shimmer ─────────────────────────────────────────────────────────
class AuditLogShimmer extends StatelessWidget {
  final int count;
  const AuditLogShimmer({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(width: 36, height: 36, radius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(width: 180, height: 13),
                    const SizedBox(height: 6),
                    _shimmerBox(width: double.infinity, height: 11),
                    const SizedBox(height: 5),
                    _shimmerBox(width: 100, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full-page shimmer for ReportDetailScreen ─────────────────────────────────
class ReportDetailShimmer extends StatelessWidget {
  const ReportDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header block
            Container(
              width: double.infinity,
              color: const Color(0xFFF5F7FA),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _shimmerBox(width: 72, height: 26, radius: 20),
                      const SizedBox(width: 8),
                      _shimmerBox(width: 84, height: 26, radius: 20),
                      const Spacer(),
                      _shimmerBox(width: 64, height: 13),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _shimmerBox(width: 210, height: 22),
                  const SizedBox(height: 8),
                  _shimmerBox(width: 140, height: 13),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(width: 110, height: 18),
                  const SizedBox(height: 10),
                  _shimmerBox(width: double.infinity, height: 13),
                  const SizedBox(height: 6),
                  _shimmerBox(width: double.infinity, height: 13),
                  const SizedBox(height: 6),
                  _shimmerBox(width: 220, height: 13),
                  const SizedBox(height: 24),
                  _shimmerBox(width: 80, height: 18),
                  const SizedBox(height: 10),
                  // Map placeholder
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _shimmerBox(width: 180, height: 11),
                  const SizedBox(height: 24),
                  _shimmerBox(width: 120, height: 18),
                  const SizedBox(height: 10),
                  // Photo row
                  Row(
                    children: [
                      _shimmerBox(width: 120, height: 120, radius: AppRadius.sm),
                      const SizedBox(width: 8),
                      _shimmerBox(width: 120, height: 120, radius: AppRadius.sm),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _shimmerBox(width: 80, height: 18),
                  const SizedBox(height: 12),
                  // Timeline
                  Row(children: [
                    _shimmerBox(width: 24, height: 24, radius: 12),
                    const SizedBox(width: 12),
                    _shimmerBox(width: 90, height: 13),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _shimmerBox(width: 24, height: 24, radius: 12),
                    const SizedBox(width: 12),
                    _shimmerBox(width: 110, height: 13),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
