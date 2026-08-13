import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixelcraft_film/pixelcraft_film.dart';

import '../../core/film_profile_store.dart';
import '../../core/film_profile_v1.dart';
import 'film_profile_creator_screen.dart';

class FilmProfilesScreen extends StatefulWidget {
  const FilmProfilesScreen({
    super.key,
    this.store,
    this.library,
    this.selectionMode = false,
  });

  final FilmProfileStore? store;
  final FilmProfileLibrary? library;
  final bool selectionMode;

  @override
  State<FilmProfilesScreen> createState() => _FilmProfilesScreenState();
}

class _FilmProfilesScreenState extends State<FilmProfilesScreen> {
  late final FilmProfileStore _store = widget.store ?? FilmProfileStore();
  late final FilmProfileLibrary _library =
      widget.library ?? FilmProfileLibrary(_store);
  final SearchController _searchController = SearchController();
  List<FilmProfileV1> _profiles = const [];
  bool _loading = true;
  String _query = '';
  FilmProfileOrigin? _originFilter;

  List<FilmProfileV1> get _visibleProfiles => FilmProfileQuery(
        text: _query,
        origins: _originFilter == null
            ? const <FilmProfileOrigin>{}
            : <FilmProfileOrigin>{_originFilter!},
      ).apply(_profiles);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _originFilter = null;
    });
  }

  Future<void> _refresh() async {
    final profiles = await _library.loadAll();
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
    await _library.duplicate(
      profile,
      newId: 'user_${DateTime.now().microsecondsSinceEpoch}',
    );
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
    await _library.delete(profile.id);
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
      final result = await _library.importSource(
        source,
        importedId: 'imported_${DateTime.now().microsecondsSinceEpoch}',
      );
      await _refresh();
      if (!mounted) return;
      final report = result.report;
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

  Widget _libraryControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBar(
            key: const ValueKey('film_profile_search'),
            controller: _searchController,
            hintText: 'Search Films, tags, descriptions…',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  key: const ValueKey('film_origin_all'),
                  label: const Text('All'),
                  selected: _originFilter == null,
                  onSelected: (_) => setState(() => _originFilter = null),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const ValueKey('film_origin_user'),
                  label: const Text('Created'),
                  selected: _originFilter == FilmProfileOrigin.user,
                  onSelected: (_) =>
                      setState(() => _originFilter = FilmProfileOrigin.user),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const ValueKey('film_origin_imported'),
                  label: const Text('Imported'),
                  selected: _originFilter == FilmProfileOrigin.imported,
                  onSelected: (_) => setState(
                    () => _originFilter = FilmProfileOrigin.imported,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyLibrary() => Center(
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
            const Text('Create a Film Profile or import a compatible recipe.'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _create(),
              icon: const Icon(Icons.add),
              label: const Text('Create Film'),
            ),
          ],
        ),
      );

  Widget _noMatches() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                'No matching Films',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text('Try another search or show all profile origins.'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _clearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final visibleProfiles = _visibleProfiles;
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
              ? _emptyLibrary()
              : Column(
                  children: [
                    _libraryControls(),
                    Expanded(
                      child: visibleProfiles.isEmpty
                          ? _noMatches()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: visibleProfiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final profile = visibleProfiles[index];
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
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(),
        icon: const Icon(Icons.add),
        label: const Text('Create Film'),
      ),
    );
  }
}
