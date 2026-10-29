import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/widgets/incident_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/render.dart';

IncidentModel _incident(String status, int hoursOld, {String desc = 'asdasd'}) {
  final now = DateTime.now();
  return IncidentModel(
    id: 'incident-1-aaaaaaaaaaaa',
    barangayId: 'b1',
    category: 'Public Disturbance',
    description: desc,
    severityLevel: 2,
    status: status,
    latitude: 13.94,
    longitude: 121.16,
    createdAt: now.subtract(Duration(hours: hoursOld)),
    updatedAt: now,
  );
}

void main() {
  setUpAll(loadRealFonts);

  for (final width in [400.0, 640.0]) {
    testWidgets('IncidentCard lays out cleanly at ${width.toInt()}px', (tester) async {
      useSize(tester, Size(width, 720));
      await tester.pumpWidget(renderApp(
        Column(
          children: [
            IncidentCard(
              incident: _incident('responding', 700),
              showReporter: true,
            ),
            IncidentCard(
              incident: _incident('pending', 3,
                  desc: 'A long description that runs over to a second line '
                      'so the card has to grow to fit it all properly'),
              showReporter: true,
            ),
          ],
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      // No debug-check workarounds here, on purpose. Before the layout fix this
      // threw (LayoutBuilder inside IntrinsicHeight) and overflowed by 13px.
      expect(tester.takeException(), isNull);
      final path = await snap(tester, 'card_${width.toInt()}');
      // ignore: avoid_print
      print('RENDERED $path');
    });
  }
}
