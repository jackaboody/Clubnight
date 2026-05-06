// presentation/mobile/widgets/player_status_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/presentation/providers/providers.dart';

class PlayerStatusCard extends ConsumerWidget {
  final String playerId;
  const PlayerStatusCard({super.key, required this.playerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAsync = ref.watch(playerMatchViewProvider(playerId));

    return viewAsync.when(
      data: (view) => _PlayerStatusContent(view: view),
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $e'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PlayerStatusContent extends StatelessWidget {
  final PlayerMatchView view;
  const _PlayerStatusContent({required this.view});

  @override
  Widget build(BuildContext context) {
    final player = view.player;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlayerHeader(player: player),
            const SizedBox(height: 16),
            _StatusBanner(status: player.status),
            const SizedBox(height: 16),
            if (player.status == PlayerStatus.playing &&
                view.currentMatch != null) ...[
              _ActiveMatchInfo(
                match: view.currentMatch!,
                court: view.currentCourt,
              ),
            ],
            if (view.nextMatch != null) ...[
              const SizedBox(height: 16),
              _NextMatchInfo(match: view.nextMatch!),
            ],
            const SizedBox(height: 16),
            _QuickActions(player: player),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PlayerHeader extends StatelessWidget {
  final Player player;
  const _PlayerHeader({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.15),
          child: Text(
            player.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              player.name,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Level ${player.level.toStringAsFixed(1)} · ${player.matchesPlayed} matches tonight',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final PlayerStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      PlayerStatus.waiting =>
        ('Waiting for a match', Icons.hourglass_empty, Colors.orange),
      PlayerStatus.playing =>
        ('Currently playing', Icons.sports_tennis, Colors.green),
      PlayerStatus.unavailable =>
        ('Unavailable', Icons.pause, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ActiveMatchInfo extends StatelessWidget {
  final Match match;
  final Court? court;
  const _ActiveMatchInfo({required this.match, this.court});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current match',
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (court != null)
          Text('Court ${court!.number} · ${match.type.name}'),
        if (match.remainingTime != null) ...[
          const SizedBox(height: 4),
          _MatchTimer(match: match),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _NextMatchInfo extends StatelessWidget {
  final Match match;
  const _NextMatchInfo({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'You\'re up next — ${match.type.name}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  final Player player;
  const _QuickActions({required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(firestoreProvider);
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: const Text('Available'),
          selected: player.status != PlayerStatus.unavailable,
          onSelected: (val) {
            db.collection('players').doc(player.id).update({
              'status': val
                  ? PlayerStatus.waiting.name
                  : PlayerStatus.unavailable.name,
            });
          },
        ),
        FilterChip(
          label: const Text('Doubles'),
          selected: player.prefersDoubles,
          onSelected: (val) {
            db.collection('players').doc(player.id).update({
              'prefersDoubles': val,
            });
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _MatchTimer extends StatefulWidget {
  final Match match;
  const _MatchTimer({required this.match});

  @override
  State<_MatchTimer> createState() => _MatchTimerState();
}

class _MatchTimerState extends State<_MatchTimer> {
  late final Stream<Duration?> _timerStream;

  @override
  void initState() {
    super.initState();
    _timerStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => widget.match.remainingTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: _timerStream,
      initialData: widget.match.remainingTime,
      builder: (context, snap) {
        final remaining = snap.data;
        if (remaining == null) return const SizedBox.shrink();

        final isOvertime = remaining == Duration.zero;
        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;
        final label = isOvertime
            ? 'Overtime'
            : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        return Row(
          children: [
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: isOvertime ? Colors.red : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isOvertime ? Colors.red : null,
                fontWeight:
                    isOvertime ? FontWeight.bold : FontWeight.normal,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
