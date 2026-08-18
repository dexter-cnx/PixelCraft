import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/platform_flow_foundation.dart';
import '../../app/platform_media_services.dart';

/// Increment this only when a release has user-facing What's New content.
const currentWhatsNewId = 'camera-first-pf3-2026-08';

const _dxtrOrange = Color(0xFFFF6A00);
const _dxtrOrangeDeep = Color(0xFFB83D00);
const _dxtrBlack = Color(0xFF070707);

class GreetingGate extends StatefulWidget {
  const GreetingGate({super.key, required this.child});

  final Widget child;

  @override
  State<GreetingGate> createState() => _GreetingGateState();
}

class _GreetingGateState extends State<GreetingGate> {
  static const _permissionsPromptedKey = 'greeting.permissions_prompted';
  static const _whatsNewSeenKey = 'greeting.whats_new_seen';

  bool _loading = true;
  bool _showGreeting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final permissionsPrompted = prefs.getBool(_permissionsPromptedKey) ?? false;
    final seenWhatsNew = prefs.getString(_whatsNewSeenKey);
    if (!mounted) return;
    setState(() {
      _showGreeting = !permissionsPrompted || seenWhatsNew != currentWhatsNewId;
      _loading = false;
    });
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionsPromptedKey, true);
    await prefs.setString(_whatsNewSeenKey, currentWhatsNewId);
    if (mounted) setState(() => _showGreeting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _dxtrBlack,
        body: Center(child: CircularProgressIndicator(color: _dxtrOrange)),
      );
    }
    if (!_showGreeting) return widget.child;
    return GreetingScreen(onContinue: _complete);
  }
}

class GreetingScreen extends StatefulWidget {
  const GreetingScreen({super.key, required this.onContinue});

  final Future<void> Function() onContinue;

  @override
  State<GreetingScreen> createState() => _GreetingScreenState();
}

class _GreetingScreenState extends State<GreetingScreen> {
  final PermissionService _permissionService =
      const PlatformPermissionService();

  PermissionDecision? _cameraPermission;
  PermissionDecision? _galleryPermission;
  bool _requesting = false;
  bool _continuing = false;

  bool get _permissionsSettled =>
      _cameraPermission != null && _galleryPermission != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_requestPermissions());
    });
  }

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final camera = await _permissionService.requestCamera();
      final gallery = await _permissionService.requestGalleryWrite();
      if (!mounted) return;
      setState(() {
        _cameraPermission = camera;
        _galleryPermission = gallery;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraPermission ??= PermissionDecision.denied;
        _galleryPermission ??= PermissionDecision.denied;
      });
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _continue() async {
    if (!_permissionsSettled || _continuing) return;
    setState(() => _continuing = true);
    await widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _dxtrBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_dxtrBlack, Color(0xFF201007), Color(0xFF030303)],
              ),
            ),
          ),
          const Positioned(right: -90, top: -80, child: _LensGlow(size: 290)),
          const Positioned(
            left: -130,
            bottom: 120,
            child: _LensGlow(size: 330),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _CameraMark(),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'greeting.title'.tr(),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'greeting.subtitle'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 34),
                      Text(
                        'greeting.whats_new'.tr(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: _dxtrOrange,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FeatureRow(
                        icon: Icons.camera_alt_rounded,
                        title: 'greeting.feature_camera_title'.tr(),
                        body: 'greeting.feature_camera_body'.tr(),
                      ),
                      _FeatureRow(
                        icon: Icons.auto_awesome_rounded,
                        title: 'greeting.feature_looks_title'.tr(),
                        body: 'greeting.feature_looks_body'.tr(),
                      ),
                      _FeatureRow(
                        icon: Icons.speed_rounded,
                        title: 'greeting.feature_process_title'.tr(),
                        body: 'greeting.feature_process_body'.tr(),
                      ),
                      const SizedBox(height: 22),
                      _PermissionCard(
                        camera: _cameraPermission,
                        gallery: _galleryPermission,
                        requesting: _requesting,
                        onRetry: _requestPermissions,
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _permissionsSettled && !_continuing
                            ? _continue
                            : null,
                        icon: _continuing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text('greeting.continue'.tr()),
                        style: FilledButton.styleFrom(
                          backgroundColor: _dxtrOrange,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF422114),
                          disabledForegroundColor: Colors.white38,
                          minimumSize: const Size.fromHeight(54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _dxtrOrange.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _dxtrOrange.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, color: _dxtrOrange),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(color: Colors.white60, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.camera,
    required this.gallery,
    required this.requesting,
    required this.onRetry,
  });

  final PermissionDecision? camera;
  final PermissionDecision? gallery;
  final bool requesting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _dxtrOrange.withValues(alpha: 0.22)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'greeting.permissions_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _PermissionLine(
            icon: Icons.camera_alt_outlined,
            label: 'greeting.permission_camera'.tr(),
            decision: camera,
          ),
          const SizedBox(height: 8),
          _PermissionLine(
            icon: Icons.photo_library_outlined,
            label: 'greeting.permission_gallery'.tr(),
            decision: gallery,
          ),
          if (requesting) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(color: _dxtrOrange),
          ] else if (camera != PermissionDecision.granted ||
              gallery != PermissionDecision.granted) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('greeting.retry_permissions'.tr()),
              style: TextButton.styleFrom(foregroundColor: _dxtrOrange),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({
    required this.icon,
    required this.label,
    required this.decision,
  });

  final IconData icon;
  final String label;
  final PermissionDecision? decision;

  @override
  Widget build(BuildContext context) {
    final granted = decision == PermissionDecision.granted;
    final trailing = decision == null
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _dxtrOrange,
            ),
          )
        : Icon(
            granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: granted ? _dxtrOrange : Colors.amberAccent,
          );
    return Row(
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        trailing,
      ],
    );
  }
}

class _CameraMark extends StatelessWidget {
  const _CameraMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    height: 76,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(colors: [_dxtrOrange, _dxtrOrangeDeep]),
      boxShadow: const [
        BoxShadow(color: Color(0x66FF6A00), blurRadius: 30, spreadRadius: 4),
      ],
    ),
    child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 38),
  );
}

class _LensGlow extends StatelessWidget {
  const _LensGlow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          _dxtrOrange.withValues(alpha: 0.24),
          _dxtrOrange.withValues(alpha: 0),
        ],
      ),
    ),
  );
}
