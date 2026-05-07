// lib/presentation/controllers/scheduling_controller.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/scheduling/court_scheduler.dart';
import 'package:squash_social/presentation/providers/providers.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class SchedulingState {
  final String? lastError;
  const SchedulingState({this.lastError});
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class SchedulingController extends AsyncNotifier<SchedulingState> {
  final Map<String, List<String>> _recentPairings = {};
  Set<String> _previousActiveMatchIds = {};
  Set<String> _previousWaitingIds = {};

  // Serial task queue — all scheduling work is chained so nothing is dropped
  // when two triggers fire simultaneously (e.g. match-end + players-returning).
  Future<void> _tail = Future.value();

  void _enqueue(Future<void> Function() work) {
    _tail = _tail.then((_) => work()).catchError((Object e, StackTrace st) {
      state = AsyncValue.error(e, st);
    });
  }

  @override
  Future<SchedulingState> build() async {
    final players = await ref.read(playersStreamProvider.future);
    for (final player in players) {
      _recentPairings[player.id] = player.recentOpponents;
    }
    _previousActiveMatchIds = players
        .where((p) => p.status == PlayerStatus.playing)
        .map((p) => p.id)
        .toSet();
    _previousWaitingIds =
        players.where((p) => p.status == PlayerStatus.waiting).map((p) => p.id).toSet();

    ref.listen<AsyncValue<List<Match>>>(
      activeMatchesStreamProvider,
      (_, next) {
        next.whenOrNull(data: _onMatchesChanged);
      },
    );

    ref.listen<AsyncValue<List<Player>>>(
      playersStreamProvider,
      (_, next) {
        next.whenOrNull(data: _onPlayersChanged);
      },
    );

    return const SchedulingState();
  }

  // ---------------------------------------------------------------------------
  // Stream callbacks — enqueue work, never block each other
  // ---------------------------------------------------------------------------

  void _onMatchesChanged(List<Match> matches) {
    final nowActiveIds = matches
        .where((m) => m.status == MatchStatus.active)
        .map((m) => m.id)
        .toSet();

    final endedIds = _previousActiveMatchIds.difference(nowActiveIds);
    _previousActiveMatchIds = nowActiveIds;

    if (endedIds.isNotEmpty) {
      _enqueue(() => _handleMatchesEnded(endedIds, matches));
    }
  }

  void _onPlayersChanged(List<Player> players) {
    final nowWaitingIds =
        players.where((p) => p.status == PlayerStatus.waiting).map((p) => p.id).toSet();
    final newArrivals = nowWaitingIds.difference(_previousWaitingIds);
    _previousWaitingIds = nowWaitingIds;

    // Only trigger scheduling for genuinely new players, not for players
    // returning to waiting after a match ends (those are handled by
    // _handleMatchesEnded which is already queued ahead of this).
    if (newArrivals.isNotEmpty) {
      _enqueue(() => _tryFillEmptyCourts());
    }
  }

  // ---------------------------------------------------------------------------
  // Work
  // ---------------------------------------------------------------------------

  Future<void> _handleMatchesEnded(
    Set<String> endedMatchIds,
    List<Match> currentMatches,
  ) async {
    final courts = await ref.read(courtsStreamProvider.future);
    final players = await ref.read(playersStreamProvider.future);
    final config = await ref.read(configProvider.future);
    final scheduler = ref.read(courtSchedulerProvider);
    final repo = ref.read(matchRepositoryProvider);

    for (final endedId in endedMatchIds) {
      final Court? court;
      try {
        court = courts.firstWhere((c) => c.currentMatchId == endedId);
      } catch (_) {
        continue;
      }

      final output = scheduler.onMatchEnded(
        endedCourt: court,
        allCourts: courts,
        allPlayers: players,
        activeMatches: currentMatches,
        config: config,
        recentPairings: _recentPairings,
      );

      await repo.applyScheduleOutput(
        output: output,
        matchDurationMinutes: config.matchDurationMinutes,
        recentPairings: _recentPairings,
      );

      _updatePairingsCache(output.newNextMatches);
    }

    state = const AsyncValue.data(SchedulingState());
  }

  Future<void> _tryFillEmptyCourts() async {
    final courts = await ref.read(courtsStreamProvider.future);
    final players = await ref.read(playersStreamProvider.future);
    final matches = await ref.read(activeMatchesStreamProvider.future);
    final config = await ref.read(configProvider.future);
    final scheduler = ref.read(courtSchedulerProvider);
    final repo = ref.read(matchRepositoryProvider);

    final output = scheduler.onPlayerAdded(
      allCourts: courts,
      allPlayers: players,
      activeMatches: matches,
      config: config,
      recentPairings: _recentPairings,
    );

    if (output.newNextMatches.isNotEmpty) {
      await repo.applyScheduleOutput(
        output: output,
        matchDurationMinutes: config.matchDurationMinutes,
        recentPairings: _recentPairings,
      );
      _updatePairingsCache(output.newNextMatches);
    }

    state = const AsyncValue.data(SchedulingState());
  }

  void _updatePairingsCache(List<ScheduledMatch> newNextMatches) {
    for (final scheduled in newNextMatches) {
      for (final player in scheduled.matchResult.players) {
        final others = scheduled.matchResult.players
            .where((p) => p.id != player.id)
            .map((p) => p.id)
            .toList();
        final history = List<String>.from(_recentPairings[player.id] ?? []);
        history.insertAll(0, others);
        if (history.length > 12) history.removeRange(12, history.length);
        _recentPairings[player.id] = history;
      }
    }
  }

  /// Public entry point kept for external callers (e.g. after bulk changes).
  void onPlayerJoined() => _enqueue(() => _tryFillEmptyCourts());
}

final schedulingControllerProvider =
    AsyncNotifierProvider<SchedulingController, SchedulingState>(
  SchedulingController.new,
);
