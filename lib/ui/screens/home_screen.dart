import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openBytes(BuildContext context, Future<List<int>> bytesFuture) async {
    final bytes = await bytesFuture;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(imageBytes: bytes)));
  }

  @override
  Widget build(BuildContext context) {
    const samples = ['sample_1.png', 'sample_2.png', 'sample_3.png', 'sample_4.png'];
    return Scaffold(
      appBar: AppBar(title: const Text('PixelCraft')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            sliver: SliverList.list(children: [
              Text('Edit locally. Move fast.', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Flutter interface, Rust processing engine, zero uploads.', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
              itemCount: samples.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemBuilder: (context, index) => InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openBytes(context, DefaultAssetBundle.of(context).load('assets/samples/${samples[index]}').then((v) => v.buffer.asUint8List())),
                child: Hero(
                  tag: samples[index],
                  child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/samples/${samples[index]}', fit: BoxFit.cover)),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Import from Gallery'),
        onPressed: () async {
          final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (picked != null && context.mounted) _openBytes(context, picked.readAsBytes());
        },
      ),
    );
  }
}
