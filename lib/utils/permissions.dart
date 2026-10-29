import '../models/incident_model.dart';
import '../models/user_model.dart';
import 'constants.dart';

/// A single thing a barangay official can attempt to do.
///
/// Capabilities exist so screens ask "may this person do X?" instead of
/// re-deriving rules from role and position at each call site — which is how
/// the same check ends up subtly different in three places.
enum Capability {
  /// Secretary's gate: confirm a report is real before anyone is dispatched.
  verifyReport,

  /// Put a named official in charge of a case.
  assignOfficial,

  /// Send responders — the point after which the reporter can no longer cancel.
  dispatchResponders,

  /// Confirm arrival at the scene.
  markOnScene,

  /// Close a case.
  resolveIncident,

  /// Undo a stage. Separate from the forward actions: correcting a mistake and
  /// driving the case forward are different levels of trust.
  stepBackStage,

  /// Mark a report fraudulent. Carries a strike against the reporter and can
  /// suspend their account, so it sits highest.
  flagFalseReport,

  /// Approve a resident's account.
  verifyUser,

  /// Lock or unlock an account.
  lockUser,

  /// Correct another account's name, phone or address.
  ///
  /// Separate from [verifyUser]: approving an identity someone else asserted
  /// and rewriting it are different levels of trust. A wrong phone number here
  /// is a responder calling the wrong house during an emergency.
  editUserDetails,

  /// Grant or remove a barangay hall job title.
  managePositions,

  /// Alert the entire barangay hall at once (§14). Interrupts everyone, so it
  /// sits with the people accountable for that call.
  raiseFullBlast,

  /// Act on many cases at once. Separate from resolving a single case: a
  /// mistake here is multiplied by however many were selected.
  bulkAction,

  /// Permanently remove a report. RLS already restricts this to superadmins,
  /// so anyone else is offered a button that cannot work.
  deleteIncident,
}

/// Whether [user] may perform [capability].
///
/// ## Relationship to SD-2 and to RLS
///
/// Per **SD-2**, `role` remains the permission tier every RLS policy keys off;
/// `position` is a job title. This adds a second, finer layer *in the app* on
/// top of that tier — it narrows what an `admin` sees, and never widens what
/// the database already allows.
///
/// **This is not a security boundary.** It shapes the interface so an official
/// isn't handed controls that aren't their job; it cannot stop a modified
/// client. Anything that must actually be prevented belongs in an RLS policy.
/// Enforcing these server-side would mean extending the policies to read
/// `position` — worth doing, not done here.
///
/// ## Why an unset position means full access
///
/// Most existing accounts have `position = NULL`. Treating that as "no
/// permissions" would lock every current official out of their own dashboard
/// the moment this shipped. An account with no job title keeps the behaviour it
/// has always had; restrictions apply only once someone is deliberately
/// assigned a position.
bool can(UserModel? user, Capability capability) {
  if (user == null) return false;

  // Superadmins are city-wide administrators — position never constrains them.
  if (user.isSuperAdmin) return true;

  // Residents and non-residents hold none of these capabilities. The guard
  // matters: notification deep links have previously landed residents on
  // official screens (§16.5).
  if (!user.isOfficial) return false;

  // Deleting is superadmin-only in the RLS policy
  // ("Superadmin can delete incidents", schema.sql). Offering it to an admin
  // means offering a button that fails at the database — worse than not
  // offering it, because the failure looks like a bug rather than a rule.
  if (capability == Capability.deleteIncident) return false;

  // Backwards compatibility — see the doc comment above.
  if (!user.hasPosition) return true;

  return switch (user.position) {
    // The Secretary runs the case desk day to day and, per the barangay's own
    // working arrangement, carries the same authority as the Captain — the
    // Captain is frequently out, and a desk that cannot act without them
    // stalls live incidents.
    'secretary' => true,

    // Head of the barangay: full authority.
    'captain' => true,

    // Field responder. Acts on cases already dispatched to them; does not
    // decide which reports are genuine or when a case is closed.
    'tanod' => switch (capability) {
        Capability.markOnScene => true,
        _ => false,
      },

    // Administrative support: reads and answers, decides nothing.
    'staff' => false,

    // Unrecognised job title — fall back to the permissive default rather than
    // locking someone out over a typo or a position added later in SQL.
    _ => true,
  };
}

/// Seniority of a barangay hall position, for deciding who may re-rank whom.
///
/// Higher is more senior. This is **only** used for the structural guards
/// below — it deliberately does NOT feed [can], because the owner's decision
/// stands: a Secretary carries the same *operational* authority as the Captain
/// (verify, assign, dispatch, resolve, full-blast). What seniority governs is
/// who may rewrite the hierarchy itself, which is a different question.
int positionRank(String? position) => switch (position) {
      UserPosition.captain => 3,
      UserPosition.secretary => 2,
      UserPosition.tanod => 1,
      UserPosition.staff => 0,

      // No position is the TOP rank, not the bottom, and that is not a typo.
      // `can()` grants an official with no title full access for backwards
      // compatibility, so clearing someone's position is effectively a
      // promotion to Captain-level power. Ranking null below Captain would let
      // a Secretary "remove" their own title and escalate.
      null => 3,

      // Unknown title — same permissive fallback `can()` uses, so a typo in
      // SQL cannot silently create an account nobody is allowed to fix.
      _ => 3,
    };

/// Seniority of an account, for the structural guards.
///
/// Residents and non-residents sit below every official so they can be
/// appointed; a superadmin sits above everyone so they can always repair a
/// barangay that has locked itself up.
int accountRank(UserModel? user) {
  if (user == null) return -1;
  if (user.isSuperAdmin) return 100;
  if (!user.isOfficial) return -1;
  return positionRank(user.position);
}

/// Whether [actor] may change [target]'s position — and, when [newPosition] is
/// supplied, whether they may set it to that specific value.
///
/// ## The escalation this closes
///
/// Before 2026-08-18 any account with [Capability.managePositions] could assign
/// any position to anyone, themselves included. In practice that meant a single
/// Secretary could:
///
///   * mint unlimited Captains and Secretaries, and
///   * set the actual Captain to `staff`, which is read-only — leaving the
///     Captain unable to undo it, because `staff` cannot manage positions.
///     Only a superadmin could restore them.
///
/// Two rules close it, and they apply to the actor's own account exactly as
/// they apply to anyone else's:
///
///   1. You may not act on someone who ranks **at or above** you. (You may
///      always act on yourself, subject to rule 2.)
///   2. You may not grant a position **above your own rank** — so a Secretary
///      cannot promote anyone, including themselves, to Captain.
///
/// Superadmins are exempt: someone has to be able to fix a barangay whose
/// Captain account was lost.
bool canSetPositionOf(
  UserModel? actor,
  UserModel target, {
  String? newPosition,
  bool checkNewPosition = false,
}) {
  if (actor == null) return false;
  if (!can(actor, Capability.managePositions)) return false;
  if (actor.isSuperAdmin) return true;

  final actorRank = accountRank(actor);
  final isSelf = actor.id == target.id;

  // Rule 1 — peers and superiors are off limits. Self is exempt here so an
  // official can always step themselves down.
  if (!isSelf && accountRank(target) >= actorRank) return false;

  // Rule 2 — cannot hand out authority you do not hold. Applies to self too,
  // which is what stops a Secretary promoting themselves to Captain.
  if (checkNewPosition && positionRank(newPosition) > actorRank) return false;

  return true;
}

/// The positions [actor] is allowed to hand out.
///
/// Used to build the picker, so an option that would be rejected is never
/// offered — a disabled-looking control the user cannot explain is worse than
/// an absent one here, because the rule is about rank, not about this target.
List<String> assignablePositions(UserModel? actor) {
  if (actor == null) return const [];

  // Someone who cannot manage positions at all gets an empty list, not a
  // rank-filtered one. Without this the helper returned ['tanod', 'staff'] for
  // a Tanod — harmless only because no Tanod can reach the picker today, which
  // is exactly the kind of assumption a future caller would inherit silently.
  if (!can(actor, Capability.managePositions)) return const [];

  if (actor.isSuperAdmin) return UserPosition.all;
  final rank = accountRank(actor);
  return UserPosition.all.where((p) => positionRank(p) <= rank).toList();
}

/// Whether [actor] may lock or unlock [target].
///
/// Same rank rule as positions: locking the Captain's account disables them
/// just as effectively as demoting them to staff, so closing one door and
/// leaving the other open would not be a fix.
///
/// Self-locking is refused outright — an official who locks themselves out
/// cannot undo it, and there is no legitimate reason to.
bool canLockAccount(UserModel? actor, UserModel target) {
  if (actor == null) return false;
  if (!can(actor, Capability.lockUser)) return false;
  if (actor.id == target.id) return false;
  if (actor.isSuperAdmin) return true;
  return accountRank(target) < accountRank(actor);
}

/// Whether [user] should see every incident in their barangay, or only the
/// ones assigned to them.
///
/// A Tanod is a field responder: they act on the case they were sent to. Being
/// shown the whole barangay's caseload invites them to open — and act on —
/// incidents that are someone else's, which is how two responders end up at
/// the same scene and none at another.
///
/// Anyone without a position keeps the old behaviour, for the same
/// backwards-compatibility reason as [can].
bool seesAllIncidents(UserModel? user) {
  if (user == null) return false;
  if (user.isSuperAdmin) return true;
  if (!user.isOfficial) return false;
  if (!user.hasPosition) return true;
  return user.position != 'tanod' && user.position != 'staff';
}

/// Whether [user] may VOLUNTEER: press "I'm responding" on a report nobody has
/// taken. Secretary, Captain and Tanod can; front-desk staff cannot (they answer
/// and read, they are not sent to a scene), and the database refuses them too.
///
/// Late at night the Captain and the tanods are the people on call, so a tanod
/// has to be able to take a report — which means being able to SEE it.
bool canVolunteer(UserModel? user) {
  if (user == null || !user.isOfficial) return false;
  return user.position != 'staff';
}

/// A report that still needs somebody to go: nobody is assigned and it has not
/// been resolved, closed or set aside.
bool isOpenForVolunteers(IncidentModel incident) =>
    incident.assignedTo == null &&
    (incident.status == 'pending' || incident.status == 'verified');

/// The incidents [user] should be shown.
///
/// A Secretary, Captain or superadmin sees them all. A Tanod sees the cases
/// assigned to them AND the reports open for volunteers — otherwise there would
/// be nothing for them to volunteer for. Front-desk staff see only what is
/// assigned to them.
///
/// **This filters the view, not the record.** Nothing is deleted or hidden from
/// the database — the Secretary, Captain and superadmin still see the complete
/// history, and the audit log is untouched. A Tanod simply isn't handed cases
/// that are someone else's.
List<IncidentModel> visibleIncidents(
  UserModel? user,
  List<IncidentModel> incidents,
) {
  if (seesAllIncidents(user)) return incidents;
  if (user == null) return const [];
  final volunteer = canVolunteer(user);
  return incidents
      .where((i) =>
          i.assignedTo == user.id || (volunteer && isOpenForVolunteers(i)))
      .toList();
}

/// Whether [user] may open this specific incident.
///
/// Backs the route guard on the manage screen, so a stale notification tap or
/// a deep link cannot put a responder inside a case that is someone else's.
bool canOpenIncident(UserModel? user, IncidentModel incident) =>
    seesAllIncidents(user) ||
    (user != null &&
        (incident.assignedTo == user.id ||
            (canVolunteer(user) && isOpenForVolunteers(incident))));

/// Short explanation for why a control is disabled.
///
/// Shown on the control itself. A greyed-out button with no reason reads as a
/// bug; naming the position responsible tells the user who to go to.
String? capabilityBlockedReason(UserModel? user, Capability capability) {
  if (can(user, capability)) return null;

  final owner = switch (capability) {
    Capability.flagFalseReport ||
    Capability.lockUser ||
    Capability.managePositions ||
    Capability.raiseFullBlast =>
      'the Secretary or Barangay Captain',
    Capability.verifyReport ||
    Capability.assignOfficial ||
    Capability.dispatchResponders ||
    Capability.resolveIncident ||
    Capability.stepBackStage =>
      'the Secretary or Captain',
    Capability.markOnScene => 'an assigned responder',
    Capability.bulkAction => 'the Secretary or Captain',
    Capability.deleteIncident => 'a city administrator',
    Capability.verifyUser => 'the Secretary or Captain',
    Capability.editUserDetails => 'the Secretary or Captain',
  };

  return 'Only $owner can do this.';
}
