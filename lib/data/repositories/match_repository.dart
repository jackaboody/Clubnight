// lib/data/repositories/match_repository.dart
//
// Executes all Firestore writes related to match lifecycle.
// Uses batched writes to keep round-trips minimal and changes atomic.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/scheduling/court_scheduler.dart';

class MatchRepository {
  final FirebaseFirestore _db;

  MatchRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  Stream<List<Match>> watchActiveAndScheduledMatches() {
    return _db
        .collection('matches')
        .where('status', whereIn: ['active', 'scheduled'])
        .snapshots()
        .map((snap) => snap.docs.map(Match.fromFirestore).toList());
  }

  Stream<Match?> watchMatch(String matchId) {
    return _db
        .collection('matches')
        .doc(matchId)
        .snapshots()
        .map((doc) => doc.exists ? Match.fromFirestore(doc) : null);
  }

  // ---------------------------------------------------------------------------
  // Write: apply a ScheduleOutput from CourtScheduler
  // ---------------------------------------------------------------------------

  /// Applies one batch of scheduling decisions atomically.
  /// Creates new match documents, updates courts, and updates player statuses.
  Future<void> applyScheduleOutput({
    required ScheduleOutput output,
    required int matchDurationMinutes,
    required Map<String, List<String>> recentPairings,
  }) async {
    final batch = _db.batch();
    final now = DateTime.now();

    // Courts whose nextMatch is being promoted → will have a currentMatch after
    // this batch commits.
    final activatingCourtIds = output.courtsToActivateNextMatch
        .where((c) => c.nextMatchId != null)
        .map((c) => c.id)
        .toSet();

    // Courts whose match ended with no queued nextMatch → being freed.
    final freedCourtIds = output.courtsToActivateNextMatch
        .where((c) => c.nextMatchId == null)
        .map((c) => c.id)
        .toSet();

    // 1. Activate pending next matches on courts that just freed up.
    for (final court in output.courtsToActivateNextMatch) {
      final courtRef = _db.collection('courts').doc(court.id);
      if (court.nextMatchId != null) {
        // Promote nextMatch → currentMatch.
        batch.update(courtRef, {
          'currentMatchId': court.nextMatchId,
          'nextMatchId': null,
        });
        batch.update(_db.collection('matches').doc(court.nextMatchId), {
          'status': MatchStatus.active.name,
          'startedAt': Timestamp.fromDate(now),
          'expectedEndAt': Timestamp.fromDate(
            now.add(Duration(minutes: matchDurationMinutes)),
          ),
        });
      } else {
        // Match ended with nothing queued — clear the court so it shows free.
        batch.update(courtRef, {'currentMatchId': null});
      }
    }

    // 2. Create new match documents and assign to courts.
    for (final scheduled in output.newNextMatches) {
      final matchRef = _db.collection('matches').doc();
      final courtRef = _db.collection('courts').doc(scheduled.court.id);

      // Start immediately if the court has no current match, accounting for
      // courts being freed or activated within this same batch.
      final courtWillBeFree = scheduled.court.currentMatchId == null ||
          freedCourtIds.contains(scheduled.court.id);
      final startNow =
          courtWillBeFree && !activatingCourtIds.contains(scheduled.court.id);

      batch.set(matchRef, {
        'playerIds': scheduled.matchResult.players.map((p) => p.id).toList(),
        'type': scheduled.matchResult.type == MatchType.doubles
            ? 'doubles'
            : 'singles',
        'courtId': scheduled.court.id,
        'status':
            startNow ? MatchStatus.active.name : MatchStatus.scheduled.name,
        'startedAt': startNow ? Timestamp.fromDate(now) : null,
        'expectedEndAt': startNow
            ? Timestamp.fromDate(
                now.add(Duration(minutes: matchDurationMinutes)))
            : null,
        'completedAt': null,
        'durationMinutes': matchDurationMinutes,
      });

      batch.update(courtRef,
          startNow ? {'currentMatchId': matchRef.id} : {'nextMatchId': matchRef.id});

      // Update recent pairings for each player in the group.
      for (final player in scheduled.matchResult.players) {
        final others = scheduled.matchResult.players
            .where((p) => p.id != player.id)
            .map((p) => p.id)
            .toList();
        final history = List<String>.from(recentPairings[player.id] ?? []);
        history.insertAll(0, others);
        const keepEntries = 12;
        if (history.length > keepEntries) {
          history.removeRange(keepEntries, history.length);
        }
        final playerRef = _db.collection('players').doc(player.id);
        batch.update(playerRef, {'recentOpponents': history});
      }
    }

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Write: end a match (End Now or natural completion)
  // ---------------------------------------------------------------------------

  Future<void> endMatch({
    required String matchId,
    required List<String> playerIds,
  }) async {
    final batch = _db.batch();
    final now = DateTime.now();

    // Mark match as completed.
    batch.update(_db.collection('matches').doc(matchId), {
      'status': MatchStatus.completed.name,
      'completedAt': Timestamp.fromDate(now),
    });

    // Return players to waiting and increment matchesPlayed.
    for (final playerId in playerIds) {
      batch.update(_db.collection('players').doc(playerId), {
        'status': PlayerStatus.waiting.name,
        'lastPlayedAt': Timestamp.fromDate(now),
        'currentMatchId': null,
        'matchesPlayed': FieldValue.increment(1),
      });
    }

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Write: reset the entire evening
  // ---------------------------------------------------------------------------

  Future<void> resetEvening() async {
    final batch = _db.batch();

    // Delete all matches.
    final matchDocs = await _db.collection('matches').get();
    for (final doc in matchDocs.docs) {
      batch.delete(doc.reference);
    }

    // Clear courts.
    final courts = await _db.collection('courts').get();
    for (final doc in courts.docs) {
      batch.update(doc.reference, {
        'currentMatchId': null,
        'nextMatchId': null,
      });
    }

    // Delete all players.
    final players = await _db.collection('players').get();
    for (final doc in players.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
