import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:barangay_safety_app/models/response_metric.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/screens/shared/response_analytics_screen.dart';
import 'package:barangay_safety_app/services/response_metrics_service.dart';
import 'package:barangay_safety_app/utils/manila_time.dart';
import 'package:barangay_safety_app/utils/response_export.dart';
import 'package:barangay_safety_app/utils/response_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/render.dart';

ResponseMetricRow _row(
  String id, {
  String barangay = 'Barangay 3',
  String category = 'Fire',
  int severity = 4,
  String status = 'resolved',
  required DateTime submitted,
  int? firstResponse,
  int? dispatch,
  int level = 0,
  String? responder = 'Tony Tanod',
}) {
  DateTime? after(int? s) => s == null ? null : submitted.add(Duration(seconds: s));
  return ResponseMetricRow(
    reportId: id,
    residentName: 'Resident $id',
    barangayId: 'b-$barangay',
    barangayName: barangay,
    category: category,
    severity: severity,
    finalStatus: status,
    submittedAt: submitted,
    firstActionAt: after(firstResponse),
    dispatchedAt: after(dispatch),
    escalationLevel: level,
    level1At: level >= 1 ? submitted.add(const Duration(minutes: 5)) : null,
    level3At: level >= 3 ? submitted.add(const Duration(minutes: 15)) : null,
    responderName: responder,
    responderRole: responder == null ? null : 'tanod',
    secsToFirstResponse: firstResponse,
    secsToDispatch: dispatch,
    answeredWithin5: firstResponse == null ? null : firstResponse <= 300,
    answeredWithin10: firstResponse == null ? null : firstResponse <= 600,
    answeredWithin15: firstResponse == null ? null : firstResponse <= 900,
  );
}

class _Source implements ResponseDataSource {
  _Source(this.rows, {this.failLog = false});

  final List<ResponseMetricRow> rows;
  final bool failLog;
  final loggedExports = <Map<String, Object?>>[];

  @override
  Future<({List<ResponseMetricRow> rows, bool truncated})> fetchRows({
    required DateTime from,
    required DateTime to,
  }) async =>
      (rows: rows, truncated: false);

  @override
  Future<List<StatusLogRow>> fetchStatusLogs(List<String> ids) async => [
        for (final r in rows.where((r) => ids.contains(r.reportId)))
          StatusLogRow(
            reportId: r.reportId,
            fromStatus: null,
            toStatus: 'pending',
            changedByName: r.residentName,
            changedByRole: 'resident',
            changedAt: r.submittedAt,
          ),
      ];

  @override
  Future<List<EscalationEventRow>> fetchEscalations(List<String> ids) async => const [];

  @override
  Future<void> logExport({
    required String userId,
    required String? userName,
    required String? barangayId,
    required String format,
    required ExportFilters filters,
    required int rowCount,
  }) async {
    if (failLog) throw Exception('database says no');
    loggedExports.add({'user': userId, 'format': format, 'rows': rowCount, 'filters': filters.toJson()});
  }
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);
  final UserModel _user;
  @override
  UserModel? get user => _user;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

UserModel _admin({bool superAdmin = false}) => UserModel(
      id: 'admin-1',
      email: 'a@x.ph',
      fullName: 'Juan Admin',
      phone: '0917',
      role: superAdmin ? 'superadmin' : 'admin',
      position: 'captain',
      barangayId: 'b-Barangay 3',
      isVerified: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

// 20 Oct 2026, 09:00 Manila.
final _day = DateTime.utc(2026, 10, 20, 1);

final _rows = [
  _row('r1', submitted: _day, firstResponse: 120, dispatch: 300),
  _row('r2', submitted: _day.add(const Duration(hours: 1)), firstResponse: 420, dispatch: 900, level: 1, category: 'Noise', severity: 1),
  _row('r3', submitted: _day.add(const Duration(days: 1)), firstResponse: 1000, dispatch: 1500, level: 3, barangay: 'Barangay 7'),
  _row('r4', submitted: _day.add(const Duration(days: 1, hours: 2)), firstResponse: null, status: 'pending', level: 2, responder: null),
];

void main() {
  setUpAll(loadRealFonts);

  Future<_Source> mount(
    WidgetTester tester, {
    double width = 1300,
    UserModel? user,
    _Source? source,
    List<({String name, Uint8List bytes, String mime})>? downloads,
  }) async {
    useSize(tester, Size(width, 1700));
    final src = source ?? _Source(_rows);
    await tester.pumpWidget(renderApp(
      ResponseAnalyticsScreen(
        source: src,
        today: DateTime(2026, 10, 25),
        canExport: true,
        downloader: (name, bytes, {required mimeType}) async =>
            downloads?.add((name: name, bytes: bytes, mime: mimeType)),
      ),
      extraProviders: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(user ?? _admin())),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return src;
  }

  testWidgets('shows the numbers, computed from the loaded reports', (tester) async {
    await mount(tester);
    final s = summarizeRows(_rows);
    expect(tester.takeException(), isNull);

    expect(find.text('4'), findsWidgets); // reports
    expect(find.text('3 answered · 1 waiting now'), findsOneWidget);
    expect(find.text(formatMinSec(s.firstResponse.median)), findsWidgets); // 7:00
    expect(find.text('7:00'), findsWidgets);
    expect(find.text('33%'), findsOneWidget); // 1 of 3 within 5 min
    expect(find.text('67%'), findsNWidgets(2)); // 2 of 3 within 10 min, and again within 15
    expect(find.text('Level 3 — Unattended'), findsOneWidget);
    expect(find.textContaining('faster than the best manual case'), findsOneWidget);
    await snap(tester, 'response_analytics_wide');
  });

  testWidgets('lays out at phone and tablet widths without overflow', (tester) async {
    for (final w in [400.0, 820.0]) {
      await mount(tester, width: w);
      expect(tester.takeException(), isNull, reason: 'width $w');
      await snap(tester, 'response_analytics_${w.toInt()}');
    }
  });

  testWidgets('filters narrow the cards and the export together', (tester) async {
    final downloads = <({String name, Uint8List bytes, String mime})>[];
    final src = await mount(tester, downloads: downloads);

    // Category: Noise -> only r2 remains.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Noise').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 answered · 0 waiting now'), findsOneWidget);

    await tester.tap(find.text('Export CSV'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(downloads, hasLength(1));
    final csv = utf8.decode(downloads.single.bytes.sublist(3));
    final lines = const LineSplitter().convert(csv);
    expect(lines, hasLength(2), reason: 'header + the one Noise report');
    expect(lines[1], contains('Resident r2'));
    expect(src.loggedExports.single['rows'], 1);
  });

  testWidgets('the Excel summary shows the same figures as the screen', (tester) async {
    final downloads = <({String name, Uint8List bytes, String mime})>[];
    final src = await mount(tester, downloads: downloads);

    await tester.tap(find.text('Export Excel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(downloads, hasLength(1));
    final d = downloads.single;
    expect(d.name, 'response_time_report_barangay_3_2026-09-26_2026-10-25.xlsx'.replaceFirst('barangay_3', 'all_barangays'));
    expect(d.mime, contains('spreadsheetml'));
    expect(d.bytes.sublist(0, 2), [0x50, 0x4B]); // "PK" — a zip

    final zip = ZipDecoder().decodeBytes(d.bytes);
    final summary = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    final s = summarizeRows(_rows);
    expect(summary, contains(formatMinSec(s.firstResponse.median)));
    expect(summary, contains('${s.total}'));
    expect(summary, contains('${s.reachedLevel3}'));

    // The export was recorded, with the filters and the row count.
    expect(src.loggedExports, hasLength(1));
    expect(src.loggedExports.single['format'], 'xlsx');
    expect(src.loggedExports.single['rows'], 4);
    expect(src.loggedExports.single['user'], 'admin-1');
  });

  testWidgets('Word: a .docx summary is offered, downloaded, and recorded as docx', (tester) async {
    final downloads = <({String name, Uint8List bytes, String mime})>[];
    final src = await mount(tester, downloads: downloads);

    await tester.tap(find.text('Export Word'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(downloads, hasLength(1));
    final d = downloads.single;
    expect(d.name, endsWith('.docx'));
    expect(d.mime, contains('wordprocessingml'));
    expect(d.bytes.sublist(0, 2), [0x50, 0x4B]);
    final doc = utf8.decode(ZipDecoder().decodeBytes(d.bytes).findFile('word/document.xml')!.content as List<int>);
    expect(doc, contains('Response Time Report'));
    expect(doc, contains('7:00')); // same median first response the cards show
    expect(src.loggedExports.single['format'], 'docx');
    expect(src.loggedExports.single['rows'], 4);
  });

  testWidgets('Excel, Word and CSV are all offered — and there is no PDF button', (tester) async {
    await mount(tester);
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Export Word'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.textContaining('PDF'), findsNothing);
  });

  testWidgets('if the export cannot be recorded, nothing is downloaded', (tester) async {
    final downloads = <({String name, Uint8List bytes, String mime})>[];
    await mount(tester, downloads: downloads, source: _Source(_rows, failLog: true));

    await tester.tap(find.text('Export Excel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(downloads, isEmpty);
    expect(find.textContaining('Nothing was downloaded'), findsOneWidget);
  });

  testWidgets('an admin does not get a barangay filter', (tester) async {
    await mount(tester);
    expect(find.text('Barangay'), findsNothing);
  });

  testWidgets('a superadmin does', (tester) async {
    await mount(tester, user: _admin(superAdmin: true));
    expect(find.text('Barangay'), findsOneWidget);
  });

  testWidgets('no reports yet: says so instead of showing zeros', (tester) async {
    await mount(tester, source: _Source(const []));
    expect(find.textContaining('No reports in this date range'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);
    // Nothing to export, so the button is disabled.
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Export Excel'), matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });
}
