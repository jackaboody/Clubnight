// domain/models/court.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum CourtMode { singles, doubles, holding }

class Court {
  final String id;
  final int number;
  final CourtMode mode;
  final String? currentMatchId;
  final String? nextMatchId;

  const Court({
    required this.id,
    required this.number,
    required this.mode,
    this.currentMatchId,
    this.nextMatchId,
  });

  factory Court.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Court(
      id: doc.id,
      number: d['number'] as int,
      mode: CourtMode.values.byName(d['mode'] as String? ?? 'singles'),
      currentMatchId: d['currentMatchId'] as String?,
      nextMatchId: d['nextMatchId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'number': number,
        'mode': mode.name,
        'currentMatchId': currentMatchId,
        'nextMatchId': nextMatchId,
      };

  bool get isAvailable =>
      mode != CourtMode.holding && currentMatchId == null;

  bool get isHolding => mode == CourtMode.holding;

  Court copyWith({
    CourtMode? mode,
    String? currentMatchId,
    String? nextMatchId,
  }) =>
      Court(
        id: id,
        number: number,
        mode: mode ?? this.mode,
        currentMatchId: currentMatchId ?? this.currentMatchId,
        nextMatchId: nextMatchId ?? this.nextMatchId,
      );
}
