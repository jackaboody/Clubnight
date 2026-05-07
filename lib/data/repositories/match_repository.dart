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

    // Courts whose nextMatch is being promoted → will have a currentMatch after
    // this batch commits.
    final activatingCourtIds = output.courtsToActivateNextMatch
        .where((t) => t.court.nextMatchId != null)
        .map((t) => t.court.id)
        .toSet();

    // Courts whose match ended with no queued nextMatch → being freed.
    final freedCourtIds = output.courtsToActivateNextMatch
        .where((t) => t.court.nextMatchId == null)
        .map((t) => t.court.id)
        .toSet();

    // 1. Promote nextMatch → currentMatch (stays 'scheduled' until organiser
    //    presses Start, so the timer only runs once players are on court).
    for (final target in output.courtsToActivateNextMatch) {
      final court = target.court;
      final courtRef = _db.collection('courts').doc(court.id);
      if (court.nextMatchId != null) {
        batch.update(courtRef, {
          'currentMatchId': court.nextMatchId,
          'nextMatchId': null,
        });
        // Mark players as 'playing' so the scheduler won't re-assign them,
        // but leave the match as 'scheduled' — timer starts on Start button.
        for (final playerId in target.playerIds) {
          batch.update(_db.collection('players').doc(playerId), {
            'status': PlayerStatus.playing.name,
            'currentMatchId': court.nextMatchId,
          });
        }
      } else {
        // Match ended with nothing queued — clear the court.
        batch.update(courtRef, {'currentMatchId': null});
      }
    }

    // 2. Create new match documents. Matches placed in the currentMatch slot
    //    (court was free) are still 'scheduled' — Start button activates them.
    for (final scheduled in output.newNextMatches) {
      final matchRef = _db.collection('matches').doc();
      final courtRef = _db.collection('courts').doc(scheduled.court.id);

      final courtWillBeFree = scheduled.court.currentMatchId == null ||
          freedCourtIds.contains(scheduled.court.id);
      final goToCurrentSlot =
          courtWillBeFree && !activatingCourtIds.contains(scheduled.court.id);

      batch.set(matchRef, {
        'playerIds': scheduled.matchResult.players.map((p) => p.id).toList(),
        'type': scheduled.matchResult.type == MatchType.doubles
            ? 'doubles'
            : 'singles',
        'courtId': scheduled.court.id,
        'status': MatchStatus.scheduled.name,
        'startedAt': null,
        'expectedEndAt': null,
        'completedAt': null,
        'durationMinutes': matchDurationMinutes,
      });

      batch.update(
          courtRef,
          goToCurrentSlot
              ? {'currentMatchId': matchRef.id}
              : {'nextMatchId': matchRef.id});

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
        batch.update(_db.collection('players').doc(player.id), {
          'recentOpponents': history,
          if (goToCurrentSlot) 'status': PlayerStatus.playing.name,
          if (goToCurrentSlot) 'currentMatchId': matchRef.id,
        });
      }
    }

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Write: start a match (organiser taps Start when players are on court)
  // ---------------------------------------------------------------------------

  Future<void> startMatch({
    required String matchId,
    required int durationMinutes,
  }) {
    final now = DateTime.now();
    return _db.collection('matches').doc(matchId).update({
      'status': MatchStatus.active.name,
      'startedAt': Timestamp.fromDate(now),
      'expectedEndAt':
          Timestamp.fromDate(now.add(Duration(minutes: durationMinutes))),
    });
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
  // Write: safely remove a player and cancel any matches they are in
  // ---------------------------------------------------------------------------

  Future<void> removePlayer(String playerId) async {
    final matchSnap = await _db
        .collection('matches')
        .where('playerIds', arrayContains: playerId)
        .where('status', whereIn: ['active', 'scheduled'])
        .get();

    final batch = _db.batch();
    final now = DateTime.now();

    for (final doc in matchSnap.docs) {
      final match = Match.fromFirestore(doc);

      batch.update(doc.reference, {
        'status': MatchStatus.completed.name,
        'completedAt': Timestamp.fromDate(now),
      });

      // Clear currentMatchId on any court pointing at this match.
      final currentCourtSnap = await _db
          .collection('courts')
          .where('currentMatchId', isEqualTo: match.id)
          .get();
      for (final c in currentCourtSnap.docs) {
        batch.update(c.reference, {'currentMatchId': null});
      }

      // Clear nextMatchId on any court pointing at this match.
      final nextCourtSnap = await _db
          .collection('courts')
          .where('nextMatchId', isEqualTo: match.id)
          .get();
      for (final c in nextCourtSnap.docs) {
        batch.update(c.reference, {'nextMatchId': null});
      }

      // Return other players in the match to waiting.
      for (final pid in match.playerIds) {
        if (pid != playerId) {
          batch.update(_db.collection('players').doc(pid), {
            'status': PlayerStatus.waiting.name,
            'currentMatchId': null,
          });
        }
      }
    }

    batch.delete(_db.collection('players').doc(playerId));
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
