import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/app_keys.dart';
import '../core/theme.dart';
import '../services/party_service.dart';
import 'buttons.dart';

/// Shared look for the watch-party sheets, so every party surface matches the
/// rest of the app: dark panels, white primary buttons, grey secondary
/// buttons, and the accent colour for anything that ends or leaves.

const TextStyle partyTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 20,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.none,
);

const TextStyle partySubtitleStyle = TextStyle(
  color: AppTheme.textSecondary,
  fontSize: 14,
  decoration: TextDecoration.none,
);

Widget partyPanel({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.background,
      borderRadius: AppTheme.radius16,
    ),
    child: child,
  );
}

Widget partyPrimaryButton({
  required String label,
  required VoidCallback onTap,
  bool busy = false,
}) {
  return SizedBox(
    width: double.infinity,
    child: HoverButton(
      onTap: busy ? () {} : onTap,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    decoration: TextDecoration.none,
                  ),
                ),
        ),
      ),
    ),
  );
}

Widget partySecondaryButton({
  required String label,
  IconData? icon,
  required VoidCallback onTap,
}) {
  return HoverButton(
    onTap: onTap,
    backgroundColor: const Color(0x662F3640),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget partyDangerButton({
  required String label,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return HoverButton(
    onTap: onTap,
    backgroundColor: AppTheme.accent.withOpacity(0.2),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Copies the party code and confirms with a short notice.
void copyPartyCode(String pin) {
  Clipboard.setData(ClipboardData(text: pin));
  appMessengerKey.currentState?.showSnackBar(
    const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 2)),
  );
}

/// Human-readable member line: "Just you" or "2 watching".
String partyMemberLine(List<String> names) {
  final count = names.isEmpty ? 1 : names.length;
  return count == 1 ? 'Just you' : '$count watching';
}

/// The party code, large and copyable, with the viewer count beside it.
class PartyCodeCard extends StatelessWidget {
  final PartySession session;

  const PartyCodeCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return partyPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARTY CODE',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.8),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  session.pin,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: () => copyPartyCode(session.pin),
            icon: const Icon(LucideIcons.copy, color: Colors.white70, size: 20),
          ),
        ],
      ),
    );
  }
}

/// The single status line shown over the player during a party, such as
/// "Ana is buffering" or "Back in sync". It fades in and out in place, so a
/// burst of events never stacks on screen.
class PartyStatusPill extends StatelessWidget {
  final PartySession party;

  const PartyStatusPill({super.key, required this.party});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: party.status,
      builder: (_, text, __) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: text == null
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Center(
                key: ValueKey(text),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (text.contains('buffering')) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// The party status line for pages other than the player, such as "Waiting
/// for the host to start". Hidden while the player is showing the party, which
/// has its own line.
class PartyGlobalStatus extends StatelessWidget {
  const PartyGlobalStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PartySession?>(
      valueListenable: PartyService.currentListenable,
      builder: (_, session, __) {
        if (session == null) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: session.playerOpen,
          builder: (_, open, __) {
            if (open) return const SizedBox.shrink();
            return IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(top: 64),
                child: PartyStatusPill(party: session),
              ),
            );
          },
        );
      },
    );
  }
}
