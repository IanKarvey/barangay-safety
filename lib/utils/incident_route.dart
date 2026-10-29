import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Picks the correct incident screen for whoever is signed in.
///
/// This exists because notification taps used to push `/incident-manage`
/// unconditionally — the OFFICIAL screen — so a resident tapping "New update
/// on your report" landed on a page with Mark Resolved, Flag and Delete
/// controls for their own case. That is an authorisation hole, not a
/// navigation annoyance.
///
/// Officials manage; everyone else views.
String incidentRouteForCurrentUser(BuildContext context) {
  try {
    final user = context.read<AuthProvider>().user;
    return (user?.isOfficial ?? false) ? '/incident-manage' : '/report-detail';
  } catch (_) {
    // No provider in scope (e.g. a background isolate) — default to the
    // read-only screen. Failing closed is the right direction here.
    return '/report-detail';
  }
}
