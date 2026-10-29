import 'package:flutter/widgets.dart';

/// Supported languages.
enum AppLanguage {
  english('en', 'English'),
  tagalog('tl', 'Tagalog');

  const AppLanguage(this.code, this.label);
  final String code;
  final String label;

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.english,
      );
}

/// App text in English and Tagalog.
///
/// Deliberately a plain typed class rather than `.arb` files + codegen. For
/// two hand-maintained languages this keeps every translation visible beside
/// its English source — a mismatched or missing key is a compile error, not a
/// silent fallback to the key name at runtime, which is the usual failure mode
/// of map-based lookups.
///
/// TRANSLATION NOTES
/// - Barangay terminology (barangay, tanod, kapitan) stays as-is; these are
///   the actual words used, not English loanwords to be translated.
/// - Emergency wording favours the plain spoken Tagalog a panicking person
///   reads fastest, over formal/deep Tagalog. "Tulong" not "saklolo".
/// - Widely-understood English terms common in Filipino usage (GPS, email,
///   password) are kept — translating them would make the app harder to use,
///   not easier.
abstract class AppStrings {
  const AppStrings();

  static const AppStrings en = _EnStrings();
  static const AppStrings tl = _TlStrings();

  static AppStrings of(AppLanguage lang) =>
      lang == AppLanguage.tagalog ? tl : en;

  // ── Common ────────────────────────────────────────────────────────────
  String get cancel;
  String get confirm;
  String get save;
  String get close;
  String get back;
  String get retry;
  String get loading;
  String get search;
  String get all;
  String get yes;
  String get no;
  String get language;
  String get logout;
  String get refresh;
  String get home;
  String get profile;
  String get editProfile;
  String get helpSupport;
  String get about;
  String get signOut;
  String get communityMap;
  String get noReportsYet;
  String get noReportsHomeSubtitle;
  String get noReportsListSubtitle;

  // ── Auth ──────────────────────────────────────────────────────────────
  String get login;
  String get register;
  String get email;
  String get password;
  String get confirmPassword;
  String get fullName;
  String get phoneNumber;
  String get address;
  String get barangay;
  String get createAccount;
  String get signIn;
  String get noAccount;
  String loginScopeTitle(String barangays);
  String get loginScopeBody;
  String get listAnd;
  String get haveAccount;
  String get forgotPassword;
  String get justVisiting;
  String get appTagline;
  String get welcomeBack;

  // ── Roles / positions ─────────────────────────────────────────────────
  String get resident;
  String get nonResident;
  String get official;
  String get secretary;
  String get captain;
  String get tanod;
  String get staff;
  String get administrator;
  String get superAdmin;
  String get cityAdministrator;
  String get allBarangays;
  String get overview_;
  String get cityMap;
  String get allReports;
  String get admin;

  // ── Incident ──────────────────────────────────────────────────────────
  String get reportIncident;
  String get myReports;
  String get recentReports;
  String get reportDetails;
  String get manageIncident;
  String get description;
  String get location;
  String get category;
  String get severity;

  /// Shown in place of the threat level before a category is picked.
  String get severityPickCategoryFirst;

  /// Shown when a left-on location broadcast is resumed at app start.
  String get locationSharingResumed;

  /// Shown when a left-on broadcast could not be resumed and was switched off.
  String get locationSharingCouldNotResume;

  /// Explains that the level is fixed by the category and cannot be edited.
  String get severityAutoSetNote;
  String get status;
  String get reportedBy;
  String get noReports;
  String get fileIncidentReport;
  String get incidentDetails;
  String get locationEvidence;
  String get reviewSubmit;
  String get whatHappened;
  String get whereAndProof;
  String get confirmYourReport;
  String get incidentCategory;
  String get tapToSelectCategory;
  String get describeIncidentHint;
  String get submitReport;
  String get gpsLocation;
  String get nearbyLandmark;
  String get landmarkHint;
  String get photosOptional;
  String get videosOptional;
  String get takePhotoNow;
  String get enableLocation;
  String get callBarangayHotline;
  String get iUnderstand;

  // ── LGU referral pop-up (incidents beyond the barangay) ──────────────
  String get referralTitle;
  String referralBody(String category, String agency);
  String referralCall(String agency);
  String get referralBack;
  String get referralAdvisoryTitle;
  String referralAdvisoryBody(String category, String agency);
  String get referralContinue;
  String get referralNoDialer;
  String get referralCopied;
  String get agencyFire;
  String get agencyPolice;
  String get agencyMedical;
  String get agencyDisaster;
  String get agencyLto;
  String get referralOr;
  String get referralIfHurt;
  String get retakePhoto;

  // ── Status values ─────────────────────────────────────────────────────
  String get statusPending;
  String get statusVerified;
  String get statusAssigned;
  String get statusResponding;
  String get statusOnScene;
  String get statusResolved;
  String get statusFlagged;

  // ── Six-stage tracker ─────────────────────────────────────────────────
  String get responseProgress;
  String get stageSubmitted;
  String get stageSubmittedDesc;
  String get stageVerified;
  String get stageVerifiedDesc;
  String get stageAssigned;
  String get stageAssignedDesc;
  String get stageResponding;
  String get stageRespondingDesc;
  String get stageOnScene;
  String get stageOnSceneDesc;
  String get stageResolved;
  String get stageResolvedDesc;
  String get stageSubmittedWait;
  String get stageVerifiedWait;
  String get stageAssignedWait;
  String get stageRespondingWait;
  String get stageOnSceneWait;
  String get stageResolvedWait;
  String get now;
  String stepOf(int current, int total);
  String elapsedSoFar(String duration);
  String elapsedTook(String duration);

  // ── Conversation ──────────────────────────────────────────────────────
  String get conversation;
  String get messageBarangay;
  String get noMessages;
  String get you;
  String get resolutionNotes;
  String photosCount(int n);
  String videosCount(int n);

  // ── Non-resident flow ─────────────────────────────────────────────────
  String get emergencyReport;
  String get emergencyReportSubtitle;
  String get contactNumber;
  String get continueLabel;
  String get reportEmergency;
  String get callBarangay;
  String get uploadProof;
  String get cannotCall;
  String get helpOnTheWay;
  String get assignedToYourReport;
  String get locatingBarangay;
  String connectedTo(String barangay);
  // Non-resident status banner
  String get nrBannerNotified;
  String get nrBannerUploadProof;
  String get nrBannerReviewing;
  String get nrBannerResolved;
  String get nrBannerDisregarded;
  String get nrOutsideCoverage;
  // Non-resident primary button
  String get nrWaitingLocation;
  String get nrCallBarangayCaps;
  String get nrUploadProofCaps;
  String get nrReviewing;
  String get nrAlreadyFiled;

  // ── Incident categories ───────────────────────────────────────────────
  // Display only. The English string stays the canonical value written to
  // `incidents.category` — translating what gets stored would break filters,
  // the heat map's category list, the high-severity photo rule, and every
  // row already in the database.
  String get catTheft;
  String get catAssault;
  String get catVehicular;
  String get catFire;
  String get catFlooding;
  String get catNoise;
  String get catVandalism;
  String get catSuspicious;
  String get catDrugs;
  String get catDomestic;
  String get catPublicDisturbance;
  String get catMedical;
  String get catOther;

  // ── Severity ──────────────────────────────────────────────────────────
  String get sev1;
  String get sev2;
  String get sev3;
  String get sev4;
  String get sev1Desc;
  String get sev2Desc;
  String get sev3Desc;
  String get sev4Desc;

  // ── Officials ─────────────────────────────────────────────────────────
  String get dashboard;
  String get goodMorning;
  String get goodAfternoon;
  String get goodEvening;
  String get overview;
  String get needsAttention;
  String get recentIncidents;
  String get viewAll;
  String get resolutionRate;
  String get activeBySeverity;
  String get activityLog;
  String get noIncidents;
  String get noIncidentsSubtitle;
  String get emergencyFromVisitors;
  String flaggedNeedReview(int count);
  String awaitingAction(int count);
  String get map;
  String get incidents;
  String get users;
  String get analytics;
  String get heatMap;
  String get lensAllReports;
  String get lensCrime;
  String get lensFire;
  String get lensFlood;
  String get lensAccidents;
  String nothingInPeriod(String lens);
  String get nonResidentReports;
  String get assign;
  String get reassign;
  String get deploy;
  String get disregard;
  String get markResolved;
  String get shareYourLocation;
  String get sharingYourLocation;
  String get reviewProof;
  String get verifyReport;
  String get assignOfficial;
  String get dispatchResponders;
  String get markOnScene;
  String get stepBack;
  String get barangayCoordinates;
  String get coordsWhyItMatters;
  String get coordsUpdated;
  String get coordsAlreadyCurrent;
  String get fromSuggested;
  String get applyAll;
  String get applyAllTitle;
  String get applyAllBody;
  String get tapMapToSetCentre;
  String get centreShouldBeHall;
  String get saveCentre;
  String get suggested;
  String get reporterEstablished;
  String get reporterOrdinary;
  String get reporterCheckHistory;
  String get reportsFiled;
  String get flaggedFalse;
  String get strikesOnRecord;
  String get verifiedAccount;
  String get trustNeverBlocks;
  String get possibleDuplicateTitle;
  String get possibleDuplicateBody;
  String get notDuplicates;
  String get sameIncident;
  String get openReport;
  String get dupSamePhoto;
  String get dupSamePhotoAndPlace;
  String get dupNearby;
  String get linkDuplicateTitle;
  String get linkDuplicateBody;
  String get linkDuplicateConfirm;
  String get duplicateLinked;
  String get duplicateDismissed;
  String get peopleReportedThis;
  String get guardianRequired;
  String get guardianSectionTitle;
  String get guardianSectionWhy;
  String get guardianName;
  String get guardianPhone;
  String get guardianRelationship;
  String get relParent;
  String get relGrandparent;
  String get relSibling;
  String get relLegalGuardian;
  String get relOther;
  String get phoneAlreadyUsedTitle;
  String get phoneAlreadyUsedBody;
  String get continueAnyway;
  String get backToLogin;
  String get notSubmittedYet;
  String get guardianMissing;
  String get guardianOnRecord;
  String get idFrontTitle;
  String get idFrontHint;
  String get idBackTitle;
  String get idBackHint;
  String get idSelfieTitle;
  String get idSelfieHint;
  String get idAllSubmitted;
  String get idAllSubmittedNote;
  String get idPhotoSaved;
  String get selectIdType;
  String get takeAPhoto;
  String get chooseFromGallery;
  String get addPhoto;
  String get ofThree;
  String get fieldRequired;
  String get myAccount;
  String get editDetails;
  String get detailsUpdated;
  String get addStaff;
  String get addStaffSubtitle;
  String get pickPosition;
  String get noEligibleAccounts;
  String get noEligibleAccountsHint;
  String get promoteTitle;
  String get promoteBody;
  String get promoteConfirm;
  String get promoted;
  String get promotedNotifTitle;
  String get promotedNotifBody;
  String get rejectIdTitle;
  String get rejectIdBody;
  String get rejectIdConfirm;
  String get idRejected;
  String get idRejectedNotifTitle;
  String get idRejectedNotifBody;
  String get verificationHeading;
  String get verificationBlurb;
  String get whatToDoNext;
  String get reviewedManuallyNote;
  String get uploadYourId;
  String get uploadIdTitle;
  String get uploadIdSubtitle;
  String get retakeId;
  String get idSubmitted;
  String get idSubmittedNote;
  String get idUploading;
  String get idPrivacyNote;
  String get stepUploadId;
  String get stepUploadIdDesc;
  String get stepOfficialChecks;
  String get stepOfficialChecksDesc;
  String get viewSubmittedId;
  String get noIdSubmitted;
  String get aiSuggestsTitle;
  String aiSuggestsLevel(String level);
  String get aiUseSuggestion;
  String get aiDismiss;
  String get aiChecking;
  String get aiAdvisoryNote;
  String get privacyNotice;
  String get privacyConsentLabel;
  String get privacyConsentRequired;
  String get readNotice;
  String get requestDeletion;
  String get requestDeletionTitle;
  String get requestDeletionBody;
  String get deletionRequested;
  String get deletionAlreadyRequested;
  String get walkUpReport;
  String get residentReports;
  String get nonResidentReportsCount;
  String get fullBlast;
  String get fullBlastConfirmTitle;
  String get fullBlastConfirmBody;
  String fullBlastSent(int count);
  String get fullBlastNobody;
  String get integrityWarning;
  String get integrityMocked;
  String get integrityVpn;
  String get integrityAdvisory;
  String get staleCaseTitle;
  String staleCaseBody(int days);
  String get stillActive;
  String get caseMarkedResolved;
  String get staleCaseSnoozed;
  String get dateRange;
  String get rangeLast7;
  String get rangeLast30;
  String get rangeLast90;
  String get rangeAllTime;
  String showingRange(String range);
  String get dateOfBirth;
  String get dateOfBirthOptional;
  String get dobWhyAsk;
  String get selectDate;
  String get totalUsers;
  String get residentsCount;
  String get personnelCount;
  String get age45Plus;
  String get userStatistics;
  String get dobNotSet;
  String get ageUnknownNote;
  String get theReporter;
  String callPersonQ(String name);
  String willDial(String phone);
  String get onb1Title;
  String get onb1Sub;
  String get onb2Title;
  String get onb2Sub;
  String get onb3Title;
  String get onb3Sub;
  String get aboutTheApp;
  String get keyFeatures;
  String get coverageArea;
  String get technology;
  String get legal;
  String get city;
  String get platform;
  String get backend;
  String get storage;
  String get maps;
  String get featGeoTagged;
  String get featMap;
  String get featTracking;
  String get featRoles;
  String get featAnalytics;
  String get featAudit;
  String get fitEveryone;
  String get centerOnMe;
  String get centerOnThis;
  String get distance;
  String get lastUpdate;
  String get call;
  String get live;
  String get incidentHeatMap;
  String get fitToData;
  String get period;
  String get isolated;
  String get hotspot;
  String get topHotspots;
  String get callReporter;
  String get evidenceSubmitted;
  String get proofNotLoaded;
  String get tapToInspect;
  String get disregardThisReport;
  String get stayInTheApp;
  String get sendThisReport;
  String get barangayNotified;
  String get reasonNoLoad;
  String get reasonNoSignal;
  String get reasonOther;
  String get visitBarangayHall;
  String get visitBarangayHallDesc;
  String get bringValidId;
  String get officialApproves;
  String get youGetNotified;
  String get resetPassword;
  String get sendResetLink;
  String get checkYourEmail;
  String get reportNotFound;
  String get reportDeletedOk;
  String get homeAddress;
  String get saveChanges;
  String get notifications;
  String get markAllRead;
  String get notificationCleared;
  String get barangayOffice;
  String get emailUs;
  String get emergencyHotline;
  String get offlineReportsSubmitted;
  String get onlyPendingDeletable;
  String get incidentMap;
  String get newPassword;
  String get updatePassword;
  String get couldNotPlayVideo;
  String get unableToGetLocation;
  String get bulkDelete;
  String bulkAction(String action);
  String levelLabel(int level, String label);
  String get cityWideOverview;
  String get allBarangaysView;
  String get criticalHighPriority;
  String get cityResolutionRate;
  String get unresolvedOnly;
  String get cityWideIncidentMap;
  String get fitAllIncidents;
  String get allIncidentReports;
  String acrossAllBarangays(int total);
  String get searchAllHint;
  String get noReportsTitle;
  String get noReportsMatchFilters;
  String get noOfficials;
  String get noResidents;
  String get noPendingVerifications;
  String get allPendingReviewed;
  String get locked;
  String get removeAdminRole;
  String get makeOfficial;
  String get submittedId;
  String get reject;
  String get approve;
  String get responsePerformance;
  String get topCategories;
  String get incidentsLast7Days;
  String get analyticsReports;
  String get noDataYet;
  String get noData;
  String get avgResolutionTime;
  String get slaCompliance;
  String get currentlyOverdue;
  String get auditStatusUpdate;
  String get auditSeverityChanged;
  String get auditAssignment;
  String get auditUserVerified;
  String get auditAccountLocked;
  String get auditAccountUnlocked;
  String get auditReportDeleted;
  String get auditReportFlagged;
  String get addressOptional;
  String get selectBarangay;
  String get flagAsFraudulent;
  String get quickActions;
  String get statusProgress;
  String get assignedTo;
  String get severityLevel;
  String get evidencePhotos;
  String get evidenceVideos;
  String get officialUpdates;
  String get postUpdateHint;
  String get noActivityLogged;
  String get resolveIncident;
  String get addResolutionNotes;
  String get resolutionNotesHint;
  String get assignTo;
  String get noOfficialsInBarangay;
  String get removeAssignment;
  String get deleteReport;
  String get applyStrike;
  String get reportDeleted;
  String get notFound;
  String callPerson(String name);
  String get incidentManagement;
  String get userManagement;
  String get searchIncidentsHint;
  String get noIncidentsMatchFilters;
  String get resolve;
  String get delete;
  String get unlock;
  String get lock;
  String get verify;
  String get assignPosition;
  String get removePosition;
  String get noActiveNonResidentReports;
  String get trackLive;
  String get noLocationYet;
  String get whoIsResponding;
  String get restoreToPending;
  String get reopen;
}

// ══════════════════════════════════════════════════════════════════════════
class _EnStrings extends AppStrings {
  const _EnStrings();

  @override String get cancel => 'Cancel';
  @override String get confirm => 'Confirm';
  @override String get save => 'Save';
  @override String get close => 'Close';
  @override String get back => 'Back';
  @override String get retry => 'Retry';
  @override String get loading => 'Loading…';
  @override String get search => 'Search';
  @override String get all => 'All';
  @override String get yes => 'Yes';
  @override String get no => 'No';
  @override String get language => 'Language';
  @override String get logout => 'Log out';
  @override String get refresh => 'Refresh';
  @override String get home => 'Home';
  @override String get profile => 'Profile';
  @override String get editProfile => 'Edit Profile';
  @override String get helpSupport => 'Help & Support';
  @override String get about => 'About';
  @override String get signOut => 'Sign Out';
  @override String get communityMap => 'Community Map';
  @override String get noReportsYet => 'No Reports Yet';
  @override String get noReportsHomeSubtitle =>
      'Tap the + button to file your first incident report.';
  @override String get noReportsListSubtitle =>
      'Your filed incident reports will appear here.';

  @override String get login => 'Login';
  @override String get register => 'Register';
  @override String get email => 'Email Address';
  @override String get password => 'Password';
  @override String get confirmPassword => 'Confirm Password';
  @override String get fullName => 'Full Name';
  @override String get phoneNumber => 'Phone Number';
  @override String get address => 'Address';
  @override String get barangay => 'Barangay';
  @override String get createAccount => 'Create Account';
  @override String get signIn => 'Sign in';
  @override String get noAccount => "Don't have an account? ";
  @override String loginScopeTitle(String barangays) =>
      'Serving Barangays $barangays';
  @override String get loginScopeBody =>
      'Lipa City, Batangas. Residents of other barangays are not covered '
      'by this system.';
  @override String get listAnd => 'and';
  @override String get haveAccount => 'I have an account — Sign in';
  @override String get forgotPassword => 'Forgot Password?';
  @override String get justVisiting => 'Just visiting? Report an emergency';
  @override String get appTagline => 'Incident Reporting System';
  @override String get welcomeBack => 'Welcome back to your community app';

  @override String get resident => 'Resident';
  @override String get nonResident => 'Non-Resident';
  @override String get official => 'Barangay Official';
  @override String get secretary => 'Secretary';
  @override String get captain => 'Barangay Captain';
  @override String get tanod => 'Barangay Tanod';
  @override String get staff => 'Barangay Staff';
  @override String get administrator => 'Administrator';
  @override String get superAdmin => 'SUPER ADMIN';
  @override String get cityAdministrator => 'City Administrator';
  @override String get allBarangays => 'Lipa City — All Barangays';
  @override String get overview_ => 'Overview';
  @override String get cityMap => 'City Map';
  @override String get allReports => 'All Reports';
  @override String get admin => 'Admin';

  @override String get reportIncident => 'Report an Incident';
  @override String get myReports => 'My Reports';
  @override String get recentReports => 'Recent Reports';
  @override String get reportDetails => 'Report Details';
  @override String get manageIncident => 'Manage Incident';
  @override String get description => 'Description';
  @override String get location => 'Location';
  @override String get category => 'Category';
  @override String get severity => 'Severity';
  @override String get locationSharingResumed =>
      'Location sharing resumed — your position is visible to reporters.';
  @override String get locationSharingCouldNotResume =>
      'Location sharing was switched off — it could not be resumed.';
  @override String get severityPickCategoryFirst =>
      'Choose what happened first — the threat level is set automatically.';
  @override String get severityAutoSetNote =>
      'Set automatically by the incident type. This cannot be changed.';
  @override String get status => 'Status';
  @override String get reportedBy => 'Reported by';
  @override String get noReports => 'No reports yet';
  @override String get fileIncidentReport => 'File Incident Report';
  @override String get incidentDetails => 'Incident Details';
  @override String get locationEvidence => 'Location & Evidence';
  @override String get reviewSubmit => 'Review & Submit';
  @override String get whatHappened => 'What happened?';
  @override String get whereAndProof => 'Where and proof';
  @override String get confirmYourReport => 'Confirm your report';
  @override String get incidentCategory => 'Incident Category';
  @override String get tapToSelectCategory =>
      'Tap to select the type of incident';
  @override String get describeIncidentHint =>
      'Describe the incident in detail...';
  @override String get submitReport => 'Submit Report';
  @override String get gpsLocation => 'GPS Location';
  @override String get nearbyLandmark => 'Nearby Landmark (optional)';
  @override String get landmarkHint =>
      'e.g., Near Lipa City Hall, beside 7-Eleven';
  @override String get photosOptional => 'Photos (optional)';
  @override String get videosOptional => 'Videos (optional)';
  @override String get takePhotoNow => 'Take Photo Now';
  @override String get enableLocation => 'Enable Location';
  @override String get callBarangayHotline => 'Call Barangay Hotline';
  @override String get iUnderstand => 'I Understand';

  // ── LGU referral pop-up ──────────────────────────────────────────────
  @override String get referralTitle => 'This needs emergency responders';
  @override String referralBody(String category, String agency) =>
      '$category is beyond what the barangay can handle. Please call '
      '$agency directly — they can respond faster than a report filed here.';
  @override String referralCall(String agency) => 'Call $agency';
  @override String get referralBack => 'Choose another category';
  @override String get referralAdvisoryTitle =>
      'This may need emergency responders too';
  @override String referralAdvisoryBody(String category, String agency) =>
      '$category can be reported to your barangay. If anyone is in danger '
      'right now, please also call $agency directly.';
  @override String get referralContinue => 'Report to the barangay';
  @override String get referralNoDialer =>
      'No phone app on this device. The number is copied — please dial it '
      'manually.';
  @override String get referralCopied => 'Number copied';
  @override String get agencyLto => 'Land Transportation Office (LTO)';
  @override String get referralOr => ' or ';
  @override String get referralIfHurt => 'If anyone is hurt';
  @override String get agencyFire => 'Fire Department (BFP)';
  @override String get agencyPolice => 'Police (PNP)';
  @override String get agencyMedical => 'Ambulance / Emergency Medical';
  @override String get agencyDisaster => 'Disaster Response (CDRRMO)';
  @override String get retakePhoto => 'Retake Photo';

  @override String get statusPending => 'Pending';
  @override String get statusVerified => 'Verified';
  @override String get statusAssigned => 'Assigned';
  @override String get statusResponding => 'Responding';
  @override String get statusOnScene => 'On Scene';
  @override String get statusResolved => 'Resolved';
  @override String get statusFlagged => 'Flagged';

  @override String get responseProgress => 'Response Progress';
  @override String get stageSubmitted => 'Report Submitted';
  @override String get stageSubmittedDesc =>
      'Your report was received by the barangay.';
  @override String get stageVerified => 'Verified by Secretary';
  @override String get stageVerifiedDesc =>
      'The barangay secretary confirmed your report.';
  @override String get stageAssigned => 'Official Assigned';
  @override String get stageAssignedDesc =>
      'A barangay official was put in charge.';
  @override String get stageResponding => 'Responders En Route';
  @override String get stageRespondingDesc =>
      'Help is on the way to your location.';
  @override String get stageOnScene => 'On Scene';
  @override String get stageOnSceneDesc =>
      'Responders have arrived at the location.';
  @override String get stageResolved => 'Resolved';
  @override String get stageResolvedDesc =>
      'The barangay marked this incident as resolved.';
  @override String get stageSubmittedWait =>
      'Waiting for your report to be received.';
  @override String get stageVerifiedWait =>
      'The secretary will review your report shortly.';
  @override String get stageAssignedWait =>
      'An official will be assigned to handle this.';
  @override String get stageRespondingWait =>
      'Responders will be dispatched to you.';
  @override String get stageOnSceneWait =>
      'Responders will arrive at the location.';
  @override String get stageResolvedWait =>
      'This will close once the incident is handled.';
  @override String get now => 'NOW';
  @override String stepOf(int current, int total) => 'Step $current of $total';
  @override String elapsedSoFar(String duration) => '$duration so far';
  @override String elapsedTook(String duration) => 'Took $duration';

  @override String get conversation => 'Conversation';
  @override String get messageBarangay => 'Message the barangay…';
  @override String get noMessages =>
      'No messages yet. You can send a message to the barangay about this report.';
  @override String get you => 'You';
  @override String get resolutionNotes => 'Resolution Notes';
  @override String photosCount(int n) => 'Photos ($n)';
  @override String videosCount(int n) => 'Videos ($n)';

  @override String get emergencyReport => 'Emergency Report';
  @override String get emergencyReportSubtitle =>
      'For visitors and non-residents. Enter your details to report an '
      'emergency to the nearest barangay.';
  @override String get contactNumber => 'Contact Number';
  @override String get continueLabel => 'Continue';
  @override String get reportEmergency => 'REPORT EMERGENCY';
  @override String get callBarangay => 'Call Barangay';
  @override String get uploadProof => 'Upload proof';
  @override String get cannotCall => "I can't call";
  @override String get helpOnTheWay => 'Help is on the way';
  @override String get assignedToYourReport => 'Assigned to your report';
  @override String get locatingBarangay => 'Locating your barangay…';
  @override String connectedTo(String barangay) => 'Connected to $barangay';
  @override String get nrBannerNotified => 'Barangay notified — call them now';
  @override String get nrBannerUploadProof => 'Upload proof to continue';
  @override String get nrBannerReviewing => 'Barangay is reviewing your proof';
  @override String get nrBannerResolved => 'Report resolved';
  @override String get nrBannerDisregarded => 'Report disregarded';
  @override String get nrOutsideCoverage =>
      'You have left the barangay coverage area';
  @override String get nrWaitingLocation => 'Waiting for your location…';
  @override String get nrCallBarangayCaps => 'CALL BARANGAY';
  @override String get nrUploadProofCaps => 'UPLOAD PROOF';
  @override String get nrReviewing => 'Barangay is reviewing…';
  @override String get nrAlreadyFiled => 'Report already filed';

  @override String get catTheft => 'Theft / Robbery';
  @override String get catAssault => 'Physical Assault';
  @override String get catVehicular => 'Vehicular Accident';
  @override String get catFire => 'Fire';
  @override String get catFlooding => 'Flooding';
  @override String get catNoise => 'Noise Disturbance';
  @override String get catVandalism => 'Vandalism';
  @override String get catSuspicious => 'Suspicious Activity';
  @override String get catDrugs => 'Drug-Related';
  @override String get catDomestic => 'Domestic Violence';
  @override String get catPublicDisturbance => 'Public Disturbance';
  @override String get catMedical => 'Medical Emergency';
  @override String get catOther => 'Other';

  @override String get sev1 => 'Critical / Life-Threatening';
  @override String get sev2 => 'High / Serious';
  @override String get sev3 => 'Medium / Moderate';
  @override String get sev4 => 'Low / Minor Disturbance';
  @override String get sev1Desc =>
      'Immediate danger to life. Requires emergency response.';
  @override String get sev2Desc => 'Serious incident requiring urgent attention.';
  @override String get sev3Desc => 'Moderate incident that needs timely response.';
  @override String get sev4Desc => 'Minor disturbance or community concern.';

  @override String get dashboard => 'Dashboard';
  @override String get goodMorning => 'Good morning';
  @override String get goodAfternoon => 'Good afternoon';
  @override String get goodEvening => 'Good evening';
  @override String get overview => 'Overview';
  @override String get needsAttention => 'Needs Immediate Attention';
  @override String get recentIncidents => 'Recent Incidents';
  @override String get viewAll => 'View All';
  @override String get resolutionRate => 'Resolution Rate';
  @override String get activeBySeverity => 'Active by Severity';
  @override String get activityLog => 'Activity Log';
  @override String get noIncidents => 'No Incidents';
  @override String get noIncidentsSubtitle =>
      'No incident reports yet for your barangay.';
  @override String get emergencyFromVisitors =>
      'Emergency reports from visitors';
  @override String flaggedNeedReview(int count) => count == 1
      ? '1 flagged report needs review'
      : '$count flagged reports need review';
  @override String awaitingAction(int count) => count == 1
      ? '1 report awaiting action'
      : '$count reports awaiting action';
  @override String get map => 'Map';
  @override String get incidents => 'Incidents';
  @override String get users => 'Users';
  @override String get analytics => 'Analytics';
  @override String get heatMap => 'Heat Map';
  @override String get lensAllReports => 'All Reports';
  @override String get lensCrime => 'Crime';
  @override String get lensFire => 'Fire';
  @override String get lensFlood => 'Flooding';
  @override String get lensAccidents => 'Accidents';
  @override String nothingInPeriod(String lens) =>
      'No $lens in this period';
  @override String get nonResidentReports => 'Non-Resident Reports';
  @override String get assign => 'Assign';
  @override String get reassign => 'Reassign';
  @override String get deploy => 'Deploy';
  @override String get disregard => 'Disregard';
  @override String get markResolved => 'Mark Resolved';
  @override String get shareYourLocation => 'Share your location';
  @override String get sharingYourLocation => 'Sharing your location';
  @override String get reviewProof => 'Review proof';
  @override String get verifyReport => 'Verify Report';
  @override String get assignOfficial => 'Assign Official';
  @override String get dispatchResponders => 'Dispatch Responders';
  @override String get markOnScene => 'Mark On Scene';
  @override String get stepBack => 'Step back';
  @override String get barangayCoordinates => 'Barangay coordinates';
  @override String get coordsWhyItMatters =>
      'Emergency reports from visitors are routed to whichever barangay centre '
      'is closest. A wrong pin sends an emergency to the wrong hall, so set '
      'each one to the actual barangay hall.';
  @override String get coordsUpdated => 'Coordinates updated';
  @override String get coordsAlreadyCurrent => 'Everything is already up to date';
  @override String get fromSuggested => 'from the suggested point';
  @override String get applyAll => 'Apply suggested';
  @override String get applyAllTitle => 'Use the suggested points?';
  @override String get applyAllBody =>
      'barangays will move to points sourced from OpenStreetMap. Check each on '
      'the map afterwards — only your barangay knows where its hall really is.';
  @override String get tapMapToSetCentre => 'Tap the map to place the centre point.';
  @override String get centreShouldBeHall =>
      'Set this to the barangay hall, not the middle of the area.';
  @override String get saveCentre => 'Save centre point';
  @override String get suggested => 'SUGGESTED';
  @override String get reporterEstablished => 'Established reporter';
  @override String get reporterOrdinary => 'Reporter history';
  @override String get reporterCheckHistory => 'Check this reporter\'s history';
  @override String get reportsFiled => 'reports filed';
  @override String get flaggedFalse => 'flagged false';
  @override String get strikesOnRecord => 'strikes';
  @override String get verifiedAccount => 'verified';
  @override String get trustNeverBlocks =>
      'History never blocks a report. Respond as normal.';
  @override String get possibleDuplicateTitle => 'Already reported?';
  @override String get possibleDuplicateBody =>
      'These came in nearby around the same time. Link them only if they are '
      'the same emergency.';
  @override String get notDuplicates => 'These are different';
  @override String get sameIncident => 'Same incident';
  @override String get openReport => 'Open';
  @override String get dupSamePhoto => 'Same photo';
  @override String get dupSamePhotoAndPlace => 'Same photo & place';
  @override String get dupNearby => 'Nearby';
  @override String get linkDuplicateTitle => 'Link these reports?';
  @override String get linkDuplicateBody =>
      'The later report will be filed under the earlier one. Nothing is '
      'deleted, and everyone who reported it still gets the updates.';
  @override String get linkDuplicateConfirm => 'Link them';
  @override String get duplicateLinked => 'Reports linked';
  @override String get duplicateDismissed => 'Kept separate';
  @override String get peopleReportedThis => 'people reported this';
  @override String get guardianRequired =>
      'Please complete the parent or guardian details.';
  @override String get guardianSectionTitle => 'Parent or guardian';
  @override String get guardianSectionWhy =>
      'You are under 18, so the law requires a parent or guardian to agree '
      'before the barangay can keep your details. You can still report an '
      'emergency either way.';
  @override String get guardianName => 'Parent / guardian full name';
  @override String get guardianPhone => 'Parent / guardian phone';
  @override String get guardianRelationship => 'Relationship to you';
  @override String get relParent => 'Parent';
  @override String get relGrandparent => 'Grandparent';
  @override String get relSibling => 'Older sibling';
  @override String get relLegalGuardian => 'Legal guardian';
  @override String get relOther => 'Other';
  @override String get phoneAlreadyUsedTitle => 'That number is already registered';
  @override String get phoneAlreadyUsedBody =>
      'An account already uses this phone number. If it is yours, sign in '
      'instead of making a second one.';
  @override String get continueAnyway => 'Continue anyway';
  @override String get notSubmittedYet => 'Not submitted yet';
  @override String get guardianMissing =>
      'Under 18 - no guardian consent on record';
  @override String get guardianOnRecord => 'Guardian consent on record';
  @override String get idFrontTitle => 'Front of your ID';
  @override String get idFrontHint => 'Your name and photo must be readable';
  @override String get idBackTitle => 'Back of your ID';
  @override String get idBackHint => 'Shows the ID is genuine';
  @override String get idSelfieTitle => 'Selfie holding your ID';
  @override String get idSelfieHint => 'Camera only, so we can see it is you';
  @override String get idAllSubmitted => 'All three received';
  @override String get idAllSubmittedNote =>
      'A barangay official will review them. You can replace any photo until '
      'then.';
  @override String get idPhotoSaved => 'Photo saved';
  @override String get selectIdType => 'Which ID are you using?';
  @override String get takeAPhoto => 'Take a photo';
  @override String get chooseFromGallery => 'Choose from gallery';
  @override String get addPhoto => 'Add';
  @override String get ofThree => 'of 3';
  @override String get fieldRequired => 'Required';
  @override String get myAccount => 'My account';
  @override String get editDetails => 'Edit details';
  @override String get detailsUpdated => 'Details updated';
  @override String get addStaff => 'Add personnel';
  @override String get addStaffSubtitle =>
      'Pick a registered resident to give a barangay hall role.';
  @override String get pickPosition => 'Choose a position';
  @override String get noEligibleAccounts => 'No accounts to promote';
  @override String get noEligibleAccountsHint =>
      'They need to register and be verified first, then they will show up here.';
  @override String get promoteTitle => 'Give this person a role?';
  @override String get promoteBody =>
      'They will get access to reports, residents and barangay tools. You can '
      'remove the role later.';
  @override String get promoteConfirm => 'Give role';
  @override String get promoted => 'Role granted';
  @override String get promotedNotifTitle => 'You now have a barangay role';
  @override String get promotedNotifBody =>
      'Your barangay gave you a hall position. Sign out and back in to see the '
      'official tools.';
  @override String get rejectIdTitle => 'Ask for a new photo?';
  @override String get rejectIdBody =>
      'The ID will be removed and they can upload another one. This does not '
      'lock or delete their account.';
  @override String get rejectIdConfirm => 'Ask for new photo';
  @override String get idRejected => 'Asked for a new photo';
  @override String get idRejectedNotifTitle => 'Please re-upload your ID';
  @override String get idRejectedNotifBody =>
      'Your barangay could not read the ID you sent. Please upload a clearer '
      'photo showing your name and address.';
  @override String get verificationHeading => 'One more step';
  @override String get verificationBlurb =>
      'Your account is created. Upload a valid ID and a barangay official will '
      'check it - no need to visit the hall.';
  @override String get whatToDoNext => 'How it works';
  @override String get reviewedManuallyNote =>
      'A real person reviews every ID, so approval is not instant.';
  @override String get uploadYourId => 'Upload your valid ID';
  @override String get uploadIdTitle => 'Verify from home';
  @override String get uploadIdSubtitle =>
      'Take a photo of any government-issued ID showing your name and address. '
      'No trip to the barangay hall needed.';
  @override String get retakeId => 'Replace photo';
  @override String get idSubmitted => 'ID submitted';
  @override String get idSubmittedNote =>
      'Your barangay is reviewing it. You can replace the photo if it came out blurry.';
  @override String get idUploading => 'Uploading…';
  @override String get idPrivacyNote =>
      'Only your own barangay officials can see this. It is never public.';
  @override String get stepUploadId => 'Upload your ID';
  @override String get stepUploadIdDesc =>
      'A photo of any government-issued ID. Takes a minute.';
  @override String get stepOfficialChecks => 'An official checks it';
  @override String get stepOfficialChecksDesc =>
      'A barangay official reviews your ID and activates your account.';
  @override String get viewSubmittedId => 'View submitted ID';
  @override String get noIdSubmitted => 'No ID submitted yet';
  @override String get aiSuggestsTitle => 'Suggested severity';
  @override String aiSuggestsLevel(String level) => 'This looks like $level';
  @override String get aiUseSuggestion => 'Use this';
  @override String get aiDismiss => 'Keep mine';
  @override String get aiChecking => 'Checking your photo…';
  @override String get aiAdvisoryNote =>
      'A suggestion from your photo. You decide.';
  @override String get privacyNotice => 'Privacy Notice';
  @override String get privacyConsentLabel =>
      'I have read and agree to the Privacy Notice.';
  @override String get privacyConsentRequired =>
      'Please read and accept the Privacy Notice to continue.';
  @override String get readNotice => 'Read it';
  @override String get requestDeletion => 'Request account deletion';
  @override String get requestDeletionTitle => 'Request account deletion?';
  @override String get requestDeletionBody =>
      'Your barangay will be notified and will remove your personal details.\n\n'
      'Incident reports you filed are kept as the barangay record of a real '
      'emergency, but your name and contact details are removed from them.';
  @override String get deletionRequested =>
      'Request sent. Your barangay will action it.';
  @override String get deletionAlreadyRequested => 'Deletion already requested';
  @override String get walkUpReport => 'NON-RESIDENT';
  @override String get residentReports => 'Resident reports';
  @override String get nonResidentReportsCount => 'Non-resident reports';
  @override String get fullBlast => 'Alert Everyone';
  @override String get fullBlastConfirmTitle => 'Alert the whole barangay hall?';
  @override String get fullBlastConfirmBody =>
      'Every member of the hall will be notified immediately, whoever the case '
      'is assigned to. Use this for emergencies that cannot wait.';
  @override String fullBlastSent(int count) => 'Alerted $count personnel';
  @override String get fullBlastNobody =>
      'No one in this barangay holds a position yet — nobody to alert.';
  @override String get integrityWarning => 'Check this report carefully';
  @override String get integrityMocked =>
      'The device reported a fake GPS location.';
  @override String get integrityVpn => 'Filed while connected through a VPN.';
  @override String get integrityAdvisory =>
      'This does not mean the report is false — verify as usual.';
  @override String get staleCaseTitle => 'Is this case finished?';
  @override String staleCaseBody(int days) => days <= 1
      ? 'no update for a day. If it is already sorted, close it here.'
      : 'no update for $days days. If it is already sorted, close it here.';
  @override String get stillActive => 'Still active';
  @override String get caseMarkedResolved => 'Case marked resolved';
  @override String get staleCaseSnoozed => "Noted — we'll ask again tomorrow";
  @override String get dateRange => 'Date Range';
  @override String get rangeLast7 => '7 days';
  @override String get rangeLast30 => '30 days';
  @override String get rangeLast90 => '90 days';
  @override String get rangeAllTime => 'All time';
  @override String showingRange(String range) => 'Showing: $range';
  @override String get dateOfBirth => 'Date of Birth';
  @override String get dateOfBirthOptional => 'Date of Birth (optional)';
  @override String get dobWhyAsk =>
      'Used only for anonymous barangay statistics. Never shown to anyone.';
  @override String get selectDate => 'Select date';
  @override String get totalUsers => 'Total Users';
  @override String get residentsCount => 'Residents';
  @override String get personnelCount => 'Barangay Personnel';
  @override String get age45Plus => 'Aged 45 and over';
  @override String get userStatistics => 'User Statistics';
  @override String get dobNotSet => 'Not set';
  @override String get ageUnknownNote =>
      'accounts have no birth date on file and are not counted.';
  @override String get theReporter => 'the reporter';
  @override String callPersonQ(String name) => 'Call $name?';
  @override String willDial(String phone) => 'This will dial $phone.';
  @override String get onb1Title => 'Stay Safe,\nStay Informed';
  @override String get onb1Sub =>
      "Get real-time alerts about incidents in your barangay. Your community's "
      'safety is one tap away.';
  @override String get onb2Title => 'Report in\nSeconds';
  @override String get onb2Sub =>
      'Capture the scene, pin the location, and file a report instantly - '
      'even without internet.';
  @override String get onb3Title => 'Officials\nRespond Fast';
  @override String get onb3Sub =>
      'Barangay officials are notified immediately and can track, update, and '
      'resolve reports in real time.';
  @override String get aboutTheApp => 'About the App';
  @override String get keyFeatures => 'Key Features';
  @override String get coverageArea => 'Coverage Area';
  @override String get technology => 'Technology';
  @override String get legal => 'Legal';
  @override String get city => 'City';
  @override String get platform => 'Platform';
  @override String get backend => 'Backend';
  @override String get storage => 'Storage';
  @override String get maps => 'Maps';
  @override String get featGeoTagged => 'Geo-Tagged Incident Reporting';
  @override String get featMap => 'Interactive City-Wide Incident Map';
  @override String get featTracking => 'Real-Time Status Tracking';
  @override String get featRoles => 'Role-Based Access Control';
  @override String get featAnalytics => 'Analytics & Statistics Dashboard';
  @override String get featAudit => 'Full Audit Trail Logging';
  @override String get fitEveryone => 'Fit everyone';
  @override String get centerOnMe => 'Center on me';
  @override String get centerOnThis => 'Center on this';
  @override String get distance => 'Distance';
  @override String get lastUpdate => 'Last update';
  @override String get call => 'Call';
  @override String get live => 'LIVE';
  @override String get incidentHeatMap => 'Incident Heat Map';
  @override String get fitToData => 'Fit to data';
  @override String get period => 'Period';
  @override String get isolated => 'Isolated';
  @override String get hotspot => 'Hotspot';
  @override String get topHotspots => 'Top hotspots';
  @override String get callReporter => 'Call reporter';
  @override String get evidenceSubmitted => 'Evidence submitted';
  @override String get proofNotLoaded => 'Proof could not be loaded';
  @override String get tapToInspect => 'Tap to inspect';
  @override String get disregardThisReport => 'Disregard this report?';
  @override String get stayInTheApp => 'Stay in the app';
  @override String get sendThisReport => 'Send this emergency report?';
  @override String get barangayNotified => 'Barangay notified';
  @override String get reasonNoLoad => 'No load / credits';
  @override String get reasonNoSignal => 'No signal';
  @override String get reasonOther => 'Another reason';
  @override String get visitBarangayHall => 'Visit the Barangay Hall';
  @override String get visitBarangayHallDesc =>
      'Go in person during office hours.';
  @override String get bringValidId => 'Bring a Valid ID';
  @override String get officialApproves => 'Official Approves Your Account';
  @override String get youGetNotified => 'You Get Notified';
  @override String get backToLogin => 'Back to Login';
  @override String get resetPassword => 'Reset Password';
  @override String get sendResetLink => 'Send Reset Link';
  @override String get checkYourEmail => 'Check Your Email';
  @override String get reportNotFound => 'Report not found';
  @override String get reportDeletedOk => 'Report deleted successfully';
  @override String get homeAddress => 'Home Address';
  @override String get saveChanges => 'Save Changes';
  @override String get notifications => 'Notifications';
  @override String get markAllRead => 'Mark all read';
  @override String get notificationCleared => 'Notification cleared';
  @override String get barangayOffice => 'Barangay Office';
  @override String get emailUs => 'Email Us';
  @override String get emergencyHotline => 'Emergency Hotline';
  @override String get offlineReportsSubmitted =>
      'Offline reports submitted successfully';
  @override String get onlyPendingDeletable =>
      'Only pending reports can be deleted';
  @override String get incidentMap => 'Incident Map';
  @override String get newPassword => 'New Password';
  @override String get updatePassword => 'Update Password';
  @override String get couldNotPlayVideo => 'Could not play video';
  @override String get unableToGetLocation => 'Unable to get location';
  @override String get bulkDelete => 'Bulk Delete';
  @override String bulkAction(String action) => 'Bulk $action';
  @override String levelLabel(int level, String label) =>
      'Level $level: $label';
  @override String get cityWideOverview => 'City-Wide Overview';
  @override String get allBarangaysView => 'All barangays - city-wide view';
  @override String get criticalHighPriority => 'Critical & High Priority';
  @override String get cityResolutionRate => 'City Resolution Rate';
  @override String get unresolvedOnly => 'Unresolved only';
  @override String get cityWideIncidentMap => 'City-Wide Incident Map';
  @override String get fitAllIncidents => 'Fit all incidents';
  @override String get allIncidentReports => 'All Incident Reports';
  @override String acrossAllBarangays(int total) =>
      'Across all barangays · $total total';
  @override String get searchAllHint =>
      'Search by description, category, barangay, reporter...';
  @override String get noReportsTitle => 'No Reports';
  @override String get noReportsMatchFilters => 'No reports match your filters.';
  @override String get noOfficials => 'No Officials';
  @override String get noResidents => 'No Residents';
  @override String get noPendingVerifications => 'No Pending Verifications';
  @override String get allPendingReviewed =>
      'All pending accounts have been reviewed.';
  @override String get locked => 'LOCKED';
  @override String get removeAdminRole => 'Remove Admin Role';
  @override String get makeOfficial => 'Make Official';
  @override String get submittedId => 'Submitted ID:';
  @override String get reject => 'Reject';
  @override String get approve => 'Approve';
  @override String get responsePerformance => 'Response Performance';
  @override String get topCategories => 'Top Categories';
  @override String get incidentsLast7Days => 'Incidents - Last 7 Days';
  @override String get analyticsReports => 'Analytics & Reports';
  @override String get noDataYet => 'No data yet';
  @override String get noData => 'No data';
  @override String get avgResolutionTime => 'Avg Resolution Time';
  @override String get slaCompliance => 'SLA Compliance (≤48h)';
  @override String get currentlyOverdue => 'Currently Overdue';
  @override String get auditStatusUpdate => 'Status Update';
  @override String get auditSeverityChanged => 'Severity Changed';
  @override String get auditAssignment => 'Assignment';
  @override String get auditUserVerified => 'User Verified';
  @override String get auditAccountLocked => 'Account Locked';
  @override String get auditAccountUnlocked => 'Account Unlocked';
  @override String get auditReportDeleted => 'Report Deleted';
  @override String get auditReportFlagged => 'Report Flagged';
  @override String get addressOptional => 'Address (optional)';
  @override String get selectBarangay => 'Select Barangay';
  @override String get flagAsFraudulent => 'Flag as Fraudulent';
  @override String get quickActions => 'Quick Actions';
  @override String get statusProgress => 'Status Progress';
  @override String get assignedTo => 'Assigned To';
  @override String get severityLevel => 'Severity Level';
  @override String get evidencePhotos => 'Evidence Photos';
  @override String get evidenceVideos => 'Evidence Videos';
  @override String get officialUpdates => 'Official Updates';
  @override String get postUpdateHint => 'Post an update to the resident...';
  @override String get noActivityLogged => 'No activity logged yet.';
  @override String get resolveIncident => 'Resolve Incident';
  @override String get addResolutionNotes =>
      'Add resolution notes (optional):';
  @override String get resolutionNotesHint =>
      'How was this incident resolved?';
  @override String get assignTo => 'Assign To';
  @override String get noOfficialsInBarangay =>
      'No officials found in this barangay.';
  @override String get removeAssignment => 'Remove Assignment';
  @override String get deleteReport => 'Delete Report';
  @override String get applyStrike => 'Apply Strike';
  @override String get reportDeleted => 'Report deleted';
  @override String get notFound => 'Not found';
  @override String callPerson(String name) => 'Call $name';
  @override String get incidentManagement => 'Incident Management';
  @override String get userManagement => 'User Management';
  @override String get searchIncidentsHint =>
      'Search description, category, reporter…';
  @override String get noIncidentsMatchFilters =>
      'No incident reports match your filters.';
  @override String get resolve => 'Resolve';
  @override String get delete => 'Delete';
  @override String get unlock => 'Unlock';
  @override String get lock => 'Lock';
  @override String get verify => 'Verify';
  @override String get assignPosition => 'Assign Position';
  @override String get removePosition => 'Remove Position';
  @override String get noActiveNonResidentReports =>
      'No active non-resident reports';
  @override String get trackLive => 'Track Live';
  @override String get noLocationYet => 'No location received yet';
  @override String get whoIsResponding => 'Who is responding?';
  @override String get restoreToPending => 'Restore to Pending';
  @override String get reopen => 'Reopen';
}

// ══════════════════════════════════════════════════════════════════════════
class _TlStrings extends AppStrings {
  const _TlStrings();

  @override String get cancel => 'Kanselahin';
  @override String get confirm => 'Kumpirmahin';
  @override String get save => 'I-save';
  @override String get close => 'Isara';
  @override String get back => 'Bumalik';
  @override String get retry => 'Subukan ulit';
  @override String get loading => 'Naglo-load…';
  @override String get search => 'Maghanap';
  @override String get all => 'Lahat';
  @override String get yes => 'Oo';
  @override String get no => 'Hindi';
  @override String get language => 'Wika';
  @override String get logout => 'Mag-log out';
  @override String get refresh => 'I-refresh';
  @override String get home => 'Home';
  @override String get profile => 'Profile';
  @override String get editProfile => 'I-edit ang Profile';
  @override String get helpSupport => 'Tulong at Suporta';
  @override String get about => 'Tungkol Dito';
  @override String get signOut => 'Mag-sign out';
  @override String get communityMap => 'Mapa ng Komunidad';
  @override String get noReportsYet => 'Wala Pang Report';
  @override String get noReportsHomeSubtitle =>
      'Pindutin ang + para maghain ng unang report mo.';
  @override String get noReportsListSubtitle =>
      'Dito lalabas ang mga report na inihain mo.';

  @override String get login => 'Mag-login';
  @override String get register => 'Magrehistro';
  // Kept in English — universally used in Filipino digital contexts, and
  // translating them makes forms harder to complete, not easier.
  @override String get email => 'Email Address';
  @override String get password => 'Password';
  @override String get confirmPassword => 'Kumpirmahin ang Password';
  @override String get fullName => 'Buong Pangalan';
  @override String get phoneNumber => 'Numero ng Telepono';
  @override String get address => 'Tirahan';
  @override String get barangay => 'Barangay';
  @override String get createAccount => 'Gumawa ng Account';
  @override String get signIn => 'Mag-sign in';
  @override String get noAccount => 'Wala pang account? ';
  @override String loginScopeTitle(String barangays) =>
      'Naglilingkod sa Barangay $barangays';
  @override String get loginScopeBody =>
      'Lipa City, Batangas. Hindi sakop ng sistemang ito ang mga '
      'residente ng ibang barangay.';
  @override String get listAnd => 'at';
  @override String get haveAccount => 'May account na ako — Mag-sign in';
  @override String get forgotPassword => 'Nakalimutan ang Password?';
  @override String get justVisiting =>
      'Bisita lang? Mag-report ng emergency';
  @override String get appTagline => 'Sistema ng Pag-uulat ng Insidente';
  @override String get welcomeBack => 'Maligayang balik sa app ng komunidad mo';

  @override String get resident => 'Residente';
  @override String get nonResident => 'Hindi Residente';
  @override String get official => 'Opisyal ng Barangay';
  @override String get secretary => 'Kalihim';
  @override String get captain => 'Kapitan ng Barangay';
  @override String get tanod => 'Barangay Tanod';
  @override String get staff => 'Kawani ng Barangay';
  @override String get administrator => 'Administrador';
  // Role badge kept in English — it is a system role name officials already
  // recognise on sight, not a phrase to be read.
  @override String get superAdmin => 'SUPER ADMIN';
  @override String get cityAdministrator => 'Administrador ng Lungsod';
  @override String get allBarangays => 'Lipa City — Lahat ng Barangay';
  @override String get overview_ => 'Buod';
  @override String get cityMap => 'Mapa ng Lungsod';
  @override String get allReports => 'Lahat ng Report';
  @override String get admin => 'Admin';

  @override String get reportIncident => 'Mag-report ng Insidente';
  @override String get myReports => 'Mga Report Ko';
  @override String get recentReports => 'Mga Bagong Report';
  @override String get reportDetails => 'Detalye ng Report';
  @override String get manageIncident => 'Pamahalaan ang Insidente';
  @override String get description => 'Paglalarawan';
  @override String get location => 'Lokasyon';
  @override String get category => 'Uri';
  @override String get severity => 'Antas ng Panganib';
  @override String get locationSharingResumed =>
      'Ipinagpatuloy ang pagbabahagi ng lokasyon — nakikita ka ng mga nag-uulat.';
  @override String get locationSharingCouldNotResume =>
      'Na-off ang pagbabahagi ng lokasyon — hindi ito naipagpatuloy.';
  @override String get severityPickCategoryFirst =>
      'Piliin muna kung ano ang nangyari — awtomatikong itatakda ang antas ng panganib.';
  @override String get severityAutoSetNote =>
      'Awtomatikong itinakda batay sa uri ng insidente. Hindi ito mababago.';
  @override String get status => 'Katayuan';
  @override String get reportedBy => 'Iniulat ni';
  @override String get noReports => 'Wala pang report';
  @override String get fileIncidentReport => 'Maghain ng Report';
  @override String get incidentDetails => 'Detalye ng Insidente';
  @override String get locationEvidence => 'Lokasyon at Ebidensya';
  @override String get reviewSubmit => 'Suriin at Ipadala';
  @override String get whatHappened => 'Ano ang nangyari?';
  @override String get whereAndProof => 'Saan at anong patunay';
  @override String get confirmYourReport => 'Kumpirmahin ang report mo';
  @override String get incidentCategory => 'Uri ng Insidente';
  @override String get tapToSelectCategory =>
      'Pindutin para piliin ang uri ng insidente';
  @override String get describeIncidentHint =>
      'Ilarawan nang detalyado ang nangyari...';
  @override String get submitReport => 'Ipadala ang Report';
  // GPS kept as-is — the term everyone already uses.
  @override String get gpsLocation => 'Lokasyon sa GPS';
  @override String get nearbyLandmark => 'Malapit na Palatandaan (opsyonal)';
  @override String get landmarkHint =>
      'hal., Malapit sa Lipa City Hall, katabi ng 7-Eleven';
  @override String get photosOptional => 'Mga Larawan (opsyonal)';
  @override String get videosOptional => 'Mga Video (opsyonal)';
  @override String get takePhotoNow => 'Kumuha ng Larawan Ngayon';
  @override String get enableLocation => 'Buksan ang Lokasyon';
  @override String get callBarangayHotline => 'Tawagan ang Barangay Hotline';
  @override String get iUnderstand => 'Naiintindihan Ko';

  // ── LGU referral pop-up ──────────────────────────────────────────────
  @override String get referralTitle =>
      'Kailangan nito ng mga emergency responder';
  @override String referralBody(String category, String agency) =>
      'Ang $category ay hindi kayang tugunan ng barangay. Mangyaring '
      'tawagan nang direkta ang $agency — mas mabilis silang makakatugon '
      'kaysa sa report dito.';
  @override String referralCall(String agency) => 'Tawagan ang $agency';
  @override String get referralBack => 'Pumili ng ibang kategorya';
  @override String get referralAdvisoryTitle =>
      'Maaaring kailanganin din ang mga emergency responder';
  @override String referralAdvisoryBody(String category, String agency) =>
      'Ang $category ay maaaring i-report sa inyong barangay. Kung may '
      'panganib ngayon, mangyaring tawagan din nang direkta ang $agency.';
  @override String get referralContinue => 'I-report sa barangay';
  @override String get referralNoDialer =>
      'Walang phone app sa device na ito. Nakopya na ang numero — paki-dial '
      'nang mano-mano.';
  @override String get referralCopied => 'Nakopya ang numero';
  @override String get agencyLto => 'Land Transportation Office (LTO)';
  @override String get referralOr => ' o ';
  @override String get referralIfHurt => 'Kung may nasaktan';
  @override String get agencyFire => 'Bumbero (BFP)';
  @override String get agencyPolice => 'Pulisya (PNP)';
  @override String get agencyMedical => 'Ambulansya / Emergency Medical';
  @override String get agencyDisaster => 'Disaster Response (CDRRMO)';
  @override String get retakePhoto => 'Kuhanan Ulit';

  @override String get statusPending => 'Naghihintay';
  @override String get statusVerified => 'Naberipika';
  @override String get statusAssigned => 'May Naka-assign';
  @override String get statusResponding => 'Papunta Na';
  @override String get statusOnScene => 'Nasa Lugar Na';
  @override String get statusResolved => 'Naayos Na';
  @override String get statusFlagged => 'Naka-flag';

  @override String get responseProgress => 'Progreso ng Tugon';
  @override String get stageSubmitted => 'Naipadala ang Report';
  @override String get stageSubmittedDesc =>
      'Natanggap na ng barangay ang iyong report.';
  @override String get stageVerified => 'Naberipika ng Kalihim';
  @override String get stageVerifiedDesc =>
      'Kinumpirma ng kalihim ng barangay ang iyong report.';
  @override String get stageAssigned => 'May Naka-assign na Opisyal';
  @override String get stageAssignedDesc =>
      'May opisyal ng barangay na inatasan.';
  @override String get stageResponding => 'Papunta Na ang Tutugon';
  @override String get stageRespondingDesc =>
      'Papunta na ang tulong sa iyong lokasyon.';
  @override String get stageOnScene => 'Nasa Lugar Na';
  @override String get stageOnSceneDesc =>
      'Dumating na ang tutugon sa lugar.';
  @override String get stageResolved => 'Naayos Na';
  @override String get stageResolvedDesc =>
      'Minarkahan ng barangay na naayos na ang insidente.';
  @override String get stageSubmittedWait =>
      'Hinihintay na matanggap ang report mo.';
  @override String get stageVerifiedWait =>
      'Susuriin ng kalihim ang report mo sa lalong madaling panahon.';
  @override String get stageAssignedWait =>
      'May opisyal na aatasang humawak nito.';
  @override String get stageRespondingWait =>
      'May ipadadalang tutugon sa iyo.';
  @override String get stageOnSceneWait =>
      'Darating ang tutugon sa lugar.';
  @override String get stageResolvedWait =>
      'Magsasara ito kapag naayos na ang insidente.';
  @override String get now => 'NGAYON';
  @override String stepOf(int current, int total) =>
      'Hakbang $current sa $total';
  @override String elapsedSoFar(String duration) => '$duration na';
  @override String elapsedTook(String duration) => 'Tumagal ng $duration';

  @override String get conversation => 'Usapan';
  @override String get messageBarangay => 'Magmensahe sa barangay…';
  @override String get noMessages =>
      'Wala pang mensahe. Maaari kang magpadala ng mensahe sa barangay tungkol '
      'sa report na ito.';
  @override String get you => 'Ikaw';
  @override String get resolutionNotes => 'Tala ng Paglutas';
  @override String photosCount(int n) => 'Mga Larawan ($n)';
  @override String videosCount(int n) => 'Mga Video ($n)';

  @override String get emergencyReport => 'Emergency Report';
  @override String get emergencyReportSubtitle =>
      'Para sa mga bisita at hindi residente. Ilagay ang iyong detalye upang '
      'mag-report ng emergency sa pinakamalapit na barangay.';
  @override String get contactNumber => 'Numero ng Kontak';
  @override String get continueLabel => 'Magpatuloy';
  // Kept short and shouty — this is the button someone presses in a panic.
  @override String get reportEmergency => 'MAG-REPORT NG EMERGENCY';
  @override String get callBarangay => 'Tawagan ang Barangay';
  @override String get uploadProof => 'Mag-upload ng patunay';
  @override String get cannotCall => 'Hindi ako makatawag';
  @override String get helpOnTheWay => 'Papunta na ang tulong';
  @override String get assignedToYourReport => 'Naka-assign sa report mo';
  @override String get locatingBarangay => 'Hinahanap ang iyong barangay…';
  @override String connectedTo(String barangay) => 'Nakakonekta sa $barangay';
  @override String get nrBannerNotified =>
      'Naabisuhan ang barangay — tawagan sila ngayon';
  @override String get nrBannerUploadProof =>
      'Mag-upload ng patunay para magpatuloy';
  @override String get nrBannerReviewing =>
      'Sinusuri ng barangay ang patunay mo';
  @override String get nrBannerResolved => 'Naayos na ang report';
  @override String get nrBannerDisregarded => 'Hindi pinansin ang report';
  @override String get nrOutsideCoverage =>
      'Nakalabas ka na sa sakop ng barangay';
  @override String get nrWaitingLocation => 'Hinihintay ang lokasyon mo…';
  @override String get nrCallBarangayCaps => 'TAWAGAN ANG BARANGAY';
  @override String get nrUploadProofCaps => 'MAG-UPLOAD NG PATUNAY';
  @override String get nrReviewing => 'Sinusuri ng barangay…';
  @override String get nrAlreadyFiled => 'Naihain na ang report';

  // Everyday spoken terms, not legal/blotter vocabulary — a resident in a
  // panic should recognise these at a glance.
  @override String get catTheft => 'Nakawan / Pagnanakaw';
  @override String get catAssault => 'Pananakit / Pambubugbog';
  @override String get catVehicular => 'Aksidente sa Sasakyan';
  @override String get catFire => 'Sunog';
  @override String get catFlooding => 'Baha';
  @override String get catNoise => 'Maingay na Kapitbahay';
  @override String get catVandalism => 'Bandalismo';
  @override String get catSuspicious => 'Kahina-hinalang Gawain';
  @override String get catDrugs => 'May Kinalaman sa Droga';
  @override String get catDomestic => 'Karahasan sa Tahanan';
  @override String get catPublicDisturbance => 'Gulo sa Pampublikong Lugar';
  @override String get catMedical => 'Emergency na Medikal';
  @override String get catOther => 'Iba pa';

  @override String get sev1 => 'Kritikal / Delikado sa Buhay';
  @override String get sev2 => 'Mataas / Seryoso';
  @override String get sev3 => 'Katamtaman';
  @override String get sev4 => 'Mababa / Maliit na Gulo';
  @override String get sev1Desc =>
      'May agarang panganib sa buhay. Kailangan ng emergency response.';
  @override String get sev2Desc =>
      'Seryosong insidente na kailangang asikasuhin agad.';
  @override String get sev3Desc =>
      'Katamtamang insidente na kailangang tugunan sa tamang panahon.';
  @override String get sev4Desc =>
      'Maliit na gulo o alalahanin sa komunidad.';

  @override String get dashboard => 'Dashboard';
  @override String get goodMorning => 'Magandang umaga';
  @override String get goodAfternoon => 'Magandang hapon';
  @override String get goodEvening => 'Magandang gabi';
  @override String get overview => 'Buod';
  @override String get needsAttention => 'Kailangan ng Agarang Aksyon';
  @override String get recentIncidents => 'Mga Bagong Insidente';
  @override String get viewAll => 'Tingnan Lahat';
  @override String get resolutionRate => 'Bahagdan ng Naayos';
  @override String get activeBySeverity => 'Aktibo ayon sa Antas';
  @override String get activityLog => 'Talaan ng Aktibidad';
  @override String get noIncidents => 'Walang Insidente';
  @override String get noIncidentsSubtitle =>
      'Wala pang report ng insidente sa inyong barangay.';
  @override String get emergencyFromVisitors =>
      'Mga emergency report mula sa bisita';
  // Tagalog has no plural -s, so both forms read naturally as one string.
  @override String flaggedNeedReview(int count) =>
      '$count naka-flag na report ang kailangang suriin';
  @override String awaitingAction(int count) =>
      '$count report ang naghihintay ng aksyon';
  @override String get map => 'Mapa';
  @override String get incidents => 'Mga Insidente';
  @override String get users => 'Mga User';
  @override String get analytics => 'Analytics';
  @override String get heatMap => 'Heat Map';
  @override String get lensAllReports => 'Lahat ng Report';
  @override String get lensCrime => 'Krimen';
  @override String get lensFire => 'Sunog';
  @override String get lensFlood => 'Baha';
  @override String get lensAccidents => 'Aksidente';
  @override String nothingInPeriod(String lens) =>
      'Walang $lens sa panahong ito';
  @override String get nonResidentReports => 'Report ng Hindi Residente';
  @override String get assign => 'Mag-assign';
  @override String get reassign => 'Palitan ang Assign';
  @override String get deploy => 'Ipadala';
  @override String get disregard => 'Huwag Pansinin';
  @override String get markResolved => 'Markahang Naayos';
  @override String get shareYourLocation => 'Ibahagi ang iyong lokasyon';
  @override String get sharingYourLocation => 'Ibinabahagi ang lokasyon mo';
  @override String get reviewProof => 'Tingnan ang patunay';
  @override String get verifyReport => 'Beripikahin ang Report';
  @override String get assignOfficial => 'Mag-assign ng Opisyal';
  @override String get dispatchResponders => 'Ipadala ang Tutugon';
  @override String get markOnScene => 'Markahang Nasa Lugar';
  @override String get stepBack => 'Bumalik sa nakaraan';
  @override String get barangayCoordinates => 'Koordinado ng barangay';
  @override String get coordsWhyItMatters =>
      'Ang ulat ng mga bisita ay ipinapadala sa pinakamalapit na sentro ng '
      'barangay. Ang maling pin ay nagpapadala ng emergency sa maling hall, '
      'kaya itakda ito sa mismong barangay hall.';
  @override String get coordsUpdated => 'Na-update ang koordinado';
  @override String get coordsAlreadyCurrent => 'Updated na ang lahat';
  @override String get fromSuggested => 'mula sa iminumungkahing punto';
  @override String get applyAll => 'Gamitin ang mungkahi';
  @override String get applyAllTitle => 'Gamitin ang mga iminumungkahing punto?';
  @override String get applyAllBody =>
      'na barangay ang lilipat sa mga puntong galing sa OpenStreetMap. Suriin '
      'ang bawat isa sa mapa pagkatapos — kayo lang ang nakakaalam kung nasaan '
      'talaga ang inyong hall.';
  @override String get tapMapToSetCentre => 'I-tap ang mapa para ilagay ang sentro.';
  @override String get centreShouldBeHall =>
      'Itakda ito sa barangay hall, hindi sa gitna ng lugar.';
  @override String get saveCentre => 'I-save ang sentro';
  @override String get suggested => 'IMINUMUNGKAHI';
  @override String get reporterEstablished => 'Matagal nang nag-uulat';
  @override String get reporterOrdinary => 'Kasaysayan ng nag-report';
  @override String get reporterCheckHistory => 'Suriin ang kasaysayan nito';
  @override String get reportsFiled => 'ulat na naisumite';
  @override String get flaggedFalse => 'napatunayang huwad';
  @override String get strikesOnRecord => 'strike';
  @override String get verifiedAccount => 'beripikado';
  @override String get trustNeverBlocks =>
      'Hindi hinaharangan ng kasaysayan ang ulat. Tumugon gaya ng dati.';
  @override String get possibleDuplicateTitle => 'Na-report na ba ito?';
  @override String get possibleDuplicateBody =>
      'Magkalapit ang mga ito sa lugar at oras. Pagsamahin lamang kung iisang '
      'insidente talaga.';
  @override String get notDuplicates => 'Magkaiba ito';
  @override String get sameIncident => 'Iisang insidente';
  @override String get openReport => 'Buksan';
  @override String get dupSamePhoto => 'Parehong larawan';
  @override String get dupSamePhotoAndPlace => 'Parehong larawan at lugar';
  @override String get dupNearby => 'Malapit';
  @override String get linkDuplicateTitle => 'Pagsamahin ang mga report?';
  @override String get linkDuplicateBody =>
      'Isasama ang mas bagong report sa mas naunang isa. Walang mabubura, at '
      'makakatanggap pa rin ng update ang lahat ng nag-report.';
  @override String get linkDuplicateConfirm => 'Pagsamahin';
  @override String get duplicateLinked => 'Napagsama ang mga report';
  @override String get duplicateDismissed => 'Pinanatiling hiwalay';
  @override String get peopleReportedThis => 'ang nag-report nito';
  @override String get guardianRequired =>
      'Pakikumpleto ang detalye ng magulang o guardian.';
  @override String get guardianSectionTitle => 'Magulang o guardian';
  @override String get guardianSectionWhy =>
      'Wala ka pang 18, kaya hinihingi ng batas ang pahintulot ng magulang o '
      'guardian bago itago ng barangay ang detalye mo. Puwede ka pa ring '
      'mag-report ng emergency kahit ano ang mangyari.';
  @override String get guardianName => 'Buong pangalan ng magulang / guardian';
  @override String get guardianPhone => 'Numero ng magulang / guardian';
  @override String get guardianRelationship => 'Relasyon sa iyo';
  @override String get relParent => 'Magulang';
  @override String get relGrandparent => 'Lolo / Lola';
  @override String get relSibling => 'Nakatatandang kapatid';
  @override String get relLegalGuardian => 'Legal na guardian';
  @override String get relOther => 'Iba pa';
  @override String get phoneAlreadyUsedTitle => 'Nakarehistro na ang numerong iyan';
  @override String get phoneAlreadyUsedBody =>
      'May account nang gumagamit ng numerong ito. Kung sa iyo ito, mag-sign in '
      'na lang sa halip na gumawa ng pangalawa.';
  @override String get continueAnyway => 'Magpatuloy pa rin';
  @override String get notSubmittedYet => 'Wala pang naipadala';
  @override String get guardianMissing =>
      'Wala pang 18 - walang pahintulot ng magulang';
  @override String get guardianOnRecord => 'May pahintulot ang magulang';
  @override String get idFrontTitle => 'Harap ng iyong ID';
  @override String get idFrontHint => 'Dapat mabasa ang pangalan at larawan mo';
  @override String get idBackTitle => 'Likod ng iyong ID';
  @override String get idBackHint => 'Patunay na tunay ang ID';
  @override String get idSelfieTitle => 'Selfie na hawak ang ID';
  @override String get idSelfieHint => 'Camera lang, para makita na ikaw nga';
  @override String get idAllSubmitted => 'Nakumpleto na ang tatlo';
  @override String get idAllSubmittedNote =>
      'Susuriin ito ng opisyal ng barangay. Puwede mo pang palitan ang alinman '
      'hanggang doon.';
  @override String get idPhotoSaved => 'Na-save ang larawan';
  @override String get selectIdType => 'Anong ID ang gagamitin mo?';
  @override String get takeAPhoto => 'Kumuha ng larawan';
  @override String get chooseFromGallery => 'Pumili sa gallery';
  @override String get addPhoto => 'Idagdag';
  @override String get ofThree => 'sa 3';
  @override String get fieldRequired => 'Kailangan';
  @override String get myAccount => 'Aking account';
  @override String get editDetails => 'I-edit ang detalye';
  @override String get detailsUpdated => 'Na-update ang detalye';
  @override String get addStaff => 'Magdagdag ng tauhan';
  @override String get addStaffSubtitle =>
      'Pumili ng rehistradong residente na bibigyan ng tungkulin sa barangay hall.';
  @override String get pickPosition => 'Pumili ng posisyon';
  @override String get noEligibleAccounts => 'Walang maaaring bigyan ng tungkulin';
  @override String get noEligibleAccountsHint =>
      'Kailangan muna silang mag-rehistro at ma-verify, saka sila lalabas dito.';
  @override String get promoteTitle => 'Bigyan ng tungkulin?';
  @override String get promoteBody =>
      'Makikita nila ang mga report, residente at kagamitan ng barangay. Puwede '
      'mong alisin ang tungkulin mamaya.';
  @override String get promoteConfirm => 'Ibigay ang tungkulin';
  @override String get promoted => 'Naibigay ang tungkulin';
  @override String get promotedNotifTitle => 'May tungkulin ka na sa barangay';
  @override String get promotedNotifBody =>
      'Binigyan ka ng barangay ng posisyon sa hall. Mag-sign out at mag-sign in '
      'ulit para makita ang mga tool ng opisyal.';
  @override String get rejectIdTitle => 'Humingi ng bagong larawan?';
  @override String get rejectIdBody =>
      'Aalisin ang ID at makakapag-upload sila ulit. Hindi nito nila-lock o '
      'binubura ang account nila.';
  @override String get rejectIdConfirm => 'Humingi ng bago';
  @override String get idRejected => 'Humingi ng bagong larawan';
  @override String get idRejectedNotifTitle => 'Pakiulit ang pag-upload ng ID';
  @override String get idRejectedNotifBody =>
      'Hindi mabasa ng barangay ang ID na ipinadala mo. Mag-upload ng mas '
      'malinaw na larawan na makikita ang pangalan at tirahan mo.';
  @override String get verificationHeading => 'Isang hakbang na lang';
  @override String get verificationBlurb =>
      'Nagawa na ang account mo. Mag-upload ng valid ID at susuriin ito ng '
      'opisyal ng barangay - hindi na kailangang pumunta sa hall.';
  @override String get whatToDoNext => 'Paano ito gumagana';
  @override String get reviewedManuallyNote =>
      'May taong sumusuri sa bawat ID, kaya hindi ito agad-agad.';
  @override String get uploadYourId => 'I-upload ang valid ID mo';
  @override String get uploadIdTitle => 'Mag-verify mula sa bahay';
  @override String get uploadIdSubtitle =>
      'Kunan ng larawan ang kahit anong government ID na may pangalan at tirahan mo. '
      'Hindi na kailangang pumunta sa barangay hall.';
  @override String get retakeId => 'Palitan ang larawan';
  @override String get idSubmitted => 'Naipadala ang ID';
  @override String get idSubmittedNote =>
      'Sinusuri ito ng barangay ninyo. Pwede mong palitan kung malabo ang kuha.';
  @override String get idUploading => 'Ina-upload…';
  @override String get idPrivacyNote =>
      'Ang opisyal lang ng barangay mo ang makakakita nito. Hindi ito pampubliko.';
  @override String get stepUploadId => 'I-upload ang ID mo';
  @override String get stepUploadIdDesc =>
      'Larawan ng kahit anong government ID. Isang minuto lang.';
  @override String get stepOfficialChecks => 'Susuriin ng opisyal';
  @override String get stepOfficialChecksDesc =>
      'Susuriin ng opisyal ng barangay ang ID mo at bubuksan ang account mo.';
  @override String get viewSubmittedId => 'Tingnan ang ipinasang ID';
  @override String get noIdSubmitted => 'Wala pang ipinasang ID';
  @override String get aiSuggestsTitle => 'Mungkahing antas';
  @override String aiSuggestsLevel(String level) => 'Mukhang $level ito';
  @override String get aiUseSuggestion => 'Gamitin ito';
  @override String get aiDismiss => 'Panatilihin ang akin';
  @override String get aiChecking => 'Sinusuri ang larawan mo…';
  @override String get aiAdvisoryNote =>
      'Mungkahi lang mula sa larawan mo. Ikaw ang magpapasya.';
  @override String get privacyNotice => 'Paunawa sa Privacy';
  @override String get privacyConsentLabel =>
      'Nabasa ko at sumasang-ayon ako sa Paunawa sa Privacy.';
  @override String get privacyConsentRequired =>
      'Pakibasa at tanggapin ang Paunawa sa Privacy para magpatuloy.';
  @override String get readNotice => 'Basahin';
  @override String get requestDeletion => 'Humiling ng pagbura ng account';
  @override String get requestDeletionTitle => 'Humiling ng pagbura ng account?';
  @override String get requestDeletionBody =>
      'Maaabisuhan ang barangay ninyo at aalisin nila ang personal mong detalye.\n\n'
      'Ang mga report na inihain mo ay mananatili bilang tala ng barangay sa '
      'tunay na emergency, ngunit aalisin dito ang pangalan at kontak mo.';
  @override String get deletionRequested =>
      'Naipadala ang hiling. Aaksyunan ito ng barangay ninyo.';
  @override String get deletionAlreadyRequested => 'Naihiling na ang pagbura';
  @override String get walkUpReport => 'HINDI RESIDENTE';
  @override String get residentReports => 'Report ng residente';
  @override String get nonResidentReportsCount => 'Report ng hindi residente';
  @override String get fullBlast => 'Alertuhin Lahat';
  @override String get fullBlastConfirmTitle =>
      'Alertuhin ang buong barangay hall?';
  @override String get fullBlastConfirmBody =>
      'Agad na maaabisuhan ang bawat kawani ng hall, kahit kanino naka-assign '
      'ang kaso. Gamitin ito sa emergency na hindi na pwedeng maghintay.';
  @override String fullBlastSent(int count) => 'Naalertuhan ang $count kawani';
  @override String get fullBlastNobody =>
      'Wala pang may hawak na posisyon sa barangay na ito — walang maaalertuhan.';
  @override String get integrityWarning => 'Suriing mabuti ang report na ito';
  @override String get integrityMocked =>
      'Nag-ulat ang device ng pekeng lokasyon sa GPS.';
  @override String get integrityVpn => 'Ipinadala habang naka-VPN.';
  @override String get integrityAdvisory =>
      'Hindi ibig sabihin nito na peke ang report — beripikahin gaya ng dati.';
  @override String get staleCaseTitle => 'Tapos na ba ang kasong ito?';
  @override String staleCaseBody(int days) => days <= 1
      ? 'walang update sa loob ng isang araw. Kung ayos na, isara mo na dito.'
      : 'walang update sa loob ng $days araw. Kung ayos na, isara mo na dito.';
  @override String get stillActive => 'Aktibo pa';
  @override String get caseMarkedResolved => 'Namarkahang naayos ang kaso';
  @override String get staleCaseSnoozed => 'Naitala — tatanungin ulit bukas';
  @override String get dateRange => 'Saklaw ng Petsa';
  @override String get rangeLast7 => '7 araw';
  @override String get rangeLast30 => '30 araw';
  @override String get rangeLast90 => '90 araw';
  @override String get rangeAllTime => 'Lahat';
  @override String showingRange(String range) => 'Ipinapakita: $range';
  @override String get dateOfBirth => 'Petsa ng Kapanganakan';
  @override String get dateOfBirthOptional =>
      'Petsa ng Kapanganakan (opsyonal)';
  @override String get dobWhyAsk =>
      'Ginagamit lamang para sa istatistika ng barangay. Hindi ipinapakita '
      'kaninuman.';
  @override String get selectDate => 'Pumili ng petsa';
  @override String get totalUsers => 'Kabuuang User';
  @override String get residentsCount => 'Mga Residente';
  @override String get personnelCount => 'Kawani ng Barangay';
  @override String get age45Plus => 'Edad 45 pataas';
  @override String get userStatistics => 'Istatistika ng User';
  @override String get dobNotSet => 'Wala pa';
  @override String get ageUnknownNote =>
      'na account ang walang nakatalang petsa ng kapanganakan at hindi kabilang.';
  @override String get theReporter => 'ang nag-report';
  @override String callPersonQ(String name) => 'Tawagan si $name?';
  @override String willDial(String phone) => 'Tatawagan nito ang $phone.';
  @override String get onb1Title => 'Manatiling Ligtas,\nManatiling Alam';
  @override String get onb1Sub =>
      'Makatanggap ng agarang abiso tungkol sa mga insidente sa barangay mo. '
      'Isang pindot lang ang kaligtasan ng komunidad mo.';
  @override String get onb2Title => 'Mag-report sa\nIlang Segundo';
  @override String get onb2Sub =>
      'Kunan ang pangyayari, itakda ang lokasyon, at magpadala ng report agad - '
      'kahit walang internet.';
  @override String get onb3Title => 'Mabilis na\nTugon ng Opisyal';
  @override String get onb3Sub =>
      'Agad na naaabisuhan ang mga opisyal ng barangay at kaya nilang '
      'subaybayan, i-update, at ayusin ang mga report nang live.';
  @override String get aboutTheApp => 'Tungkol sa App';
  @override String get keyFeatures => 'Mga Pangunahing Tampok';
  @override String get coverageArea => 'Saklaw na Lugar';
  @override String get technology => 'Teknolohiya';
  @override String get legal => 'Legal';
  @override String get city => 'Lungsod';
  @override String get platform => 'Plataporma';
  @override String get backend => 'Backend';
  @override String get storage => 'Imbakan';
  @override String get maps => 'Mapa';
  @override String get featGeoTagged => 'Pag-uulat na May Lokasyon';
  @override String get featMap => 'Interaktibong Mapa ng Buong Lungsod';
  @override String get featTracking => 'Live na Pagsubaybay sa Katayuan';
  @override String get featRoles => 'Kontrol sa Access ayon sa Tungkulin';
  @override String get featAnalytics => 'Dashboard ng Analytics at Estadistika';
  @override String get featAudit => 'Kumpletong Talaan ng Aktibidad';
  @override String get fitEveryone => 'Ipakita ang lahat';
  @override String get centerOnMe => 'Ituon sa akin';
  @override String get centerOnThis => 'Ituon dito';
  @override String get distance => 'Layo';
  @override String get lastUpdate => 'Huling update';
  @override String get call => 'Tumawag';
  @override String get live => 'LIVE';
  @override String get incidentHeatMap => 'Heat Map ng Insidente';
  @override String get fitToData => 'Ipakita ang datos';
  @override String get period => 'Panahon';
  @override String get isolated => 'Nag-iisa';
  @override String get hotspot => 'Hotspot';
  @override String get topHotspots => 'Pinakamataas na hotspot';
  @override String get callReporter => 'Tawagan ang nag-report';
  @override String get evidenceSubmitted => 'Naipadala ang ebidensya';
  @override String get proofNotLoaded => 'Hindi ma-load ang patunay';
  @override String get tapToInspect => 'Pindutin para tingnan';
  @override String get disregardThisReport => 'Huwag pansinin ang report na ito?';
  @override String get stayInTheApp => 'Manatili sa app';
  @override String get sendThisReport => 'Ipadala ang emergency report na ito?';
  @override String get barangayNotified => 'Naabisuhan ang barangay';
  @override String get reasonNoLoad => 'Walang load';
  @override String get reasonNoSignal => 'Walang signal';
  @override String get reasonOther => 'Ibang dahilan';
  @override String get visitBarangayHall => 'Pumunta sa Barangay Hall';
  @override String get visitBarangayHallDesc =>
      'Pumunta mismo sa oras ng opisina.';
  @override String get bringValidId => 'Magdala ng Valid ID';
  @override String get officialApproves =>
      'Aaprubahan ng Opisyal ang Account Mo';
  @override String get youGetNotified => 'Maaabisuhan Ka';
  @override String get backToLogin => 'Bumalik sa Login';
  @override String get resetPassword => 'I-reset ang Password';
  @override String get sendResetLink => 'Ipadala ang Reset Link';
  @override String get checkYourEmail => 'Tingnan ang Email Mo';
  @override String get reportNotFound => 'Hindi natagpuan ang report';
  @override String get reportDeletedOk => 'Matagumpay na nabura ang report';
  @override String get homeAddress => 'Tirahan';
  @override String get saveChanges => 'I-save ang Pagbabago';
  @override String get notifications => 'Mga Abiso';
  @override String get markAllRead => 'Markahang nabasa lahat';
  @override String get notificationCleared => 'Naalis ang abiso';
  @override String get barangayOffice => 'Opisina ng Barangay';
  @override String get emailUs => 'Mag-email sa Amin';
  @override String get emergencyHotline => 'Emergency Hotline';
  @override String get offlineReportsSubmitted =>
      'Matagumpay na naipadala ang mga offline na report';
  @override String get onlyPendingDeletable =>
      'Ang naghihintay na report lang ang pwedeng burahin';
  @override String get incidentMap => 'Mapa ng Insidente';
  @override String get newPassword => 'Bagong Password';
  @override String get updatePassword => 'I-update ang Password';
  @override String get couldNotPlayVideo => 'Hindi ma-play ang video';
  @override String get unableToGetLocation => 'Hindi makuha ang lokasyon';
  @override String get bulkDelete => 'Maramihang Pagbura';
  @override String bulkAction(String action) => 'Maramihang $action';
  @override String levelLabel(int level, String label) =>
      'Antas $level: $label';
  @override String get cityWideOverview => 'Buod ng Buong Lungsod';
  @override String get allBarangaysView =>
      'Lahat ng barangay - tanaw sa buong lungsod';
  @override String get criticalHighPriority =>
      'Kritikal at Mataas na Prayoridad';
  @override String get cityResolutionRate => 'Bahagdan ng Naayos sa Lungsod';
  @override String get unresolvedOnly => 'Hindi pa naaayos lang';
  @override String get cityWideIncidentMap =>
      'Mapa ng Insidente sa Buong Lungsod';
  @override String get fitAllIncidents => 'Ipakita lahat ng insidente';
  @override String get allIncidentReports => 'Lahat ng Report ng Insidente';
  @override String acrossAllBarangays(int total) =>
      'Sa lahat ng barangay · $total lahat';
  @override String get searchAllHint =>
      'Maghanap ayon sa paglalarawan, uri, barangay, nag-report...';
  @override String get noReportsTitle => 'Walang Report';
  @override String get noReportsMatchFilters =>
      'Walang report na tumugma sa filter mo.';
  @override String get noOfficials => 'Walang Opisyal';
  @override String get noResidents => 'Walang Residente';
  @override String get noPendingVerifications =>
      'Walang Naghihintay na Beripikasyon';
  @override String get allPendingReviewed =>
      'Nasuri na ang lahat ng naghihintay na account.';
  @override String get locked => 'NAKA-LOCK';
  @override String get removeAdminRole => 'Alisin ang Admin Role';
  @override String get makeOfficial => 'Gawing Opisyal';
  @override String get submittedId => 'Isinumiteng ID:';
  @override String get reject => 'Tanggihan';
  @override String get approve => 'Aprubahan';
  @override String get responsePerformance => 'Bilis ng Pagtugon';
  @override String get topCategories => 'Pinakamadalas na Uri';
  @override String get incidentsLast7Days => 'Insidente - Huling 7 Araw';
  @override String get analyticsReports => 'Analytics at Ulat';
  @override String get noDataYet => 'Wala pang datos';
  @override String get noData => 'Walang datos';
  @override String get avgResolutionTime => 'Karaniwang Oras ng Pag-ayos';
  // SLA kept as-is - a standard term in the officials' own reporting.
  @override String get slaCompliance => 'Pagsunod sa SLA (≤48h)';
  @override String get currentlyOverdue => 'Lampas na sa Takdang Oras';
  @override String get auditStatusUpdate => 'Update sa Katayuan';
  @override String get auditSeverityChanged => 'Binago ang Antas';
  @override String get auditAssignment => 'Pag-assign';
  @override String get auditUserVerified => 'Naberipika ang User';
  @override String get auditAccountLocked => 'Na-lock ang Account';
  @override String get auditAccountUnlocked => 'Na-unlock ang Account';
  @override String get auditReportDeleted => 'Nabura ang Report';
  @override String get auditReportFlagged => 'Naka-flag ang Report';
  @override String get addressOptional => 'Tirahan (opsyonal)';
  @override String get selectBarangay => 'Pumili ng Barangay';
  @override String get flagAsFraudulent => 'Markahang Peke';
  @override String get quickActions => 'Mabilisang Aksyon';
  @override String get statusProgress => 'Progreso ng Katayuan';
  @override String get assignedTo => 'Naka-assign Kay';
  @override String get severityLevel => 'Antas ng Panganib';
  @override String get evidencePhotos => 'Larawang Ebidensya';
  @override String get evidenceVideos => 'Video na Ebidensya';
  @override String get officialUpdates => 'Update Mula sa Barangay';
  @override String get postUpdateHint => 'Mag-post ng update sa residente...';
  @override String get noActivityLogged => 'Wala pang naitalang aktibidad.';
  @override String get resolveIncident => 'Ayusin ang Insidente';
  @override String get addResolutionNotes =>
      'Magdagdag ng tala ng paglutas (opsyonal):';
  @override String get resolutionNotesHint =>
      'Paano naayos ang insidenteng ito?';
  @override String get assignTo => 'I-assign Kay';
  @override String get noOfficialsInBarangay =>
      'Walang opisyal na natagpuan sa barangay na ito.';
  @override String get removeAssignment => 'Alisin ang Assignment';
  @override String get deleteReport => 'Burahin ang Report';
  @override String get applyStrike => 'Maglagay ng Strike';
  @override String get reportDeleted => 'Nabura ang report';
  @override String get notFound => 'Hindi natagpuan';
  @override String callPerson(String name) => 'Tawagan si $name';
  @override String get incidentManagement => 'Pamamahala ng Insidente';
  @override String get userManagement => 'Pamamahala ng User';
  @override String get searchIncidentsHint =>
      'Maghanap ng paglalarawan, uri, nag-report…';
  @override String get noIncidentsMatchFilters =>
      'Walang report na tumugma sa filter mo.';
  @override String get resolve => 'Ayusin';
  @override String get delete => 'Burahin';
  @override String get unlock => 'I-unlock';
  @override String get lock => 'I-lock';
  @override String get verify => 'Beripikahin';
  @override String get assignPosition => 'Magtakda ng Posisyon';
  @override String get removePosition => 'Alisin ang Posisyon';
  @override String get noActiveNonResidentReports =>
      'Walang aktibong report mula sa hindi residente';
  @override String get trackLive => 'Subaybayan';
  @override String get noLocationYet => 'Wala pang natatanggap na lokasyon';
  @override String get whoIsResponding => 'Sino ang tutugon?';
  @override String get restoreToPending => 'Ibalik sa Naghihintay';
  @override String get reopen => 'Buksang Muli';
}

/// Display label for a stored `incidents.category` value.
///
/// Takes the canonical English string as written in the database and returns
/// what the user should see. Unknown values pass through unchanged so a
/// category added later never renders blank.
String categoryLabel(AppStrings t, String canonical) => switch (canonical) {
      'Theft / Robbery' => t.catTheft,
      'Physical Assault' => t.catAssault,
      'Vehicular Accident' => t.catVehicular,
      'Fire' => t.catFire,
      'Flooding' => t.catFlooding,
      'Noise Disturbance' => t.catNoise,
      'Vandalism' => t.catVandalism,
      'Suspicious Activity' => t.catSuspicious,
      'Drug-Related' => t.catDrugs,
      'Domestic Violence' => t.catDomestic,
      'Public Disturbance' => t.catPublicDisturbance,
      'Medical Emergency' => t.catMedical,
      'Other' => t.catOther,
      _ => canonical,
    };

/// Display label for a severity level.
///
/// `sev1`..`sev4` are named for the *wording tiers*, not the numbers:
/// sev1 is the Critical string and sev4 the Low one. The numeric scale was
/// reversed on 2026-08-25 (4 = Critical), so the mapping below is inverted
/// rather than the ~40 translation keys being renamed in two languages.
String severityLabelFor(AppStrings t, int level) => switch (level) {
      4 => t.sev1,
      3 => t.sev2,
      2 => t.sev3,
      _ => t.sev4,
    };

String severityDescriptionFor(AppStrings t, int level) => switch (level) {
      4 => t.sev1Desc,
      3 => t.sev2Desc,
      2 => t.sev3Desc,
      _ => t.sev4Desc,
    };

/// Convenience accessor: `context.s.reportEmergency`
extension AppStringsX on BuildContext {
  AppStrings get s => AppStringsScope.of(this);
}

/// Makes the active [AppStrings] available down the tree and rebuilds
/// everything below when the language changes.
class AppStringsScope extends InheritedWidget {
  final AppStrings strings;
  final AppLanguage language;

  const AppStringsScope({
    super.key,
    required this.strings,
    required this.language,
    required super.child,
  });

  static AppStrings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    // Falls back to English rather than throwing: a missing scope should
    // degrade to readable text, never a crash mid-emergency.
    return scope?.strings ?? AppStrings.en;
  }

  @override
  bool updateShouldNotify(AppStringsScope old) => old.language != language;
}
