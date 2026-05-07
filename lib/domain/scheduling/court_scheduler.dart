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

  ScheduleOutput onMatchEnded({
    required Court endedCourt,
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
        .where((c) =>
            c.mode != CourtMode.holding &&
            c.nextMatchId == null &&
            c.id != endedCourt.id)
        .toList()
      ..add(endedCourt);

    final newNextMatches = <ScheduledMatch>[];
    final usedPlayerIds = <String>{};

    courtsNeedingNext.sort((a, b) =>
        a.id == endedCourt.id ? -1 : (b.id == endedCourt.id ? 1 : 0));

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

    // Build activation targets — include player IDs from the queued next match
    // so the repository can update player statuses atomically.
    final activationTargets = <ActivationTarget>[];
    if (endedCourt.nextMatchId != null) {
      final nextMatch = activeMatches.firstWhere(
        (m) => m.id == endedCourt.nextMatchId,
        orElse: () => throw StateError(
            'nextMatch ${endedCourt.nextMatchId} not found in activeMatches'),
      );
      activationTargets.add(ActivationTarget(
        court: endedCourt,
        playerIds: nextMatch.playerIds,
      ));
    } else {
      activationTargets.add(ActivationTarget(
        court: endedCourt,
        playerIds: const [],
      ));
    }

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
