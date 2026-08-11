import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/edit_graph.dart';
import 'package:pixelcraft/gpu/gpu_preview_renderer.dart';

void main() {
  test('fallback backend is explicit about approximation capabilities', () {
    final renderer = FallbackGpuPreviewRenderer();

    expect(renderer.capabilities.backend, GpuPreviewBackendKind.fallback);
    expect(renderer.capabilities.supportsLut33, isFalse);
    expect(renderer.capabilities.supportsMasks, isFalse);
    expect(
      renderer.capabilities.supportsNode(EditNodeType.filmProfile),
      isTrue,
    );
  });

  test('film state is normalized before reaching backend state', () async {
    final renderer = FallbackGpuPreviewRenderer();

    await renderer.setFilm(
      const GpuPreviewFilmState(
        profileId: 'velvia_inspired',
        strength: 2,
      ),
    );

    expect(renderer.film.profileId, 'velvia_inspired');
    expect(renderer.film.strength, 1);
  });

  test('edit graph can be passed to preview renderer without UI coupling',
      () async {
    final renderer = FallbackGpuPreviewRenderer();
    const graph = EditGraphDocument(
      nodes: <EditGraphNode>[
        EditGraphNode(
          id: 'film-1',
          type: EditNodeType.filmProfile,
          params: <String, Object?>{'profileId': 'astia_inspired'},
        ),
      ],
    );

    await renderer.setEditGraph(graph);

    expect(renderer.graph.nodes.single.id, 'film-1');
  });
}
