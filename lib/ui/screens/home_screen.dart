import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isImporting = false;

  Future<void> _openBytes(Future<List<int>> bytesFuture) async {
    final bytes = await bytesFuture;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(imageBytes: bytes)),
    );
  }

  Future<void> _importFromGallery() async {
    if (_isImporting) return;

    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;

      setState(() => _isImporting = true);
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() => _isImporting = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorScreen(imageBytes: Uint8List.fromList(bytes)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const samples = [
      'sample_1.png',
      'sample_2.png',
      'sample_3.png',
      'sample_4.png',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Pixel Craft')),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Edit locally. Move fast.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Flutter interface, Rust processing engine, zero uploads.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid.builder(
                  itemCount: samples.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) => InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _isImporting
                        ? null
                        : () => _openBytes(
                              DefaultAssetBundle.of(context)
                                  .load('assets/samples/${samples[index]}')
                                  .then((data) => data.buffer.asUint8List()),
                            ),
                    child: Hero(
                      tag: samples[index],
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/samples/${samples[index]}',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          if (_isImporting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          SizedBox(width: 12),
                          Text('Importing image…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: _isImporting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_isImporting ? 'Importing…' : 'Import from Gallery'),
        onPressed: _isImporting ? null : _importFromGallery,
      ),
    );
  }
}
