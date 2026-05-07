// lib/core/seeder.dart
//
// Runs once on first launch: writes 6 courts + default config to Firestore
// only if those documents don't already exist.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/app_config.dart';
import 'package:squash_social/domain/models/court.dart';

class Seeder {
  final FirebaseFirestore _db;

  Seeder({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Future<void> seedIfNeeded() async {
    await Future.wait([
      _seedCourts(),
      _seedConfig(),
    ]);
  }

  Future<void> _seedCourts() async {
    final snapshot = await _db.collection('courts').limit(1).get();
    if (snapshot.docs.isNotEmpty) return; // already seeded

    final batch = _db.batch();
    for (int i = 1; i <= 6; i++) {
      final ref = _db.collection('courts').doc('court$i');
      final court = Court(
        id: 'court$i',
        number: i,
        mode: CourtMode.singles,
      );
      batch.set(ref, court.toFirestore());
    }
    await batch.commit();
  }

  Future<void> _seedConfig() async {
    final ref = _db.collection('config').doc('settings');
    final snapshot = await ref.get();
    if (snapshot.exists) return; // already seeded

    await ref.set(const AppConfig().toFirestore());
  }
}
