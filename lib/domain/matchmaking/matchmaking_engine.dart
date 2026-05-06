// lib/domain/matchmaking/matchmaking_engine.dart
//
// Pure Dart — zero Firebase imports. Fully unit-testable.
//
// Scoring model (lower = better):
//   totalCost = waitCost + fairnessCost + skillCost + pairingPenalty
//
//   waitCost     — penalises groups containing players who have waited longest
//   fairnessCost — penalises groups that skip players with fewer matches played
//                  (can be toggled off via AppConfig.fairnessModeEnabled)
//   skillCost    — penalises large skill-level spreads within a group
//   pairingPenalty — discourages re-pairing players who recently played together

import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/models/app_config.dart';
import 'package:squash_social/domain/models/match.dart' show MatchType;

// Re-export MatchType so callers that only import this file still have access.
export 'package:squash_social/domain/models/match.dart' show MatchType;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class MatchmakingResult {
  final List<Player> players;
  final MatchType type;
  final double totalCost;

  const MatchmakingResult({
    required this.players,
    required this.type,
    required this.totalCost,
  });
}

// Intermediate scoring carrier used during candidate evaluation.
class _ScoredGroup {
  final List<Player> players;
  final MatchType type;
  final double cost;

  const _ScoredGroup(this.players, this.type, this.cost);
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class MatchmakingEngine {
  // Weights control the relative importance of each axis.
  // Exposed so they can be adjusted from AppConfig without changing logic.
  final double waitWeight;
  final double fairnessWeight;
  final double skillWeight;

  // Maximum skill difference tolerated before the skill penalty becomes steep.
  final double skillTolerance;

  // Avoid re-pairing: penalise groups where players have recently played
  // together. The penalty decays after this many matches.
  final int recentPairingDecayMatches;

  const MatchmakingEngine({
    this.waitWeight = 2.0,
    this.fairnessWeight = 1.5,
    this.skillWeight = 1.0,
    this.skillTolerance = 1.0,
    this.recentPairingDecayMatches = 3,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the best match group from [waitingPlayers] for a single court
  /// slot. Returns null if there are not enough players to form any match.
  ///
  /// [activeDoubleCourts] — number of doubles matches already running.
  /// [maxDoubleCourts]    — hard ceiling on simultaneous doubles courts.
  /// [recentPairings]     — map of playerId → list of playerIds they have
  ///                        recently played with (caller maintains this).
  MatchmakingResult? findBestMatch({
    required List<Player> waitingPlayers,
    required AppConfig config,
    required int activeDoubleCourts,
    required Map<String, List<String>> recentPairings,
  }) {
    final eligible = waitingPlayers
        .where((p) => p.status == PlayerStatus.waiting)
        .toList();

    if (eligible.length < 2) return null;

    final now = DateTime.now();
    final candidates = <_ScoredGroup>[];

    // --- Singles candidates (all pairs) ---
    final singles = _singlesGroups(eligible);
    for (final group in singles) {
      final cost = _score(
        group: group,
        type: MatchType.singles,
        now: now,
        config: config,
        recentPairings: recentPairings,
      );
      candidates.add(_ScoredGroup(group, MatchType.singles, cost));
    }

    // --- Doubles candidates (if capacity allows) ---
    final doublesAllowed =
        activeDoubleCourts < config.maxDoubleCourts && eligible.length >= 4;

    if (doublesAllowed) {
      final doublesEligible =
          eligible.where((p) => p.prefersDoubles).toList();
      if (doublesEligible.length >= 4) {
        final doubles = _doublesGroups(doublesEligible);
        for (final group in doubles) {
          final cost = _score(
            group: group,
            type: MatchType.doubles,
            now: now,
            config: config,
            recentPairings: recentPairings,
            // Subtract a bonus so doubles is preferred when players want it.
            costAdjustment: -1.0,
          );
          candidates.add(_ScoredGroup(group, MatchType.doubles, cost));
        }
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.cost.compareTo(b.cost));
    final best = candidates.first;

    return MatchmakingResult(
      players: best.players,
      type: best.type,
      totalCost: best.cost,
    );
  }

  // ---------------------------------------------------------------------------
  // Scoring
  // ---------------------------------------------------------------------------

  double _score({
    required List<Player> group,
    required MatchType type,
    required DateTime now,
    required AppConfig config,
    required Map<String, List<String>> recentPairings,
    double costAdjustment = 0.0,
  }) {
    final waitCost = _waitCost(group, now);
    final fairnessCost = config.fairnessModeEnabled
        ? _fairnessCost(group)
        : 0.0;
    final skillCost = _skillCost(group);
    final pairingPenalty = _pairingPenalty(group, recentPairings);

    return waitCost * waitWeight +
        fairnessCost * fairnessWeight +
        skillCost * skillWeight +
        pairingPenalty +
        costAdjustment;
  }

  /// Wait cost: weighted sum of each player's wait duration in minutes.
  /// Players who have waited longer pull the group cost DOWN (we want to
  /// pick groups that include long-waiters), so we negate — longer wait
  /// → lower cost → higher priority.
  double _waitCost(List<Player> group, DateTime now) {
    double totalWaitMinutes = 0;
    for (final p in group) {
      final waitedSince = p.lastPlayedAt ?? p.createdAt;
      totalWaitMinutes +=
          now.difference(waitedSince).inSeconds / 60.0;
    }
    // Negate so long-waiting groups get a lower (better) score.
    // Divide by group size to normalise; add 1 to avoid divide-by-zero.
    return -(totalWaitMinutes / group.length).clamp(0.0, 9999.0);
  }

  /// Fairness cost: penalise groups that leave behind players with fewer
  /// matches played than those in the candidate group.
  double _fairnessCost(List<Player> group) {
    if (group.isEmpty) return 0;
    final groupAvg =
        group.map((p) => p.matchesPlayed).reduce((a, b) => a + b) /
            group.length;
    // The penalty is the group's average matches played — lower is better,
    // meaning we prefer to schedule players who've played fewer times.
    return groupAvg;
  }

  /// Skill cost: penalise high skill spread within a group.
  double _skillCost(List<Player> group) {
    if (group.length < 2) return 0;
    final levels = group.map((p) => p.level).toList();
    final minLevel = levels.reduce((a, b) => a < b ? a : b);
    final maxLevel = levels.reduce((a, b) => a > b ? a : b);
    final spread = maxLevel - minLevel;
    // Below tolerance: gentle linear cost.
    // Above tolerance: quadratic penalty to strongly discourage mismatches.
    if (spread <= skillTolerance) {
      return spread;
    } else {
      return skillTolerance + (spread - skillTolerance) * (spread - skillTolerance) * 2;
    }
  }

  /// Recent pairing penalty: add a flat cost for each pair in the group
  /// that has played together recently. Penalty decays with recency index.
  double _pairingPenalty(
    List<Player> group,
    Map<String, List<String>> recentPairings,
  ) {
    double penalty = 0;
    for (int i = 0; i < group.length; i++) {
      for (int j = i + 1; j < group.length; j++) {
        final aId = group[i].id;
        final bId = group[j].id;
        final aHistory = recentPairings[aId] ?? [];
        final idx = aHistory.indexOf(bId);
        if (idx != -1) {
          // Most recent pairing → highest penalty, decays linearly.
          final recency = recentPairingDecayMatches - idx;
          if (recency > 0) {
            penalty += recency * 0.5;
          }
        }
      }
    }
    return penalty;
  }

  // ---------------------------------------------------------------------------
  // Group generation (combinatorial)
  // ---------------------------------------------------------------------------

  /// All ordered pairs from [players] — O(n²). Fine for n ≤ 30.
  List<List<Player>> _singlesGroups(List<Player> players) {
    final groups = <List<Player>>[];
    for (int i = 0; i < players.length; i++) {
      for (int j = i + 1; j < players.length; j++) {
        groups.add([players[i], players[j]]);
      }
    }
    return groups;
  }

  /// All combinations of 4 from [players] — O(n⁴/24). Fine for n ≤ 30.
  /// We only call this on the doubles-eligible subset, typically ≤ 15 players.
  List<List<Player>> _doublesGroups(List<Player> players) {
    final groups = <List<Player>>[];
    final n = players.length;
    for (int i = 0; i < n - 3; i++) {
      for (int j = i + 1; j < n - 2; j++) {
        for (int k = j + 1; k < n - 1; k++) {
          for (int l = k + 1; l < n; l++) {
            groups.add([players[i], players[j], players[k], players[l]]);
          }
        }
      }
    }
    return groups;
  }
}
