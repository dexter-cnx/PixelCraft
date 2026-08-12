import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/film_profile_store.dart';
import '../../core/film_profile_v1.dart';
import 'film_profile_creator_screen.dart';

class FilmProfilesScreen extends StatefulWidget {
  const FilmProfilesScreen({
    super.key,
    this.store,
    this.selectionMode = false,
  });

  final FilmProfileStore? store;
  final bool selectionMode;

  @override
  State<FilmProfilesScreen> createState() => _FilmProfilesScreenState();
}

class _FilmProfilesScreenState extends State<FilmProfilesScreen> {
  late final FilmProfileStore _store = widget.store ?? FilmProfileStore();
  List<FilmProfileV1> _profiles = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final profiles = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _create([FilmProfileV1? profile]) async {
    final result = await Navigator.of(context).push<FilmProfileV1>(
      MaterialPageRoute(
        builder: (_) => FilmProfileCreatorScreen(
          initialProfile: profile,
          store: _store,
        ),
      ),
    );
    if (result != null) await _refresh();
  }

  Future<void> _duplicate(FilmProfileV1 profile) async {
    final duplicate = profile.duplicate(
      newId: 'user_${DateTime.now().microsecondsSinceEpoch}',
    );
    await _store.save(duplicate);
    await _refresh();
  }

  Future<void> _delete(FilmProfileV1 profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Film Profile?'),
        content: Text('Delete “${profile.name}”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(profile.id);
    await _refresh();
  }

  Future<void> _copyExport(FilmProfileV1 profile) async {
    await Clipboard.setData(ClipboardData(text: profile.encode()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Film Profile JSON copied to clipboard.')),
    );
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Film Profile'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              hintText: 'Paste .pixelcraftprofile JSON or recipe JSON',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (source == null || source.trim().isEmpty) return;

    try {
      FilmProfileV1 profile;
      FilmProfileImportReport? report;
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic> &&
          decoded['schema'] == pixelCraftProfileSchema) {
        profile = FilmProfileV1.decode(source).copyWith(
          origin: FilmProfileOrigin.imported,
        );
      } else if (decoded is Map<String, dynamic>) {
        report = importRecipeMap(
          decoded.cast<String, Object?>(),
          id: 'imported_${DateTime.now().microsecondsSinceEpoch}',
        );
        profile = report.profile;
      } else {
        throw const FormatException('Import must be a JSON object.');
      }
      await _store.save(profile);
      await _refresh();
      if (!mounted) return;
      if (report != null) {
        await _showMappingReport(report);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  Future<void> _showMappingReport(FilmProfileImportReport report) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import mapping'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final mapping in report.mappings)
                ListTile(
                  dense: true,
                  leading: Icon(switch (mapping.kind) {
                    FilmProfileMappingKind.exact => Icons.check_circle_outline,
                    FilmProfileMappingKind.approximated =>
                      Icons.change_circle_outlined,
                    FilmProfileMappingKind.unsupported =>
                      Icons.report_gmailerrorred_outlined,
                  }),
                  title: Text(mapping.sourceField),
                  subtitle: Text(
                    '${mapping.kind.name}${mapping.targetField == null ? '' : ' → ${mapping.targetField}'}'
                    '${mapping.note.isEmpty ? '' : '\n${mapping.note}'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _select(FilmProfileV1 profile) {
    if (!widget.selectionMode) {
      _create(profile);
      return;
    }
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode ? 'Load Film' : 'Films'),
        actions: [
          IconButton(
            tooltip: 'Import Film Profile',
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Create Film Profile',
            onPressed: () => _create(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_roll_outlined, size: 54),
                      const SizedBox(height: 12),
                      Text(
                        'No custom Films yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create a Film Profile or import a compatible recipe.',
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => _create(),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Film'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _profiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.camera_roll_outlined),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          [
                            if (profile.baseFilmId.isNotEmpty)
                              profile.baseFilmId.replaceAll('_', ' '),
                            '${profile.parameters.length} adjustments',
                            profile.origin.name,
                          ].join(' • '),
                        ),
                        onTap: () => _select(profile),
                        trailing: widget.selectionMode
                            ? const Icon(Icons.chevron_right)
                            : PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'duplicate':
                                      _duplicate(profile);
                                      break;
                                    case 'export':
                                      _copyExport(profile);
                                      break;
                                    case 'delete':
                                      _delete(profile);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'duplicate',
                                    child: Text('Duplicate'),
                                  ),
                                  PopupMenuItem(
                                    value: 'export',
                                    child: Text('Copy JSON'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(),
        icon: const Icon(Icons.add),
        label: const Text('Create Film'),
      ),
    );
  }
}
