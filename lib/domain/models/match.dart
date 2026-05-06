// lib/domain/models/match.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum MatchType { singles, doubles }
enum MatchStatus { scheduled, active, completed }

class Match {
  final String id;
  final List<String> playerIds;
  final MatchType type;
  final String courtId;
  final MatchStatus status;
  final DateTime? startedAt;
  final DateTime? expectedEndAt;
  final DateTime? completedAt;
  final int durationMinutes;

  const Match({
    required this.id,
    required this.playerIds,
    required this.type,
    required this.courtId,
    required this.status,
    required this.durationMinutes,
    this.startedAt,
    this.expectedEndAt,
    this.completedAt,
  });

  factory Match.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Match(
      id: doc.id,
      playerIds: List<String>.from(d['playerIds'] as List),
      type: MatchType.values.byName(d['type'] as String? ?? 'singles'),
      courtId: d['courtId'] as String,
      status: MatchStatus.values.byName(d['status'] as String? ?? 'scheduled'),
      durationMinutes: d['durationMinutes'] as int? ?? 20,
      startedAt: (d['startedAt'] as Timestamp?)?.toDate(),
      expectedEndAt: (d['expectedEndAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'playerIds': playerIds,
        'type': type.name,
        'courtId': courtId,
        'status': status.name,
        'durationMinutes': durationMinutes,
        'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
        'expectedEndAt':
            expectedEndAt != null ? Timestamp.fromDate(expectedEndAt!) : null,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      };

  /// Returns remaining time, or Duration.zero if the match is in overtime.
  /// Returns null if the match has not started.
  Duration? get remainingTime {
    if (expectedEndAt == null) return null;
    final remaining = expectedEndAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isOvertime {
    if (expectedEndAt == null) return false;
    return DateTime.now().isAfter(expectedEndAt!);
  }
}
