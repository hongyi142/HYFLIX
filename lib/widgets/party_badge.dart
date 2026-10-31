import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/app_keys.dart';
import '../core/theme.dart';
import '../services/party_service.dart';
import 'party_ui.dart';

/// Small top-right indicator shown on every page while a party is active. It
/// shows how many people are watching and opens the party controls.
class PartyBadge extends StatelessWidget {
  const PartyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PartySession?>(
      valueListenable: PartyService.currentListenable,
      builder: (_, session, __) {
        if (session == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: _BadgePill(session: session),
        );
      },
    );
  }
}

class _BadgePill extends StatelessWidget {
  final PartySession session;

  const _BadgePill({required this.session});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: session.members,
      builder: (_, names, __) {
        final count = names.isEmpty ? 1 : names.length;
        return ValueListenableBuilder<List<String>>(
          valueListenable: session.waitingFor,
          builder: (_, waiting, __) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final ctx = appNavigatorKey.currentContext;
                if (ctx != null) showPartyManageSheet(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: waiting.isEmpty ? AppTheme.accent : Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.users, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the party controls from the badge: the code, who is watching, and
/// End party (host) or Leave party (guest).
Future<void> showPartyManageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.cardDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PartyManageSheet(),
  );
}

class _PartyManageSheet extends StatelessWidget {
  const _PartyManageSheet();

  @override
  Widget build(BuildContext context) {
    final session = PartyService.current;
    if (session == null) {
      return const SizedBox(height: 120);
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.isHost ? 'Hosting a party' : 'Watching together',
              style: partyTitleStyle,
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<List<String>>(
              valueListenable: session.members,
              builder: (_, names, __) => Text(
                partyMemberLine(names),
                style: partySubtitleStyle,
              ),
            ),
            const SizedBox(height: 20),
            PartyCodeCard(session: session),
            const SizedBox(height: 16),
            ValueListenableBuilder<List<String>>(
              valueListenable: session.members,
              builder: (_, names, __) => names.length > 1
                  ? Text(
                      names.join(', '),
                      style: partySubtitleStyle.copyWith(fontSize: 13),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
            partyDangerButton(
              label: session.isHost ? 'End party' : 'Leave party',
              icon: LucideIcons.logOut,
              onTap: () async {
                final wasHost = session.isHost;
                Navigator.pop(context);
                await PartyService.endOrLeave(session);
                appMessengerKey.currentState?.showSnackBar(SnackBar(
                  content: Text(wasHost ? 'Party ended' : 'You left the party'),
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}
