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

  // Track the previous state of each status bucket so we can detect
  // the right kind of change in each stream callback.
  Set<String> _previousActiveMatchIds = {};
  Set<String> _previousWaitingIds = {};
  Set<String> _previousPlayingIds = {};

  // Serial task queue — all scheduling work runs in order so nothing is
  // dropped when multiple triggers fire from the same Firestore batch.
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
    _previousWaitingIds =
        players.where((p) => p.status == PlayerStatus.waiting).map((p) => p.id).toSet();
    _previousPlayingIds =
        players.where((p) => p.status == PlayerStatus.playing).map((p) => p.id).toSet();
    _previousActiveMatchIds = {};

    ref.listen<AsyncValue<List<Match>>>(
      activeMatchesStreamProvider,
      (_, next) => next.whenOrNull(data: _onMatchesChanged),
    );

    ref.listen<AsyncValue<List<Player>>>(
      playersStreamProvider,
      (_, next) => next.whenOrNull(data: _onPlayersChanged),
    );

    return const SchedulingState();
  }

  // ---------------------------------------------------------------------------
  // Stream callbacks
  // ---------------------------------------------------------------------------

  void _onMatchesChanged(List<Match> matches) {
    final nowActiveIds = matches
        .where((m) => m.status == MatchStatus.active)
        .map((m) => m.id)
        .toSet();

    final endedIds = _previousActiveMatchIds.difference(nowActiveIds);
    _previousActiveMatchIds = nowActiveIds;

    if (endedIds.isNotEmpty) {
      // Pass endedIds only — _handleMatchesEnded reads fresh data when it runs
      // so it always sees the current court/match state, not a stale snapshot.
      _enqueue(() => _handleMatchesEnded(endedIds));
    }
  }

  void _onPlayersChanged(List<Player> players) {
    final nowWaitingIds =
        players.where((p) => p.status == PlayerStatus.waiting).map((p) => p.id).toSet();
    final nowPlayingIds =
        players.where((p) => p.status == PlayerStatus.playing).map((p) => p.id).toSet();

    // Genuinely new arrivals: newly waiting AND not previously playing.
    // Players returning from a match (playing → waiting) are excluded here;
    // they are handled by _handleMatchesEnded which respects wait times and
    // fairness. If we also triggered fill here they'd be re-scheduled immediately.
    final newArrivals = nowWaitingIds
        .difference(_previousWaitingIds)
        .difference(_previousPlayingIds);

    _previousWaitingIds = nowWaitingIds;
    _previousPlayingIds = nowPlayingIds;

    if (newArrivals.isNotEmpty) {
      _enqueue(() => _tryFillEmptyCourts());
    }
  }

  // ---------------------------------------------------------------------------
  // Work
  // ---------------------------------------------------------------------------

  Future<void> _handleMatchesEnded(Set<String> endedMatchIds) async {
    // Always read fresh data — stale snapshots from the stream callback would
    // miss any nextMatches created by items earlier in the queue.
    final courts = await ref.read(courtsStreamProvider.future);
    final players = await ref.read(playersStreamProvider.future);
    final matches = await ref.read(activeMatchesStreamProvider.future);
    final config = await ref.read(configProvider.future);
    final scheduler = ref.read(courtSchedulerProvider);
    final repo = ref.read(matchRepositoryProvider);

    for (final endedId in endedMatchIds) {
      final Court? court;
      try {
        court = courts.firstWhere((c) => c.currentMatchId == endedId);
      } catch (_) {
        continue; // Court already advanced by a concurrent trigger.
      }

      final output = scheduler.onMatchEnded(
        endedCourt: court,
        allCourts: courts,
        allPlayers: players,
        activeMatches: matches,
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

  void onPlayerJoined() => _enqueue(() => _tryFillEmptyCourts());
}

final schedulingControllerProvider =
    AsyncNotifierProvider<SchedulingController, SchedulingState>(
  SchedulingController.new,
);
