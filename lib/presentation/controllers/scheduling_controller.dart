// lib/presentation/controllers/scheduling_controller.dart
//
// Sits above the UI. Listens to real-time stream changes and decides when to
// invoke the CourtScheduler, then applies the result via MatchRepository.
// Implemented as a Riverpod AsyncNotifier so it can be kept alive for the
// entire session and react to stream events.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/presentation/providers/providers.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class SchedulingState {
  final bool isProcessing;
  final String? lastError;

  const SchedulingState({this.isProcessing = false, this.lastError});
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class SchedulingController extends AsyncNotifier<SchedulingState> {
  // Recent pairings cache — player ID → list of opponent IDs (most recent first).
  // Rebuilt from Firestore on startup; updated locally on each scheduled match.
  final Map<String, List<String>> _recentPairings = {};

  // Snapshot of previously seen active match IDs so we can detect transitions.
  Set<String> _previouslyActiveMatchIds = {};

  @override
  Future<SchedulingState> build() async {
    // Load recent pairings from player documents once on startup.
    final players = await ref.read(playersStreamProvider.future);
    for (final player in players) {
      _recentPairings[player.id] = player.recentOpponents;
    }

    // Listen for matches transitioning to 'completed' — that's our trigger.
    // ref.listen is automatically cancelled when the notifier is disposed.
    ref.listen<AsyncValue<List<Match>>>(
      activeMatchesStreamProvider,
      (_, next) {
        next.whenOrNull(
          data: _onMatchesChanged,
          error: (e, _) => state = AsyncValue.data(
            SchedulingState(lastError: e.toString()),
          ),
        );
      },
    );

    return const SchedulingState();
  }

  void _onMatchesChanged(List<Match> matches) {
    final nowActiveIds = matches
        .where((m) => m.status == MatchStatus.active)
        .map((m) => m.id)
        .toSet();

    // Detect any match that just left the active set — it ended.
    // (The repository marks it completed, so it drops off the stream.)
    final endedIds = _previouslyActiveMatchIds.difference(nowActiveIds);
    _previouslyActiveMatchIds = nowActiveIds;

    if (endedIds.isNotEmpty) {
      _handleMatchesEnded(endedIds, matches);
    }
  }

  Future<void> _handleMatchesEnded(
    Set<String> endedMatchIds,
    List<Match> currentMatches,
  ) async {
    if (state.value?.isProcessing == true) return;
    state = const AsyncValue.data(SchedulingState(isProcessing: true));

    try {
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
          continue; // Court already updated by another trigger.
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

        // Update local pairings cache from the output.
        for (final scheduled in output.newNextMatches) {
          for (final player in scheduled.matchResult.players) {
            final others = scheduled.matchResult.players
                .where((p) => p.id != player.id)
                .map((p) => p.id)
                .toList();
            final history =
                List<String>.from(_recentPairings[player.id] ?? []);
            history.insertAll(0, others);
            if (history.length > 12) history.removeRange(12, history.length);
            _recentPairings[player.id] = history;
          }
        }
      }

      state = const AsyncValue.data(SchedulingState());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Called when a new player joins — try to fill any courts missing a nextMatch.
  Future<void> onPlayerJoined() async {
    if (state.value?.isProcessing == true) return;
    state = const AsyncValue.data(SchedulingState(isProcessing: true));

    try {
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
      }

      state = const AsyncValue.data(SchedulingState());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final schedulingControllerProvider =
    AsyncNotifierProvider<SchedulingController, SchedulingState>(
  SchedulingController.new,
);
