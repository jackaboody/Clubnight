// lib/presentation/tablet/widgets/court_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/match.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/presentation/providers/providers.dart';

class CourtCard extends ConsumerStatefulWidget {
  final Court court;

  const CourtCard({super.key, required this.court});

  @override
  ConsumerState<CourtCard> createState() => _CourtCardState();
}

class _CourtCardState extends ConsumerState<CourtCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.03).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final court = widget.court;
    final currentMatchAsync = court.currentMatchId != null
        ? ref.watch(matchByIdProvider(court.currentMatchId!))
        : null;
    final nextMatchAsync = court.nextMatchId != null
        ? ref.watch(matchByIdProvider(court.nextMatchId!))
        : null;
    final allPlayers = ref.watch(playersStreamProvider).valueOrNull ?? [];

    final isHolding = court.mode == CourtMode.holding;
    final hasActive = court.currentMatchId != null;
    final currentMatch = currentMatchAsync?.valueOrNull;
    final matchIsLive = currentMatch?.status == MatchStatus.active;
    final matchIsReady = currentMatch?.status == MatchStatus.scheduled;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: matchIsLive ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: Card(
        elevation: hasActive ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _borderColor(court, context),
            width: hasActive ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CourtHeader(court: court),
              const SizedBox(height: 12),
              if (isHolding) ...[
                const _HoldingBadge(),
              ] else ...[
                _MatchSection(
                  label: matchIsLive ? 'Now playing' : 'Ready to start',
                  matchAsync: currentMatchAsync,
                  allPlayers: allPlayers,
                  isActive: true,
                  court: court,
                ),
                const SizedBox(height: 12),
                _MatchSection(
                  label: 'Up next',
                  matchAsync: nextMatchAsync,
                  allPlayers: allPlayers,
                  isActive: false,
                  court: court,
                ),
                const SizedBox(height: 16),
                if (matchIsReady)
                  _StartMatchButton(match: currentMatch!)
                else if (matchIsLive)
                  _EndNowButton(
                    court: court,
                    match: currentMatch,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _borderColor(Court court, BuildContext context) {
    if (court.mode == CourtMode.holding) {
      return Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
    }
    final currentMatch = court.currentMatchId != null
        ? ref.watch(matchByIdProvider(court.currentMatchId!)).valueOrNull
        : null;
    if (currentMatch?.status == MatchStatus.active) {
      return court.mode == CourtMode.doubles
          ? Theme.of(context).colorScheme.secondary
          : Theme.of(context).colorScheme.primary;
    }
    if (currentMatch?.status == MatchStatus.scheduled) {
      return Colors.green.withValues(alpha: 0.6);
    }
    return Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);
  }
}

// ---------------------------------------------------------------------------

class _CourtHeader extends StatelessWidget {
  final Court court;
  const _CourtHeader({required this.court});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Court ${court.number}',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        _ModeBadge(mode: court.mode),
      ],
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final CourtMode mode;
  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (mode) {
      CourtMode.singles => ('Singles', Colors.blue),
      CourtMode.doubles => ('Doubles', Colors.purple),
      CourtMode.holding => ('Holding', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MatchSection extends StatelessWidget {
  final String label;
  final AsyncValue<Match?>? matchAsync;
  final List<Player> allPlayers;
  final bool isActive;
  final Court court;

  const _MatchSection({
    required this.label,
    required this.matchAsync,
    required this.allPlayers,
    required this.isActive,
    required this.court,
  });

  @override
  Widget build(BuildContext context) {
    if (matchAsync == null) {
      return _EmptySlot(label: label, isActive: isActive);
    }

    return matchAsync!.when(
      data: (match) {
        if (match == null) return _EmptySlot(label: label, isActive: isActive);
        final matchPlayers =
            allPlayers.where((p) => match.playerIds.contains(p.id)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            _PlayerList(players: matchPlayers, type: match.type),
            if (isActive && match.remainingTime != null) ...[
              const SizedBox(height: 6),
              _MatchTimer(match: match),
            ],
            if (!isActive && match.type == MatchType.doubles) ...[
              const SizedBox(height: 4),
              _DoublesReadiness(
                readyCount: matchPlayers.length,
                requiredCount: 4,
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const Text('Error loading match'),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final String label;
  final bool isActive;
  const _EmptySlot({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.5),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isActive ? 'Court free' : 'Waiting for players…',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.4),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PlayerList extends StatelessWidget {
  final List<Player> players;
  final MatchType type;
  const _PlayerList({required this.players, required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == MatchType.singles && players.length == 2) {
      return Row(
        children: [
          _PlayerChip(player: players[0]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'vs',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
          _PlayerChip(player: players[1]),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: players.map((p) => _PlayerChip(player: p)).toList(),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final Player player;
  const _PlayerChip({required this.player});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '${player.name} (${player.level.toStringAsFixed(1)})',
        style: const TextStyle(fontSize: 12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------

class _MatchTimer extends ConsumerStatefulWidget {
  final Match match;
  const _MatchTimer({required this.match});

  @override
  ConsumerState<_MatchTimer> createState() => _MatchTimerState();
}

class _MatchTimerState extends ConsumerState<_MatchTimer> {
  late final Stream<Duration?> _timerStream;
  bool _autoEndTriggered = false;

  @override
  void initState() {
    super.initState();
    _timerStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => widget.match.remainingTime,
    );
  }

  @override
  void didUpdateWidget(_MatchTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id) {
      _autoEndTriggered = false;
    }
  }

  void _maybeAutoEnd(Duration? remaining) {
    if (_autoEndTriggered) return;
    if (remaining != Duration.zero) return;
    if (widget.match.status != MatchStatus.active) return;
    _autoEndTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(matchRepositoryProvider).endMatch(
            matchId: widget.match.id,
            playerIds: widget.match.playerIds,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: _timerStream,
      initialData: widget.match.remainingTime,
      builder: (context, snap) {
        final remaining = snap.data;
        if (remaining == null) return const SizedBox.shrink();

        _maybeAutoEnd(remaining);

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

// ---------------------------------------------------------------------------

class _DoublesReadiness extends StatelessWidget {
  final int readyCount;
  final int requiredCount;
  const _DoublesReadiness({
    required this.readyCount,
    required this.requiredCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(requiredCount, (i) {
          final filled = i < readyCount;
          return Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? Colors.green : Colors.grey.shade300,
            ),
          );
        }),
        const SizedBox(width: 6),
        Text(
          '$readyCount/$requiredCount ready',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _HoldingBadge extends StatelessWidget {
  const _HoldingBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(Icons.pause_circle_outline,
              size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'Court on hold',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StartMatchButton extends ConsumerWidget {
  final Match match;
  const _StartMatchButton({required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => ref.read(matchRepositoryProvider).startMatch(
              matchId: match.id,
              durationMinutes: match.durationMinutes,
            ),
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Start match'),
        style: FilledButton.styleFrom(backgroundColor: Colors.green),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EndNowButton extends ConsumerWidget {
  final Court court;
  final Match? match;
  const _EndNowButton({required this.court, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed:
            match == null ? null : () => _confirmEnd(context, ref, match!),
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: const Text('End Now'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Future<void> _confirmEnd(
      BuildContext context, WidgetRef ref, Match match) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End Match?'),
        content: const Text(
          'This will end the current match. Press Start on the next match when players are ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Now'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(matchRepositoryProvider).endMatch(
            matchId: match.id,
            playerIds: match.playerIds,
          );
    }
  }
}
