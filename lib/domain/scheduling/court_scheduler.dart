// lib/domain/scheduling/court_scheduler.dart

import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/models/app_config.dart';
import 'package:squash_social/domain/matchmaking/matchmaking_engine.dart';

// ---------------------------------------------------------------------------
// Schedule result
// ---------------------------------------------------------------------------

class ScheduledMatch {
  final Court court;
  final MatchmakingResult matchResult;

  const ScheduledMatch({required this.court, required this.matchResult});
}

/// A court whose queued nextMatch should be promoted to currentMatch.
/// Carries the player IDs so the repository can flip their status to
/// 'playing' in the same atomic batch, without needing an extra read.
class ActivationTarget {
  final Court court;
  final List<String> playerIds;

  const ActivationTarget({required this.court, required this.playerIds});
}

class ScheduleOutput {
  final List<ScheduledMatch> newNextMatches;
  final List<ActivationTarget> courtsToActivateNextMatch;

  const ScheduleOutput({
    required this.newNextMatches,
    required this.courtsToActivateNextMatch,
  });
}

// ---------------------------------------------------------------------------
// Scheduler
// ---------------------------------------------------------------------------

class CourtScheduler {
  final MatchmakingEngine engine;

  const CourtScheduler({required this.engine});

  /// Handles one or more matches ending in the same Firestore snapshot.
  /// All ended courts are processed in a single consistent pass so no court
  /// can be double-scheduled or have its nextMatch overwritten by a later
  /// iteration reading stale data.
  ScheduleOutput onMatchesEnded({
    required List<Court> endedCourts,
    required List<Court> allCourts,
    required List<Player> allPlayers,
    required List<Match> activeMatches,
    required AppConfig config,
    required Map<String, List<String>> recentPairings,
  }) {
    final committedPlayerIds = _committedPlayerIds(allCourts, activeMatches);
    final endedCourtIds = endedCourts.map((c) => c.id).toSet();

    final waitingPlayers = allPlayers
        .where((p) =>
            p.status == PlayerStatus.waiting &&
            !committedPlayerIds.contains(p.id))
        .toList();

    final activeDoubleCourts = activeMatches
        .where((m) =>
            m.status == MatchStatus.active && m.type == MatchType.doubles)
        .length;

    // Ended courts first (priority — their players just freed up), then any
    // other courts that still have an empty next-match slot.
    final courtsNeedingNext = [
      ...endedCourts,
      ...allCourts.where((c) =>
          c.mode != CourtMode.holding &&
          c.nextMatchId == null &&
          !endedCourtIds.contains(c.id)),
    ];

    final newNextMatches = <ScheduledMatch>[];
    final usedPlayerIds = <String>{};

    for (final court in courtsNeedingNext) {
      final availablePlayers = waitingPlayers
          .where((p) => !usedPlayerIds.contains(p.id))
          .toList();

      final result = engine.findBestMatch(
        waitingPlayers: availablePlayers,
        config: config,
        activeDoubleCourts: activeDoubleCourts +
            newNextMatches
                .where((m) => m.matchResult.type == MatchType.doubles)
                .length,
        recentPairings: recentPairings,
      );

      if (result != null) {
        newNextMatches.add(ScheduledMatch(court: court, matchResult: result));
        usedPlayerIds.addAll(result.players.map((p) => p.id));
      }
    }

    // Build one activation target per ended court.
    final activationTargets = endedCourts.map((endedCourt) {
      if (endedCourt.nextMatchId != null) {
        try {
          final nextMatch =
              activeMatches.firstWhere((m) => m.id == endedCourt.nextMatchId);
          return ActivationTarget(
              court: endedCourt, playerIds: nextMatch.playerIds);
        } catch (_) {
          // nextMatch document missing — treat as no queued match.
        }
      }
      return ActivationTarget(court: endedCourt, playerIds: const []);
    }).toList();

    return ScheduleOutput(
      newNextMatches: newNextMatches,
      courtsToActivateNextMatch: activationTargets,
    );
  }

  ScheduleOutput onPlayerAdded({
    required List<Court> allCourts,
    required List<Player> allPlayers,
    required List<Match> activeMatches,
    required AppConfig config,
    required Map<String, List<String>> recentPairings,
  }) {
    final committedPlayerIds = _committedPlayerIds(allCourts, activeMatches);

    final waitingPlayers = allPlayers
        .where((p) =>
            p.status == PlayerStatus.waiting &&
            !committedPlayerIds.contains(p.id))
        .toList();

    final activeDoubleCourts = activeMatches
        .where((m) =>
            m.status == MatchStatus.active && m.type == MatchType.doubles)
        .length;

    final courtsNeedingNext = allCourts
        .where((c) => c.mode != CourtMode.holding && c.nextMatchId == null)
        .toList();

    final newNextMatches = <ScheduledMatch>[];
    final usedPlayerIds = <String>{};

    for (final court in courtsNeedingNext) {
      final availablePlayers = waitingPlayers
          .where((p) => !usedPlayerIds.contains(p.id))
          .toList();

      final result = engine.findBestMatch(
        waitingPlayers: availablePlayers,
        config: config,
        activeDoubleCourts: activeDoubleCourts +
            newNextMatches
                .where((m) => m.matchResult.type == MatchType.doubles)
                .length,
        recentPairings: recentPairings,
      );

      if (result != null) {
        newNextMatches.add(ScheduledMatch(court: court, matchResult: result));
        usedPlayerIds.addAll(result.players.map((p) => p.id));
      }
    }

    return ScheduleOutput(
      newNextMatches: newNextMatches,
      courtsToActivateNextMatch: const [],
    );
  }

  // ---------------------------------------------------------------------------

  /// Players who must not be re-allocated in this scheduling round:
  /// - Players already in an active match (playing right now).
  /// - Players locked into a scheduled nextMatch on a court.
  Set<String> _committedPlayerIds(
    List<Court> allCourts,
    List<Match> allMatches,
  ) {
    // Active match players.
    final activePlayers = allMatches
        .where((m) => m.status == MatchStatus.active)
        .expand((m) => m.playerIds)
        .toSet();

    // Scheduled nextMatch players.
    final nextMatchIds = allCourts
        .where((c) => c.nextMatchId != null)
        .map((c) => c.nextMatchId!)
        .toSet();
    final scheduledPlayers = allMatches
        .where((m) =>
            nextMatchIds.contains(m.id) && m.status == MatchStatus.scheduled)
        .expand((m) => m.playerIds)
        .toSet();

    return {...activePlayers, ...scheduledPlayers};
  }
}
