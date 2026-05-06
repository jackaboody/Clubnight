// lib/presentation/providers/providers.dart
//
// Riverpod providers that wrap Firestore streams and expose computed state
// to the UI. All business logic is in the domain layer — providers are thin.

import 'dart:math' show sqrt;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/app_config.dart';
import 'package:squash_social/domain/matchmaking/matchmaking_engine.dart';
import 'package:squash_social/domain/scheduling/court_scheduler.dart';
import 'package:squash_social/data/repositories/match_repository.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => MatchRepository(db: ref.watch(firestoreProvider)),
);

final matchmakingEngineProvider = Provider<MatchmakingEngine>(
  (_) => const MatchmakingEngine(),
);

final courtSchedulerProvider = Provider<CourtScheduler>(
  (ref) => CourtScheduler(engine: ref.watch(matchmakingEngineProvider)),
);

// ---------------------------------------------------------------------------
// Real-time data streams
// ---------------------------------------------------------------------------

final playersStreamProvider = StreamProvider<List<Player>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('players')
      .snapshots()
      .map((snap) => snap.docs.map(Player.fromFirestore).toList());
});

final courtsStreamProvider = StreamProvider<List<Court>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('courts')
      .orderBy('number')
      .snapshots()
      .map((snap) => snap.docs.map(Court.fromFirestore).toList());
});

final activeMatchesStreamProvider = StreamProvider<List<Match>>((ref) {
  final repo = ref.watch(matchRepositoryProvider);
  return repo.watchActiveAndScheduledMatches();
});

final configProvider = StreamProvider<AppConfig>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('config')
      .doc('settings')
      .snapshots()
      .map((doc) => AppConfig.fromFirestore(doc));
});

// ---------------------------------------------------------------------------
// Derived / computed providers
// ---------------------------------------------------------------------------

/// Organiser stats — computed from real-time streams, no extra Firestore reads.
final statsProvider = Provider<AsyncValue<OrganizerStats>>((ref) {
  final players = ref.watch(playersStreamProvider);
  final matches = ref.watch(activeMatchesStreamProvider);

  return players.when(
    data: (playerList) => matches.when(
      data: (matchList) {
        final waiting =
            playerList.where((p) => p.status == PlayerStatus.waiting).length;
        final playing =
            playerList.where((p) => p.status == PlayerStatus.playing).length;
        final unavailable = playerList
            .where((p) => p.status == PlayerStatus.unavailable)
            .length;
        final singlesCount = matchList
            .where((m) =>
                m.type == MatchType.singles &&
                m.status == MatchStatus.active)
            .length;
        final doublesCount = matchList
            .where((m) =>
                m.type == MatchType.doubles &&
                m.status == MatchStatus.active)
            .length;

        // Fairness metric: standard deviation of matchesPlayed across all players.
        final played = playerList.map((p) => p.matchesPlayed).toList();
        final fairnessScore = played.isEmpty ? 0.0 : _stdDev(played);

        return AsyncValue.data(OrganizerStats(
          totalPlayers: playerList.length,
          waiting: waiting,
          playing: playing,
          unavailable: unavailable,
          activeSingles: singlesCount,
          activeDoubles: doublesCount,
          fairnessScore: fairnessScore,
        ));
      },
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
    ),
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// Match lookup by ID — used by court cards to resolve currentMatch/nextMatch.
final matchByIdProvider =
    StreamProvider.family<Match?, String>((ref, matchId) {
  final repo = ref.watch(matchRepositoryProvider);
  return repo.watchMatch(matchId);
});

/// A specific player's enriched view — used by the mobile player screen.
final playerMatchViewProvider =
    Provider.family<AsyncValue<PlayerMatchView>, String>((ref, playerId) {
  final players = ref.watch(playersStreamProvider);
  final matches = ref.watch(activeMatchesStreamProvider);
  final courts = ref.watch(courtsStreamProvider);

  return players.when(
    data: (playerList) {
      final player = playerList.firstWhere(
        (p) => p.id == playerId,
        orElse: () => throw Exception('Player not found'),
      );
      return matches.when(
        data: (matchList) => courts.when(
          data: (courtList) {
            Match? currentMatch;
            Match? nextMatch;
            Court? currentCourt;

            if (player.currentMatchId != null) {
              try {
                currentMatch = matchList.firstWhere(
                  (m) => m.id == player.currentMatchId,
                );
                currentCourt = courtList.firstWhere(
                  (c) => c.currentMatchId == player.currentMatchId,
                );
              } catch (_) {}
            }

            // Find if they're in any scheduled next match.
            try {
              nextMatch = matchList.firstWhere(
                (m) =>
                    m.status == MatchStatus.scheduled &&
                    m.playerIds.contains(playerId),
              );
            } catch (_) {}

            return AsyncValue.data(PlayerMatchView(
              player: player,
              currentMatch: currentMatch,
              nextMatch: nextMatch,
              currentCourt: currentCourt,
            ));
          },
          loading: () => const AsyncValue.loading(),
          error: (e, st) => AsyncValue.error(e, st),
        ),
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

// ---------------------------------------------------------------------------
// Data transfer objects
// ---------------------------------------------------------------------------

class OrganizerStats {
  final int totalPlayers;
  final int waiting;
  final int playing;
  final int unavailable;
  final int activeSingles;
  final int activeDoubles;
  final double fairnessScore; // lower = fairer (std dev of matchesPlayed)

  const OrganizerStats({
    required this.totalPlayers,
    required this.waiting,
    required this.playing,
    required this.unavailable,
    required this.activeSingles,
    required this.activeDoubles,
    required this.fairnessScore,
  });
}

class PlayerMatchView {
  final Player player;
  final Match? currentMatch;
  final Match? nextMatch;
  final Court? currentCourt;

  const PlayerMatchView({
    required this.player,
    this.currentMatch,
    this.nextMatch,
    this.currentCourt,
  });
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

double _stdDev(List<int> values) {
  if (values.isEmpty) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length;
  return variance > 0 ? sqrt(variance) : 0;
}
