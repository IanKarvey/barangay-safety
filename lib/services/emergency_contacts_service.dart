import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';

/// A number shown to a resident when help has not come ("last resort").
///
/// Lives in the `emergency_contacts` table so each barangay can keep its own
/// list. `barangayId == null` means a city-level number set by the SuperAdmin.
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.barangayId,
    required this.label,
    required this.category,
    required this.phoneNumber,
    this.sortOrder = 0,
    this.isActive = true,
    this.display,
  });

  final String id;
  final String? barangayId;
  final String label;

  /// police | hospital | rescue | fire | other
  final String category;
  final String phoneNumber;
  final int sortOrder;
  final bool isActive;

  /// How the number is written on the button, when that differs from what is
  /// dialled: "+63 900 000 0001" reads far more easily than "+639000000001".
  /// Saved numbers show as typed.
  final String? display;

  String get shown => display ?? phoneNumber;

  bool get isCityLevel => barangayId == null;

  /// What to hand to `tel:` — digits and a leading `+` only, so a number typed
  /// as "(043) 757-4168" still dials.
  String get dial {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    return cleaned;
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] as String,
        barangayId: json['barangay_id'] as String?,
        label: json['label'] as String,
        category: json['category'] as String? ?? 'other',
        phoneNumber: json['phone_number'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );

  EmergencyContact copyWith({
    String? label,
    String? category,
    String? phoneNumber,
    int? sortOrder,
    bool? isActive,
  }) =>
      EmergencyContact(
        id: id,
        barangayId: barangayId,
        label: label ?? this.label,
        category: category ?? this.category,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        sortOrder: sortOrder ?? this.sortOrder,
        isActive: isActive ?? this.isActive,
      );
}

/// The national emergency line.
const EmergencyContact kNational911 = EmergencyContact(
  id: 'builtin-911',
  barangayId: null,
  label: 'National Emergency (911)',
  category: 'other',
  phoneNumber: '911',
  sortOrder: 5,
);

/// What a resident is shown when no numbers can be read from the database — the
/// phone is offline, the table has not been set up, or nobody has saved any yet.
///
/// Police, Ambulance and Rescue first, then fire and 911: the same Lipa City
/// numbers the "call this agency" pop-up already uses (see [AppConfig]). A
/// last-resort screen that shows only "911" when real local numbers are known
/// is a worse screen, so these are built in rather than left to be configured.
///
/// Ambulance and Rescue are both the CDRRMO (Lipa Rescue); there is no separate
/// ambulance line here.
final List<EmergencyContact> kBuiltInEmergencyNumbers = [
  EmergencyContact(
    id: 'builtin-police',
    barangayId: null,
    label: 'Police (PNP Lipa)',
    category: 'police',
    phoneNumber: AppConfig.referralPolice.first.dial,
    display: AppConfig.referralPolice.first.display,
    sortOrder: 1,
  ),
  EmergencyContact(
    id: 'builtin-ambulance',
    barangayId: null,
    label: 'Ambulance (CDRRMO)',
    category: 'hospital',
    phoneNumber: AppConfig.referralMedical.first.dial,
    display: AppConfig.referralMedical.first.display,
    sortOrder: 2,
  ),
  EmergencyContact(
    id: 'builtin-rescue',
    barangayId: null,
    label: 'Rescue (CDRRMO Lipa)',
    category: 'rescue',
    phoneNumber: AppConfig.referralDisaster[1].dial,
    display: AppConfig.referralDisaster[1].display,
    sortOrder: 3,
  ),
  EmergencyContact(
    id: 'builtin-fire',
    barangayId: null,
    label: 'Fire (BFP Lipa)',
    category: 'fire',
    phoneNumber: AppConfig.referralFire.first.dial,
    display: AppConfig.referralFire.first.display,
    sortOrder: 4,
  ),
  kNational911,
];

/// True when [list] is the built-in set rather than numbers someone saved.
bool isBuiltInSet(List<EmergencyContact> list) =>
    list.isNotEmpty && list.every((c) => c.id.startsWith('builtin-'));

const List<String> kContactCategories = [
  'police',
  'hospital',
  'rescue',
  'fire',
  'other',
];

/// Which numbers a resident sees: the barangay's own active numbers; if it has
/// none, the city's; if there are none of those either, the built-in Lipa City
/// set (police, ambulance, rescue, fire, 911).
///
/// A pure function so the three-step fallback can be tested without a database.
List<EmergencyContact> resolveEmergencyNumbers({
  required List<EmergencyContact> barangay,
  required List<EmergencyContact> city,
}) {
  List<EmergencyContact> usable(List<EmergencyContact> l) =>
      l.where((c) => c.isActive && c.dial.isNotEmpty).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final own = usable(barangay);
  if (own.isNotEmpty) return own;
  final cityLevel = usable(city);
  if (cityLevel.isNotEmpty) return cityLevel;
  return kBuiltInEmergencyNumbers;
}

class EmergencyContactsService {
  final _db = SupabaseService.instance;

  /// The numbers to show a resident whose barangay is [barangayId]. Never
  /// throws and never returns an empty list: a failed lookup (no signal) still
  /// shows the built-in Lipa City numbers, because this runs at the moment
  /// someone needs help.
  Future<List<EmergencyContact>> numbersFor(String barangayId) async {
    try {
      // A resident with no barangay on file still gets the city-level list.
      final scope = barangayId.isEmpty
          ? 'barangay_id.is.null'
          : 'barangay_id.eq.$barangayId,barangay_id.is.null';
      final rows = await _db.client
          .from('emergency_contacts')
          .select()
          .eq('is_active', true)
          .or(scope)
          .order('sort_order');
      final all = (rows as List)
          .map((j) => EmergencyContact.fromJson(j as Map<String, dynamic>))
          .toList();
      return resolveEmergencyNumbers(
        barangay: all.where((c) => c.barangayId == barangayId).toList(),
        city: all.where((c) => c.isCityLevel).toList(),
      );
    } catch (e) {
      debugPrint('EmergencyContactsService: lookup failed — $e');
      return kBuiltInEmergencyNumbers;
    }
  }

  /// Every row an admin manages: their barangay's, or the city-level list when
  /// [barangayId] is null (SuperAdmin).
  Future<List<EmergencyContact>> manageList(String? barangayId) async {
    final q = _db.client.from('emergency_contacts').select();
    final rows = await (barangayId == null
            ? q.filter('barangay_id', 'is', null)
            : q.eq('barangay_id', barangayId))
        .order('sort_order');
    return (rows as List)
        .map((j) => EmergencyContact.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> add({
    required String? barangayId,
    required String label,
    required String category,
    required String phoneNumber,
    int sortOrder = 0,
  }) async {
    await _db.client.from('emergency_contacts').insert({
      'barangay_id': barangayId,
      'label': label,
      'category': category,
      'phone_number': phoneNumber,
      'sort_order': sortOrder,
    });
  }

  Future<void> update(EmergencyContact c) async {
    await _db.client.from('emergency_contacts').update({
      'label': c.label,
      'category': c.category,
      'phone_number': c.phoneNumber,
      'sort_order': c.sortOrder,
      'is_active': c.isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', c.id);
  }

  Future<void> delete(String id) async {
    await _db.client.from('emergency_contacts').delete().eq('id', id);
  }
}
