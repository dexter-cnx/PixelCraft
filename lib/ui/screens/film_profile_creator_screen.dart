import 'package:flutter/material.dart';

import '../../core/film_profile_store.dart';
import '../../core/film_profile_v1.dart';

class FilmProfileCreatorScreen extends StatefulWidget {
  const FilmProfileCreatorScreen({
    super.key,
    this.initialProfile,
    this.store,
  });

  final FilmProfileV1? initialProfile;
  final FilmProfileStore? store;

  @override
  State<FilmProfileCreatorScreen> createState() => _FilmProfileCreatorScreenState();
}

class _FilmProfileCreatorScreenState extends State<FilmProfileCreatorScreen> {
  static const _baseFilms = <String, String>{
    '': 'None',
    'provia_inspired': 'Provia Inspired',
    'velvia_inspired': 'Velvia Inspired',
    'astia_inspired': 'Astia Inspired',
    'e100_inspired': 'E100 Inspired',
    'ektar_inspired': 'Ektar Inspired',
    'chrome64_inspired': 'Chrome 64 Inspired',
  };

  late final FilmProfileStore _store = widget.store ?? FilmProfileStore();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final Map<String, double> _values;
  late String _baseFilmId;
  late double _baseStrength;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _nameController = TextEditingController(text: profile?.name ?? 'My Film');
    _descriptionController = TextEditingController(text: profile?.description ?? '');
    _tagsController = TextEditingController(text: profile?.tags.join(', ') ?? '');
    _values = {
      for (final spec in filmProfileParameterSpecs)
        spec.id: profile?.parameters[spec.id] ?? spec.neutral,
    };
    _baseFilmId = profile?.baseFilmId ?? '';
    _baseStrength = profile?.baseStrength ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  String _newId() => 'user_${DateTime.now().microsecondsSinceEpoch}';

  FilmProfileV1 _buildProfile() {
    final previous = widget.initialProfile;
    return FilmProfileV1(
      id: previous?.id ?? _newId(),
      name: _nameController.text.trim().isEmpty ? 'Untitled Film' : _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      origin: FilmProfileOrigin.user,
      baseFilmId: _baseFilmId,
      baseStrength: _baseStrength,
      parameters: Map.of(_values),
      tags: _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final profile = _buildProfile();
      await _store.save(profile);
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save Film Profile: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<FilmProfileParameterSpec>>{};
    for (final spec in filmProfileParameterSpecs) {
      grouped.putIfAbsent(spec.group, () => []).add(spec);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialProfile == null ? 'Create Film' : 'Edit Film'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _baseFilms.containsKey(_baseFilmId) ? _baseFilmId : '',
              decoration: const InputDecoration(labelText: 'Base Film'),
              items: _baseFilms.entries
                  .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                  .toList(),
              onChanged: (value) => setState(() => _baseFilmId = value ?? ''),
            ),
            if (_baseFilmId.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ProfileSlider(
                label: 'Base Film Strength',
                value: _baseStrength,
                min: 0,
                max: 1,
                onChanged: (value) => setState(() => _baseStrength = value),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'portrait, warm, summer',
              ),
            ),
            const SizedBox(height: 20),
            for (final entry in grouped.entries)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: entry.key == 'Tone' || entry.key == 'Color',
                  title: Text(entry.key),
                  subtitle: Text('${entry.value.length} controls'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final spec in entry.value)
                      _ProfileSlider(
                        label: spec.label,
                        unit: spec.unit,
                        value: _values[spec.id] ?? spec.neutral,
                        min: spec.min,
                        max: spec.max,
                        neutral: spec.neutral,
                        onChanged: (value) => setState(() => _values[spec.id] = value),
                        onReset: () => setState(() => _values[spec.id] = spec.neutral),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSlider extends StatelessWidget {
  const _ProfileSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.neutral,
    this.onReset,
    this.unit = '',
  });

  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final double? neutral;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final changed = neutral != null && (value - neutral!).abs() > 0.000001;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('${value.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}'),
              if (changed && onReset != null)
                IconButton(
                  tooltip: 'Reset $label',
                  visualDensity: VisualDensity.compact,
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: 100,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
