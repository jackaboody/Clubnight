// lib/data/repositories/court_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/court.dart';

class CourtRepository {
  final FirebaseFirestore _db;

  CourtRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  Stream<List<Court>> watchAllCourts() {
    return _db
        .collection('courts')
        .orderBy('number')
        .snapshots()
        .map((snap) => snap.docs.map(Court.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Seeds the 6 courts if they don't already exist. Call once during setup.
  Future<void> seedCourts() async {
    final batch = _db.batch();
    for (int i = 1; i <= 6; i++) {
      final ref = _db.collection('courts').doc('court_$i');
      final snap = await ref.get();
      if (!snap.exists) {
        batch.set(ref, {
          'number': i,
          'mode': CourtMode.singles.name,
          'currentMatchId': null,
          'nextMatchId': null,
        });
      }
    }
    await batch.commit();
  }

  Future<void> setCourtMode(String courtId, CourtMode mode) {
    return _db.collection('courts').doc(courtId).update({
      'mode': mode.name,
      // Clear scheduled matches when switching to holding.
      if (mode == CourtMode.holding) ...{
        'currentMatchId': null,
        'nextMatchId': null,
      },
    });
  }
}
