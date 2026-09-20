import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../../ui/organisms/hina_map.dart';

class ShelterDetailPage extends ConsumerWidget {
  final ShelterInfo shelter;
  final Incident? incident;
  const ShelterDetailPage({super.key, required this.shelter, this.incident});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final loc = ref.watch(locationProvider);
    final isCurrent = incident?.shelter?.id == shelter.id;
    return Scaffold(
      appBar: AppBar(title: Text(shelter.name)),
      body: ListView(padding: const EdgeInsets.all(HinaSpace.m), children: [
        Container(
          height: 150,
          decoration: BoxDecoration(color: HinaColors.mist, borderRadius: BorderRadius.circular(HinaRadius.card)),
          alignment: Alignment.center,
          child: const Icon(Icons.school_outlined, size: 56, color: HinaColors.sky),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          const HinaTag('指定緊急避難場所', icon: Icons.verified_outlined, color: HinaColors.leaf),
          if (shelter.elevationM != null) HinaTag('標高 ${shelter.elevationM!.toStringAsFixed(1)}m', icon: Icons.terrain),
          HinaTag('徒歩 ${shelter.walkMin}分', icon: Icons.directions_walk),
          if (shelter.full) const HinaTag('満員', color: HinaColors.alert),
        ]),
        const SizedBox(height: 12),
        if (shelter.address.isNotEmpty) Text(shelter.address, style: t.bodyMedium),
        const SizedBox(height: 12),
        CrowdMeter(shelter.crowdPct),
        if (incident != null && isCurrent && incident!.reasons.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('セナヴィが選んだ理由', style: t.titleMedium),
          const SizedBox(height: 6),
          ReasonChips(incident!.reasons),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(HinaRadius.card),
            child: HinaMap(center: loc?.point ?? shelter.point, zoom: 14.5, shelters: [shelter], selected: shelter, route: incident?.route?.points ?? const [], showFlood: true),
          ),
        ),
        const SizedBox(height: 16),
        if (incident != null && incident!.state == IncidentState.proposing && isCurrent)
          HinaButton.primary('このルートで行く', onPressed: () async {
            await ref.read(agentControllerProvider).approveStart(incident!.id, byTimeout: false);
            if (context.mounted) Navigator.of(context).pop();
          })
        else if (incident != null && incident!.state.isGuiding && !isCurrent)
          HinaButton.secondary('周辺の避難所を探す(再選定)', onPressed: () async {
            await ref.read(agentControllerProvider).reselect(incident!.id, reason: 'user');
            if (context.mounted) Navigator.of(context).pop();
          })
        else
          const SizedBox.shrink(),
      ]),
    );
  }
}
