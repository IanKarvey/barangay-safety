import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:uuid/uuid.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/offline_queue_service.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../services/integrity_service.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/response_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/animated_button.dart';
import '../../utils/severity.dart';
import '../../widgets/app_text.dart';
import '../../widgets/lgu_referral_sheet.dart';
import '../../services/referral_service.dart';
import '../../utils/lgu_routing.dart';

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _locationService = LocationService();
  final _imagePicker = ImagePicker();
  late final PageController _pageController;

  String? _selectedCategory;

  /// Derived from the category, never chosen.
  ///
  /// Was a four-option picker the reporter set themselves, and briefly an AI
  /// suggestion layered on top of it. Both produced the same problem: two
  /// people reporting one fire filed it at two different levels, and officials
  /// stopped trusting the number. Choosing "Fire" now *is* choosing Critical.
  int get _severityLevel => Severity.forCategory(_selectedCategory);
  double? _latitude;

  /// The raw GPS fix, kept so §5 can read `isMocked` at submission time.
  /// Only set from an actual device fix — a pin dragged on the map is not a
  /// GPS reading and carries no mock flag to report.
  Position? _lastPosition;
  double? _longitude;
  String? _detectedAddress;
  final List<File> _photos = [];

  /// §4.1 — advisory only. Never applied automatically; the reporter taps it.
  final List<File> _videos = [];
  bool _isGettingLocation = false;
  bool _isSubmitting = false;
  bool _isSuccess = false;
  bool _isOutsideCity = false;
  double _outsideCityDistanceKm = 0;
  String _submittedCategory = '';
  int _currentStep = 0;

  static const _highSeverityCategories = {
    'Fire',
    'Physical Assault',
    'Drug-Related',
    'Domestic Violence',
    'Vehicular Accident',
    'Medical Emergency',
  };

  static const _categoryColors = [
    Color(0xFFEF4444), // Theft / Robbery
    Color(0xFFDC2626), // Physical Assault
    Color(0xFFF59E0B), // Vehicular Accident
    Color(0xFFEA580C), // Fire
    Color(0xFF3B82F6), // Flooding
    Color(0xFF8B5CF6), // Noise Disturbance
    Color(0xFF14B8A6), // Vandalism
    Color(0xFF0EA5E9), // Suspicious Activity
    Color(0xFF7C3AED), // Drug-Related
    Color(0xFFEC4899), // Domestic Violence
    Color(0xFF6366F1), // Public Disturbance
    Color(0xFF10B981), // Medical Emergency
    Color(0xFF6B7280), // Other
  ];

  // Resolved per build rather than held const — these change with language.
  List<String> _stepTitles(AppStrings t) =>
      [t.incidentDetails, t.locationEvidence, t.reviewSubmit];
  List<String> _stepSubtitles(AppStrings t) =>
      [t.whatHappened, t.whereAndProof, t.confirmYourReport];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _getLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _landmarkController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition();
      // Guarded: acquiring a GPS fix takes seconds, and a user who
      // backs out of the screen while waiting leaves this callback
      // running against a disposed State. setState() then throws
      // "setState() called after dispose()".
      if (!mounted) return;
      final distKm = lipaCityDistanceKm(position.latitude, position.longitude);
      final withinCity = distKm <= 20.0;
      setState(() {
        _lastPosition = position;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
        _isOutsideCity = !withinCity;
        _outsideCityDistanceKm = distKm;
      });
      if (!withinCity && mounted) {
        _showOutsideLipaCitySheet(distKm);
        return;
      }
      _reverseGeocode(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingLocation = false);
      showErrorSnackbar(context, e.toString());
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ];
        setState(() {
          _detectedAddress = parts.isNotEmpty ? parts.join(', ') : null;
        });
      }
    } catch (e) {
      // Reverse geocoding is a convenience — the GPS fix is what the report
      // actually needs, and it is already captured. Logged, not surfaced.
      debugPrint('ReportForm: reverse geocode failed — $e');
    }
  }

  Future<bool> _isBlackPhoto(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return false;

      final pixels = byteData.buffer.asUint8List();
      double totalLuminance = 0;
      int sampleCount = 0;
      // Sample every 400th pixel (4 bytes each: RGBA) for performance
      for (int i = 0; i < pixels.length - 3; i += 400 * 4) {
        totalLuminance += 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2];
        sampleCount++;
      }
      if (sampleCount == 0) return false;
      return (totalLuminance / sampleCount) < 20.0; // below 20/255 = essentially black
    } catch (_) {
      return false; // analysis failure → allow the photo through
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked != null) {
        final file = File(picked.path);
        if (await _isBlackPhoto(file)) {
          if (mounted) _showBlackPhotoSheet(source);
          return;
        }
        setState(() => _photos.add(file));
        // Classify the first photo only — later ones are usually more angles
        // on the same scene, and each call costs money.
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to pick image');
    }
  }

  void _showBlackPhotoSheet(ImageSource source) {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BlackPhotoSheet(
        onRetake: () {
          Navigator.pop(ctx);
          _pickPhoto(source);
        },
      ),
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      // Android can destroy the host activity while the camera is in the
      // foreground on a low-memory device, so this State may be gone by the
      // time the picker returns.
      if (picked != null && mounted) {
        setState(() => _videos.add(File(picked.path)));
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to pick video');
    }
  }

  void _showPhotoRequiredSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PhotoRequiredSheet(
        onAddPhoto: () {
          Navigator.pop(ctx);
          _pickPhoto(ImageSource.camera);
        },
      ),
    );
  }

  /// Explains that the location is out of coverage, then leaves the form.
  ///
  /// Leaving is the point. Every way forward from here is blocked — Next
  /// refuses, submit refuses — so staying on the form means sitting on a
  /// screen that cannot do anything, which is what "stuck" meant in the
  /// 2026-09-15 report. The home screen now gates this before navigating, so
  /// this path only runs when that gate's GPS lookup timed out and the form
  /// opened anyway.
  ///
  /// See showOutsideCitySheet in helpers.dart for why the sheet scrolls.
  Future<void> _showOutsideLipaCitySheet(double distanceKm) async {
    HapticFeedback.heavyImpact();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (ctx) => SingleChildScrollView(
        child: _OutsideCitySheet(distanceKm: distanceKm),
      ),
    );

    // Back to where they came from, rather than a form they cannot submit.
    if (mounted && _isOutsideCity && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showGpsRequiredSheet() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _GpsRequiredSheet(
        onEnableLocation: () async {
          Navigator.pop(ctx);
          await openAppSettings();
          if (mounted) _getLocation();
        },
        onCallHotline: () {
          Navigator.pop(ctx);
          launchUrl(Uri.parse('tel:${AppConfig.emergencyHotline}'));
        },
      ),
    );
  }

  void _goNext() {
    if (_currentStep == 0) {
      if (_selectedCategory == null) {
        showErrorSnackbar(context, 'Please select a category');
        return;
      }
      if (_descriptionController.text.trim().isEmpty) {
        showErrorSnackbar(context, 'Please describe the incident');
        return;
      }
    }
    if (_currentStep == 1) {
      if (_highSeverityCategories.contains(_selectedCategory) && _photos.isEmpty) {
        _showPhotoRequiredSheet();
        return;
      }
      if (_isOutsideCity) {
        _showOutsideLipaCitySheet(_outsideCityDistanceKm);
        return;
      }
      if (_latitude == null || _longitude == null) {
        _showGpsRequiredSheet();
        return;
      }
    }
    if (_currentStep < 2) {
      final next = _currentStep + 1;
      setState(() => _currentStep = next);
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _submit();
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      final prev = _currentStep - 1;
      setState(() => _currentStep = prev);
      _pageController.animateToPage(
        prev,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    if (_selectedCategory == null) {
      showErrorSnackbar(context, 'Please select an incident category');
      return;
    }
    if (_latitude == null || _longitude == null) {
      showErrorSnackbar(
          context, 'GPS location is required. Please enable location services.');
      return;
    }

    final user = context.read<AuthProvider>().user!;

    final barangayId = user.barangayId;
    if (barangayId == null) {
      showErrorSnackbar(context,
          'Your account has no barangay assigned yet. Please contact your barangay hall before submitting a report.');
      return;
    }

    if (user.isLocked) {
      showErrorSnackbar(context,
          'Your account is permanently locked. Visit the barangay hall to appeal.');
      return;
    }
    if (user.isActivelySuspended) {
      final days = user.strikeExpiresAt!.difference(DateTime.now()).inDays + 1;
      showErrorSnackbar(context,
          'You are suspended from filing reports for $days more day${days == 1 ? "" : "s"} due to a false report.');
      return;
    }

    setState(() => _isSubmitting = true);

    final isOnline = await ConnectivityService.isOnline();
    if (!isOnline) {
      await OfflineQueueService().enqueue(QueuedReport(
        localId: const Uuid().v4(),
        reporterId: user.id,
        barangayId: barangayId,
        category: _selectedCategory!,
        description: _descriptionController.text.trim(),
        severityLevel: _severityLevel,
        latitude: _latitude!,
        longitude: _longitude!,
        address: _detectedAddress,
        landmark: _landmarkController.text.trim().isNotEmpty
            ? _landmarkController.text.trim()
            : null,
        photoPaths: _photos.map((f) => f.path).toList(),
        videoPaths: _videos.map((f) => f.path).toList(),
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showSuccessSnackbar(context, 'Saved offline — will submit when back online');
      Navigator.pop(context);
      return;
    }

    // §5 — collected at submission because it cannot be reconstructed later.
    // Never blocks: a failed check returns "no concern" rather than stopping an
    // emergency report. See IntegrityService.
    final integrity = await IntegrityService().check(_lastPosition);

    if (!mounted) return;
    final result = await context.read<IncidentProvider>().createIncident(
      reporterId: user.id,
      barangayId: user.barangayId!,
      category: _selectedCategory!,
      description: _descriptionController.text.trim(),
      severityLevel: _severityLevel,
      latitude: _latitude!,
      longitude: _longitude!,
      address: _detectedAddress,
      landmark: _landmarkController.text.trim().isNotEmpty
          ? _landmarkController.text.trim()
          : null,
      photos: _photos,
      videos: _videos,
      reportedViaVpn: integrity.viaVpn,
      locationMocked: integrity.locationMocked,
    );

    // Photo and video uploads run inside createIncident, so this await can
    // last tens of seconds on a poor connection — ample time for the reporter
    // to leave the screen.
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _isSubmitting = false;
        _isSuccess = true;
        _submittedCategory = _selectedCategory!;
      });
      await Future.delayed(const Duration(milliseconds: 2800));
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _isSubmitting = false);
      final error = context.read<IncidentProvider>().error;
      showErrorSnackbar(context, error ?? 'Failed to submit report');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.fileIncidentReport),
        actions: [
          // "?" opens the tutorial at the step the person is on, so someone who
          // forgets what to do halfway through the form can ask without losing
          // what they typed (the form stays open underneath).
          IconButton(
            tooltip: context.rs.helpHere,
            iconSize: 30,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => Navigator.pushNamed(
              context,
              '/report-tutorial',
              arguments: {
                'source': 'form_help',
                // Form step 0 is "what happened", 1 is location + evidence,
                // 2 is review and submit.
                'step': switch (_currentStep) { 0 => 1, 1 => 2, _ => 4 },
              },
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              const OfflineBanner(),

              // ── Animated progress bar ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _buildProgressBar(),
              ),

              // ── Step header with animated title ───────────────────────
              _buildStepHeader(),

              const SizedBox(height: 8),

              // ── Step content via PageView ──────────────────────────────
              Expanded(
                child: Form(
                  key: _formKey,
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStep0Content(),
                      _buildStep1Content(),
                      _buildStep2Content(),
                    ],
                  ),
                ),
              ),

              // ── Navigation buttons ─────────────────────────────────────
              _buildNavButtons(),
            ],
          ),
          if (_isSuccess) _ReportSuccessOverlay(category: _submittedCategory),
        ],
      ),
    );
  }

  // ── Progress bar: 3 animated segments ───────────────────────────────────────
  Widget _buildProgressBar() {
    return Row(
      children: List.generate(3, (i) {
        final done = i < _currentStep;
        final active = i == _currentStep;
        return Expanded(
          child: Row(
            children: [
              // Circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: active ? 28 : 22,
                height: active ? 28 : 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done || active) ? AppColors.primary : AppColors.divider,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            key: ValueKey('done'), size: 13, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            key: ValueKey('num_$i'),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: active ? 13 : 11,
                              fontWeight: FontWeight.w700,
                              color: (done || active)
                                  ? Colors.white
                                  : AppColors.textTertiary,
                            ),
                          ),
                  ),
                ),
              ),
              // Connector line (not after last)
              if (i < 2)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (done || active) ? AppColors.primary : AppColors.divider,
                          done ? AppColors.primary : AppColors.divider,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ── Step title + subtitle with animated switcher ─────────────────────────────
  Widget _buildStepHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.stepOf(_currentStep + 1, 3),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
                child: child,
              ),
            ),
            child: Align(
              key: ValueKey(_currentStep),
              alignment: Alignment.centerLeft,
              child: AppText(
                _stepTitles(context.s)[_currentStep],
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Align(
              key: ValueKey('sub_$_currentStep'),
              alignment: Alignment.centerLeft,
              child: Text(
                _stepSubtitles(context.s)[_currentStep],
                style: AppTextStyles.footnote,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Nav buttons row ──────────────────────────────────────────────────────────
  Widget _buildNavButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: AnimatedButton(
                label: _currentStep == 2
                    ? context.s.submitReport
                    : context.s.continueLabel,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _goNext,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _goBack,
                child: Text(
                    _currentStep == 0 ? context.s.cancel : context.s.back),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 0: Incident Details ─────────────────────────────────────────────────
  Widget _buildStep0Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category chip grid
          Row(
            children: [
              Flexible(child: AppText(context.s.incidentCategory, style: AppTextStyles.heading3)),
              const Spacer(),
              if (_selectedCategory != null)
                GestureDetector(
                  onTap: () => setState(() => _selectedCategory = null),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedCategory == null
                ? Align(
                    key: const ValueKey('hint'),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.s.tapToSelectCategory,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  )
                : Align(
                    key: ValueKey('sel'),
                    alignment: Alignment.centerLeft,
                    child: AppText(
                      _selectedCategory!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConfig.incidentCategories
                .asMap()
                .entries
                .map((e) => _buildCategoryChip(e.value, e.key))
                .toList(),
          ),
          const SizedBox(height: 16),

          // Description
          TextFormField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => validateRequired(v, 'Description'),
            decoration: InputDecoration(
              labelText: context.s.description,
              hintText: context.s.describeIncidentHint,
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 60),
                child: Icon(Icons.description_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Threat level — set by the category, not by the reporter ──
          //
          // Rendered, not chosen. There is no tap target here on purpose: a
          // person filing an emergency should not also be triaging it, and a
          // level that can be argued with is a level officials cannot sort by.
          AppText(context.s.severity, style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          _buildAutoSeverityCard(),
        ],
      ),
    );
  }

  /// Shows the level the chosen category carries.
  Widget _buildAutoSeverityCard() {
    final category = _selectedCategory;

    if (category == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          context.s.severityPickCategoryFirst,
          style: AppTextStyles.caption,
        ),
      );
    }

    final level = Severity.forCategory(category);
    final color = severityColor(level);
    final label = severityLabelFor(context.s, level);
    final desc = severityDescriptionFor(context.s, level);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(severityIcon(level), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        'Level $level: $label',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(Icons.lock_outline_rounded,
                        size: 15, color: color.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 2),
                AppText(desc, style: AppTextStyles.caption),
                const SizedBox(height: 6),
                Text(
                  context.s.severityAutoSetNote,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }

  // The AI severity suggestion card lived here until 2026-08-25.
  //
  // Removed because severity is no longer a value anyone can set: the incident
  // category carries it (see lib/utils/severity.dart), so there is nothing for
  // a suggestion to change. Offering one would show the reporter a control
  // that does nothing.
  //
  // SeverityAiService and the deployed `suggest-severity` Edge Function are
  // left in place — they are unwired from this form, not deleted.

  /// Selecting a category either starts a report or, for anything beyond the
  /// barangay, shows the "call this number" pop-up and starts nothing.
  ///
  /// Checked here, at the tap, rather than at submit: someone describing a fire
  /// should find out *before* they photograph it and write it up that this
  /// report will not reach anyone able to put it out. The category is not
  /// selected, so the form can never be submitted for it.
  Future<void> _onCategoryTapped(String cat) async {
    final referral = LguRouting.referralFor(cat);
    if (referral == null) {
      setState(() => _selectedCategory = cat);
      return;
    }

    // Only a BLOCKED report is logged as a referral. An advisory one (domestic
    // violence, drugs) goes on to become a real incident, and logging it here as
    // well would count the same event twice.
    if (!referral.allowsReporting) {
      final user = context.read<AuthProvider>().user;
      // Fire and forget — bookkeeping must never delay or break the pop-up.
      unawaited(ReferralService().log(
        category: cat,
        agency: referral.agency.name,
        barangayId: user?.barangayId,
        latitude: _latitude,
        longitude: _longitude,
      ));
    }

    final proceed =
        await showLguReferralSheet(context, category: cat, referral: referral);

    // Advisory categories: the person chose to report to the barangay anyway.
    // Closing the pop-up any other way leaves nothing selected, so a report is
    // only ever started by saying so.
    if (proceed == true && mounted) {
      setState(() => _selectedCategory = cat);
    }
  }

  Widget _buildCategoryChip(String cat, int index) {
    final selected = _selectedCategory == cat;
    final color = _categoryColors[index % _categoryColors.length];

    return GestureDetector(
      onTap: () => _onCategoryTapped(cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.32),
            width: selected ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? color : AppColors.textSecondary,
              ),
              // `cat` stays the canonical English value used for state and
              // storage — only what's drawn is translated.
              child: Text(categoryLabel(context.s, cat)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Location & Evidence ──────────────────────────────────────────────
  Widget _buildStep1Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(context.s.gpsLocation, style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          if (_isGettingLocation)
            _LocationShimmer()
          else if (_latitude != null && _longitude != null) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: LocationPickerMap(
                initialPosition: LatLng(_latitude!, _longitude!),
                onLocationSelected: (pos) {
                  setState(() {
                    _latitude = pos.latitude;
                    _longitude = pos.longitude;
                  });
                  _reverseGeocode(pos.latitude, pos.longitude);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Expanded(
                  child: AppText(
                    'Lat: ${_latitude!.toStringAsFixed(6)}, Lng: ${_longitude!.toStringAsFixed(6)}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.success),
                  ),
                ),
                TextButton.icon(
                  onPressed: _getLocation,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(context.s.refresh, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Text(
              'Tap the map to adjust the pin location',
              style: AppTextStyles.caption,
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_off, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.s.unableToGetLocation)),
                  TextButton(
                    onPressed: _getLocation,
                    child: Text(context.s.retry),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          if (_detectedAddress != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detected Address',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AppText(_detectedAddress!, style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _landmarkController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.s.nearbyLandmark,
              prefixIcon: const Icon(Icons.near_me_outlined),
              hintText: context.s.landmarkHint,
            ),
          ),
          const SizedBox(height: 20),

          AppText(context.s.photosOptional, style: AppTextStyles.heading3),
          const Text(
            'Up to 5 photos as evidence',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._photos.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        entry.value,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.removeAt(entry.key)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              if (_photos.length < 5)
                GestureDetector(
                  onTap: () => _pickPhoto(ImageSource.camera),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.background,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, color: AppColors.textSecondary),
                        SizedBox(height: 2),
                        Text(
                          'Photo',
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          AppText(context.s.videosOptional, style: AppTextStyles.heading3),
          const Text(
            'Up to 2 videos, max 60 seconds each',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._videos.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: const Color(0xFF1A1A2E)),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _videoFileSize(entry.value),
                                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                                ),
                              ],
                            ),
                            Positioned(
                              bottom: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'VID',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _videos.removeAt(entry.key)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              if (_videos.length < 2)
                GestureDetector(
                  onTap: () => _pickVideo(ImageSource.camera),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.background,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_outlined, color: AppColors.textSecondary),
                        SizedBox(height: 2),
                        Text(
                          'Video',
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 2: Review & Submit ──────────────────────────────────────────────────
  Widget _buildStep2Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reviewItem('Category', _selectedCategory ?? '-'),
          _reviewSeverityItem(_severityLevel),
          _reviewItem('Description', _descriptionController.text),
          _reviewItem(
            'Location',
            _latitude != null
                ? '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'
                : 'Not set',
          ),
          if (_detectedAddress != null) _reviewItem('Address', _detectedAddress!),
          if (_landmarkController.text.trim().isNotEmpty)
            _reviewItem('Landmark', _landmarkController.text.trim()),
          _reviewItem('Photos', '${_photos.length} attached'),
          _reviewItem('Videos', '${_videos.length} attached'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your report will be sent to the barangay officials for review and action.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: AppText(
              label,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: AppText(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }

  Widget _reviewSeverityItem(int level) {
    final color = severityColor(level);
    final label = level > 0 ? severityLabelFor(context.s, level) : '-';
    // 4 is the worst, so the meter fills with the level rather than against it.
    final fraction = level > 0 ? Severity.fraction(level) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              'Severity',
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(context.s.levelLabel(level, label), style: AppTextStyles.body),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => Stack(
                      children: [
                        Container(height: 5, color: AppColors.divider),
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _videoFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return 'Video';
    }
  }

}

// ── Report submission success overlay ───────────────────────────────────────
class _ReportSuccessOverlay extends StatefulWidget {
  final String category;
  const _ReportSuccessOverlay({required this.category});

  @override
  State<_ReportSuccessOverlay> createState() => _ReportSuccessOverlayState();
}

class _ReportSuccessOverlayState extends State<_ReportSuccessOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _shieldCtrl;
  late final AnimationController _checkCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _shieldAnim;
  late final Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _shieldCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _shieldAnim = CurvedAnimation(parent: _shieldCtrl, curve: Curves.easeOutBack);
    _checkAnim = CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOutBack);

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _shieldCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 580), () {
      if (mounted) _checkCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shieldCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: AppColors.background,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Animated shield + check ──────────────────────────
              ScaleTransition(
                scale: _shieldAnim,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Icon(
                      Icons.shield_rounded,
                      size: 76,
                      color: AppColors.success,
                    ),
                    ScaleTransition(
                      scale: _checkAnim,
                      child: const Icon(
                        Icons.check_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // ── "Report Submitted!" ───────────────────────────────
              const AppText(
                'Report Submitted!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              )
                  .animate(delay: 650.ms)
                  .fadeIn(duration: 350.ms)
                  .slideY(
                    begin: 0.2,
                    end: 0,
                    duration: 380.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 14),

              // ── Category chip ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.30),
                  ),
                ),
                child: AppText(
                  categoryLabel(context.s, widget.category),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              )
                  .animate(delay: 800.ms)
                  .fadeIn(duration: 300.ms)
                  .scale(
                    begin: const Offset(0.75, 0.75),
                    end: const Offset(1.0, 1.0),
                    duration: 340.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 18),

              // ── Subtitle ──────────────────────────────────────────
              const Text(
                'Barangay officials have been notified.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 980.ms)
                  .fadeIn(duration: 300.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// ── GPS location detecting shimmer ───────────────────────────────────────────
class _LocationShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8EDF5),
      highlightColor: const Color(0xFFF5F7FC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map placeholder
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 10),
          // GPS chip placeholder
          Row(
            children: [
              Container(
                width: 14, height: 14,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Container(
                width: 180, height: 12,
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(4)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: 120, height: 10,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }
}

// ── Photo Required bottom sheet ──────────────────────────────────────────────
class _PhotoRequiredSheet extends StatelessWidget {
  final VoidCallback onAddPhoto;
  const _PhotoRequiredSheet({required this.onAddPhoto});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 36,
                  color: Color(0xFFF59E0B),
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    duration: 480.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 20),
              const AppText(
                'Photo Evidence Required',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 10),
              const Text(
                'High-severity incidents — Fire, Assault, Drug-Related, Domestic Violence, Vehicular Accident, and Medical Emergency — require at least one photo before submission.\n\nThis helps officials verify the report and respond appropriately.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 140.ms)
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAddPhoto,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(context.s.takePhotoNow),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
              ),
            ],
          ),
        ),
      ),
    ).animate().slideY(
          begin: 0.2,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ── GPS Required bottom sheet ────────────────────────────────────────────────
class _GpsRequiredSheet extends StatelessWidget {
  final VoidCallback onEnableLocation;
  final VoidCallback onCallHotline;
  const _GpsRequiredSheet({
    required this.onEnableLocation,
    required this.onCallHotline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  size: 36,
                  color: AppColors.error,
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    duration: 480.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 20),
              const AppText(
                'GPS Location Required',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 10),
              const Text(
                'Reports must be pinned to an exact GPS location so officials can respond immediately.\n\nEnable location access in your settings, then try again. If you cannot enable GPS, call the barangay hotline directly.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 140.ms)
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onEnableLocation,
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(context.s.enableLocation),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCallHotline,
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: Text(context.s.callBarangayHotline),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
                    .animate(delay: 260.ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
              ),
            ],
          ),
        ),
      ),
    ).animate().slideY(
          begin: 0.2,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ── Outside City Sheet ───────────────────────────────────────────────────────

class _OutsideCitySheet extends StatelessWidget {
  final double distanceKm;
  const _OutsideCitySheet({required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final distLabel = distanceKm >= 10
        ? '${distanceKm.toStringAsFixed(0)} km'
        : '${distanceKm.toStringAsFixed(1)} km';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wrong_location_rounded,
              size: 40,
              color: AppColors.error,
            ),
          )
              .animate()
              .scale(
                begin: const Offset(0.5, 0.5),
                duration: 500.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 300.ms),
          const SizedBox(height: 20),
          const AppText(
            'Outside Lipa City',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          )
              .animate(delay: 80.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              children: [
                const TextSpan(text: 'This app is exclusively for '),
                const TextSpan(
                  text: 'Lipa City, Batangas',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const TextSpan(text: ' residents.\n\nYour current location is '),
                TextSpan(
                  text: 'approximately $distLabel away',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                const TextSpan(
                    text: ' from Lipa City. Reports can only be filed from within the city.'),
              ],
            ),
          )
              .animate(delay: 140.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.warning.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'For emergencies outside Lipa City, contact your local barangay officials or dial 911.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(context.s.iUnderstand),
            ),
          )
              .animate(delay: 260.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
        ],
      ),
    ).animate().slideY(
          begin: 0.2,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ── Black Photo Sheet ────────────────────────────────────────────────────────

class _BlackPhotoSheet extends StatelessWidget {
  final VoidCallback onRetake;
  const _BlackPhotoSheet({required this.onRetake});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.no_photography_rounded, size: 40, color: AppColors.error),
          )
              .animate()
              .scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.easeOutBack)
              .fadeIn(duration: 300.ms),
          const SizedBox(height: 20),
          const AppText(
            'Photo Is Too Dark',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary, letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          )
              .animate(delay: 80.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          const Text(
            'Your photo appears to be completely black or too dark to be valid evidence.\n\nPlease take a clear, well-lit photo that shows the actual incident.',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13.5,
              color: AppColors.textSecondary, height: 1.6,
            ),
            textAlign: TextAlign.center,
          )
              .animate(delay: 140.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16,
                    color: AppColors.warning.withValues(alpha: 0.85)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Submitting black or invalid photos for high-severity reports may result in your account being flagged.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11.5,
                      color: AppColors.textSecondary, height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(context.s.retakePhoto),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
              .animate(delay: 260.ms)
              .fadeIn(duration: 280.ms)
              .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(context.s.cancel),
            ),
          )
              .animate(delay: 300.ms)
              .fadeIn(duration: 280.ms),
        ],
      ),
    ).animate().slideY(begin: 0.2, end: 0, duration: 420.ms, curve: Curves.easeOutBack);
  }
}
