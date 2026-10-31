import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../services/auth_service.dart';
import '../services/party_service.dart';
import '../services/torbox_service.dart';
import '../services/user_service.dart';
import 'party_ui.dart';

/// Opens the watch-party sheet from a title's detail page. The sheet has three
/// states:
///  - a party is already active: show its code and Resume, or Go to the show
///    it is watching, plus End or Leave;
///  - no party yet: host one (get a code, then Start party) or join with a code.
Future<void> showPartySheet(
  BuildContext context, {
  required String currentTitle,
  required PartySession? activeParty,
  required Future<PartySession?> Function() onHost,
  required void Function(PartySession session) onStart,
}) async {
  final joined = await showModalBottomSheet<({String pin, PartyMeta meta})>(
    context: context,
    backgroundColor: AppTheme.cardDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PartySheet(
      currentTitle: currentTitle,
      activeParty: activeParty,
      onHost: onHost,
      onStart: (session) {
        Navigator.pop(ctx);
        onStart(session);
      },
    ),
  );
  if (joined != null && context.mounted) {
    await _enterGuestParty(context, joined.pin, joined.meta);
  }
}

/// Returns why this device can't play the party's stream the way the host
/// does, or null if it can. A TorBox party needs TorBox set up on this account;
/// otherwise the guest would silently stream P2P, which is not in sync with
/// the host's source.
String? partyStreamProblem(PartyMeta meta) {
  if (meta.streamMode != 'torbox') return null;
  final ready = UserService.torrentMode == 'torbox' && TorBoxService().isConfigured;
  if (ready) return null;
  return 'This party streams through TorBox. Add your TorBox key and switch '
      'to TorBox in Settings to join.';
}

/// Joins [pin] as a guest, leaving any previous party, then opens the host's
/// show so playback starts in sync with the host.
Future<void> _enterGuestParty(
  BuildContext context,
  String pin,
  PartyMeta meta,
) async {
  final previous = PartyService.current;
  if (previous != null) await PartyService.endOrLeave(previous);

  final session = PartySession(pin: pin, meta: meta, isHost: false);
  PartyService.current = session;
  await session.connect();
  if (!context.mounted) return;
  openPartyShow(context, session);
}

/// Opens the show a party is watching, already joined to that party. Does
/// nothing if this party's show is already on screen or playing.
void openPartyShow(BuildContext context, PartySession session) {
  if (session.roomScreenOpen || session.playerOpen.value) return;
  session.roomScreenOpen = true;
  final meta = session.currentMeta;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DetailPage(
      content: ContentModel(
        title: meta.title,
        description: '',
        thumbnailUrl: meta.posterUrl,
        bannerUrl: meta.posterUrl,
        m3u8Url: '',
        year: meta.year,
        videoSourceName: meta.sourceName,
      ),
      joinParty: session,
    ),
  ));
}

class _PartySheet extends StatefulWidget {
  final String currentTitle;
  final PartySession? activeParty;
  final Future<PartySession?> Function() onHost;
  final void Function(PartySession session) onStart;

  const _PartySheet({
    required this.currentTitle,
    required this.activeParty,
    required this.onHost,
    required this.onStart,
  });

  @override
  State<_PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends State<_PartySheet> {
  final TextEditingController _pinController = TextEditingController();
  bool _hosting = false;
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _host() async {
    if (!AuthService.isLoggedIn) {
      setState(() => _error = 'Sign in to host a party.');
      return;
    }
    setState(() {
      _hosting = true;
      _error = null;
    });
    final session = await widget.onHost();
    if (!mounted) return;
    setState(() {
      _hosting = false;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    setState(() {
      if (text.isEmpty) {
        _error = 'Nothing to paste. Copy the code first.';
      } else {
        _pinController.text = PartyService.normalisePin(text);
        _error = null;
      }
    });
  }

  Future<void> _join() async {
    final pin = PartyService.normalisePin(_pinController.text);
    if (pin.length < 6) {
      setState(() => _error = 'Enter the 8-character code from your host.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final meta = await PartyService.lookup(pin);
      if (!mounted) return;
      if (meta == null) {
        setState(() {
          _joining = false;
          _error = 'No party found for that code.';
        });
        return;
      }
      final problem = partyStreamProblem(meta);
      if (problem != null) {
        setState(() {
          _joining = false;
          _error = problem;
        });
        return;
      }
      Navigator.pop(context, (pin: pin, meta: meta));
    } on PartyException catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = e.message;
        });
      }
    }
  }

  /// Ends the party for everyone when hosting, or leaves it as a guest.
  Future<void> _endOrLeave(PartySession party) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasHost = party.isHost;
    Navigator.pop(context);
    await PartyService.endOrLeave(party);
    messenger.showSnackBar(SnackBar(
      content: Text(wasHost ? 'Party ended' : 'You left the party'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeParty ?? PartyService.current;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            active == null
                ? 'Watch Party'
                : active.isHost
                    ? 'Your party'
                    : 'You are in a party',
            style: partyTitleStyle,
          ),
          const SizedBox(height: 4),
          Text(
            active == null
                ? 'Watch together, in sync.'
                : active.isHost
                    ? 'Share the code. Friends see you at the top right.'
                    : 'Playback follows the host.',
            style: partySubtitleStyle,
          ),
          const SizedBox(height: 24),
          if (active != null) _buildActive(active) else _buildChoice(),
        ],
      ),
    );
  }

  Widget _buildActive(PartySession party) {
    final sameShow = party.meta.title == widget.currentTitle;
    final String primaryLabel;
    final VoidCallback primaryTap;
    if (!sameShow) {
      primaryLabel = 'Go to ${party.meta.title}';
      primaryTap = () => _openFromSheet(party);
    } else if (party.isHost && !party.live.value) {
      // Confirms the group; the host then picks an episode to start.
      primaryLabel = 'OK';
      primaryTap = () => widget.onStart(party);
    } else {
      primaryLabel = 'Resume watching';
      primaryTap = () => widget.onStart(party);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PartyCodeCard(session: party),
        const SizedBox(height: 12),
        ValueListenableBuilder<List<String>>(
          valueListenable: party.members,
          builder: (_, names, __) => Text(
            partyMemberLine(names),
            style: partySubtitleStyle.copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),
        partyPrimaryButton(label: primaryLabel, onTap: primaryTap),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: partyDangerButton(
            label: party.isHost ? 'End party' : 'Leave party',
            icon: LucideIcons.logOut,
            onTap: () => _endOrLeave(party),
          ),
        ),
      ],
    );
  }

  void _openFromSheet(PartySession party) {
    final nav = Navigator.of(context);
    nav.pop();
    openPartyShow(nav.context, party);
  }

  Widget _buildChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        partyPanel(
          child: Row(
            children: [
              const Icon(LucideIcons.users, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Host a party',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Get a code to share',
                      style: partySubtitleStyle.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              partySecondaryButton(
                label: _hosting ? '...' : 'Get code',
                onTap: _hosting ? () {} : _host,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Join with a code',
          style: partySubtitleStyle.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pinController,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _join(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            letterSpacing: 4,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: 'CODE',
            hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 4),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: AppTheme.radiusPill,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppTheme.radiusPill,
              borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
            ),
            suffixIcon: IconButton(
              tooltip: 'Paste code',
              icon: const Icon(LucideIcons.clipboardPaste, color: AppTheme.textSecondary),
              onPressed: _pasteFromClipboard,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 13,
              decoration: TextDecoration.none,
            ),
          ),
        ],
        const SizedBox(height: 16),
        partyPrimaryButton(label: 'Join party', onTap: _join, busy: _joining),
      ],
    );
  }
}
