import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'greeting_screen.dart';

const _aboutOrange = Color(0xFFFF6A00);

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  bool get _hasWhatsNew => currentWhatsNewId.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('about.title'.tr()),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Icon(
            Icons.camera_alt_rounded,
            color: _aboutOrange,
            size: 54,
          ),
          const SizedBox(height: 14),
          Text(
            'app.title'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'about.tagline'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, height: 1.4),
          ),
          if (_hasWhatsNew) ...[
            const SizedBox(height: 28),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _aboutOrange.withValues(alpha: 0.28),
                ),
              ),
              tileColor: _aboutOrange.withValues(alpha: 0.08),
              leading: const Icon(Icons.auto_awesome_rounded),
              iconColor: _aboutOrange,
              textColor: Colors.white,
              title: Text('about.whats_new'.tr()),
              subtitle: Text(
                currentWhatsNewId,
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WhatsNewScreen(),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('about.whats_new'.tr()),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'greeting.whats_new'.tr(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _aboutOrange,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const _WhatsNewItem(
            icon: Icons.camera_alt_rounded,
            titleKey: 'greeting.feature_camera_title',
            bodyKey: 'greeting.feature_camera_body',
          ),
          const _WhatsNewItem(
            icon: Icons.auto_awesome_rounded,
            titleKey: 'greeting.feature_looks_title',
            bodyKey: 'greeting.feature_looks_body',
          ),
          const _WhatsNewItem(
            icon: Icons.speed_rounded,
            titleKey: 'greeting.feature_process_title',
            bodyKey: 'greeting.feature_process_body',
          ),
        ],
      ),
    ),
  );
}

class _WhatsNewItem extends StatelessWidget {
  const _WhatsNewItem({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

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
            color: _aboutOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _aboutOrange.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(icon, color: _aboutOrange),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleKey.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                bodyKey.tr(),
                style: const TextStyle(color: Colors.white60, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
