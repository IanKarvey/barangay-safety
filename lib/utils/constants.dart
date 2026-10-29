import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';

// ── App-wide color palette ──────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary — refined deep blue (Tailwind Blue-600/700)
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF93C5FD);   // Blue-300
  static const Color primaryDark = Color(0xFF1D4ED8);    // Blue-700
  static const Color accent = Color(0xFF10B981);         // Emerald-500

  // Backgrounds — slate-tinted whites (not harsh gray)
  static const Color background = Color(0xFFF8FAFC);     // Slate-50
  static const Color surface = Color(0xFFFFFFFF);        // Pure white
  static const Color surfaceSecondary = Color(0xFFF1F5F9); // Slate-100

  // Semantic — Tailwind-calibrated, professionally muted
  static const Color error = Color(0xFFDC2626);          // Red-600
  static const Color success = Color(0xFF16A34A);        // Green-600
  static const Color warning = Color(0xFFD97706);        // Amber-600

  // Text — Slate scale (blue-undertoned grays, not neutral gray)
  static const Color textPrimary = Color(0xFF0F172A);    // Slate-900
  static const Color textSecondary = Color(0xFF64748B);  // Slate-500
  static const Color textTertiary = Color(0xFFCBD5E1);   // Slate-300

  // Divider / separator
  static const Color divider = Color(0xFFE2E8F0);        // Slate-200

  // Severity
  static const Color severityCritical = Color(0xFFDC2626); // Red-600
  static const Color severityHigh = Color(0xFFEA580C);     // Orange-600
  static const Color severityMedium = Color(0xFFD97706);   // Amber-600
  static const Color severityLow = Color(0xFF16A34A);      // Green-600

  // Status
  static const Color statusPending = Color(0xFFD97706);    // Amber-600
  static const Color statusInProgress = Color(0xFF2563EB); // Blue-600
  static const Color statusResolved = Color(0xFF16A34A);   // Green-600
  static const Color statusFlagged = Color(0xFFDC2626);    // Red-600
}

// ── Text styles ─────────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'Poppins';

  static const TextStyle largeTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle heading1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
  );

  static const TextStyle heading3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: -0.1,
  );

  static const TextStyle subheadline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: -0.2,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0,
  );

  static const TextStyle footnote = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: -0.08,
  );
}

// ── Spacing ─────────────────────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// ── Border Radius ────────────────────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 28.0;
  static const double circular = 100.0;
}

// ── User Roles ──────────────────────────────────────────────────────────────
// `role` is the PERMISSION TIER — it decides what a user is allowed to do and
// is what every Supabase RLS policy keys off. For job title, see [UserPosition].
class UserRole {
  UserRole._();

  static const String superAdmin = 'superadmin';
  static const String admin = 'admin';
  static const String resident = 'resident';
  static const String nonResident = 'non_resident';
}

// ── Accepted identity documents (§8) ────────────────────────────────────────
// Which document a resident may present. The list is deliberately short and
// concrete — "any valid ID" sounds accommodating but leaves a reviewing
// official guessing whether a gym membership counts.
class IdType {
  IdType._();

  static const String nationalId = 'national_id';
  static const String postalId = 'postal_id';
  static const String driversLicense = 'drivers_license';
  static const String votersId = 'voters_id';
  static const String philhealth = 'philhealth';
  static const String umidSss = 'umid_sss';
  static const String barangayId = 'barangay_id';

  /// §8 student extension. Accepted specifically so students without an adult
  /// ID are not shut out of reporting emergencies — but it identifies a minor,
  /// so selecting it pulls in the guardian requirement.
  static const String schoolId = 'school_id';

  static const List<String> all = [
    nationalId,
    postalId,
    driversLicense,
    votersId,
    philhealth,
    umidSss,
    barangayId,
    schoolId,
  ];

  static String label(String? type) {
    switch (type) {
      case nationalId:
        return 'PhilSys National ID';
      case postalId:
        return 'Postal ID';
      case driversLicense:
        return "Driver's License";
      case votersId:
        return "Voter's ID";
      case philhealth:
        return 'PhilHealth ID';
      case umidSss:
        return 'UMID / SSS ID';
      case barangayId:
        return 'Barangay ID';
      case schoolId:
        return 'School ID';
      default:
        return 'Valid ID';
    }
  }
}

// ── Guardian relationship (§8 minors) ───────────────────────────────────────
// Stored as a stable key, never as the translated label the resident saw. The
// account may be created in Tagalog and reviewed in English.
class GuardianRelationship {
  GuardianRelationship._();

  static const String parent = 'parent';
  static const String grandparent = 'grandparent';
  static const String sibling = 'sibling';
  static const String legalGuardian = 'legal_guardian';
  static const String other = 'other';

  /// Translated label for a stored key. Unknown values pass through so a row
  /// written by an older build still renders something meaningful.
  static String label(AppStrings t, String? key) => switch (key) {
        parent => t.relParent,
        grandparent => t.relGrandparent,
        sibling => t.relSibling,
        legalGuardian => t.relLegalGuardian,
        other => t.relOther,
        _ => key ?? '',
      };
}

// ── Barangay Hall Positions ─────────────────────────────────────────────────
// `position` is the JOB TITLE within the barangay hall, held only by accounts
// on the admin/superadmin tier. Drives roster display, incident assignment and
// personnel analytics — it does NOT grant permissions on its own.
//
// There is deliberately no police or fire position: contacting PNP / BFP is the
// barangay hall's job, handled outside this system.
class UserPosition {
  UserPosition._();

  static const String secretary = 'secretary';
  static const String captain = 'captain';
  static const String tanod = 'tanod';
  static const String staff = 'staff';

  /// All assignable positions, in rank order.
  static const List<String> all = [secretary, captain, tanod, staff];

  /// Human-readable label for display.
  static String label(String? position) {
    switch (position) {
      case secretary:
        return 'Secretary';
      case captain:
        return 'Barangay Captain';
      case tanod:
        return 'Barangay Tanod';
      case staff:
        return 'Barangay Staff';
      default:
        return 'Unassigned';
    }
  }
}
