// domain/scheduling/court_scheduler.dart
//
// Orchestrates matchmaking across all courts.
// Pure Dart — receives current state as value objects, returns actions to apply.
// The repository layer executes the Firestore writes.

import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/models/app_config.dart';
import 'package:squash_social/domain/matchmaking/matchmaking_engine.dart';

// ---------------------------------------------------------------------------
// Schedule result — a batch of write operations for the repository to execute
// ---------------------------------------------------------------------------

class ScheduledMatch {
  final Court court;
  final MatchmakingResult matchResult;

  const ScheduledMatch({required this.court, required this.matchResult});
}

class ScheduleOutput {
  /// Matches to be written to Firestore and assigned as `nextMatch` on courts.
  final List<ScheduledMatch> newNextMatches;

  /// Courts whose current match should be ended (status → completed).
  final List<Court> courtsToActivateNextMatch;

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

  // ---------------------------------------------------------------------------
  // Main entry points
  // ---------------------------------------------------------------------------

  /// Called when any court's match ends naturally or via "End Now".
  /// Returns the set of Firestore writes needed to:
  ///   1. Promote the nextMatch to currentMatch on the triggering court.
  ///   2. Generate a new nextMatch for that court.
  ///   3. Optionally generate nextMatches for other courts that lack them.
  ScheduleOutput onMatchEnded({
    required Court endedCourt,
    required List<Court> allCourts,
    required List<Player> allPlayers,
    required List<Match> activeMatches,
    required AppConfig config,
    required Map<String, List<String>> recentPairings,
  }) {
    // Players currently in scheduled-but-not-yet-started next matches are
    // committed and should not be re-allocated.
    final committedPlayerIds = _committedPlayerIds(allCourts, activeMatches);

    final waitingPlayers = allPlayers
        .where((p) =>
            p.status == PlayerStatus.waiting &&
            !committedPlayerIds.contains(p.id))
        .toList();

    final activeDoubleCourts = activeMatches
        .where((m) => m.status == MatchStatus.active && m.type == MatchType.doubles)
        .length;

    // Courts that need a nextMatch generated (including the just-freed court).
    final courtsNeedingNext = allCourts
        .where((c) =>
            c.mode != CourtMode.holding &&
            c.nextMatchId == null &&
            c.id != endedCourt.id)
        .toList()
      ..add(endedCourt);

    final newNextMatches = <ScheduledMatch>[];
    final usedPlayerIds = <String>{};

    // Sort courts: freed court first so it gets priority allocation.
    courtsNeedingNext.sort((a, b) =>
        a.id == endedCourt.id ? -1 : (b.id == endedCourt.id ? 1 : 0));

    for (final court in courtsNeedingNext) {
      final availablePlayers = waitingPlayers
          .where((p) => !usedPlayerIds.contains(p.id))
          .toList();

      final result = engine.findBestMatch(
        waitingPlayers: availablePlayers,
        config: config,
        activeDoubleCourts: activeDoubleCourts + newNextMatches.where((m) => m.matchResult.type == MatchType.doubles).length,
        recentPairings: recentPairings,
      );

      if (result != null) {
        newNextMatches.add(ScheduledMatch(court: court, matchResult: result));
        usedPlayerIds.addAll(result.players.map((p) => p.id));
      }
    }

    return ScheduleOutput(
      newNextMatches: newNextMatches,
      courtsToActivateNextMatch: [endedCourt],
    );
  }

  /// Called when a new player joins (status becomes 'waiting').
  /// Only generates nextMatches for courts that don't have one yet.
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
        .where((m) => m.status == MatchStatus.active && m.type == MatchType.doubles)
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
        activeDoubleCourts: activeDoubleCourts + newNextMatches.where((m) => m.matchResult.type == MatchType.doubles).length,
        recentPairings: recentPairings,
      );

      if (result != null) {
        newNextMatches.add(ScheduledMatch(court: court, matchResult: result));
        usedPlayerIds.addAll(result.players.map((p) => p.id));
      }
    }

    return ScheduleOutput(
      newNextMatches: newNextMatches,
      courtsToActivateNextMatch: [],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Players who are already locked into a scheduled nextMatch should not be
  /// re-allocated by the engine.
  Set<String> _committedPlayerIds(
    List<Court> allCourts,
    List<Match> allMatches,
  ) {
    final nextMatchIds = allCourts
        .where((c) => c.nextMatchId != null)
        .map((c) => c.nextMatchId!)
        .toSet();

    return allMatches
        .where((m) =>
            nextMatchIds.contains(m.id) && m.status == MatchStatus.scheduled)
        .expand((m) => m.playerIds)
        .toSet();
  }
}
