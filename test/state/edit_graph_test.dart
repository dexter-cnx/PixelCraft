import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/edit_graph.dart';

void main() {
  test('edit graph round-trips versioned film and mask nodes', () {
    const graph = EditGraphDocument(
      nodes: <EditGraphNode>[
        EditGraphNode(
          id: 'film-1',
          type: EditNodeType.filmProfile,
          opacity: 0.8,
          params: <String, Object?>{
            'profileId': 'provia_inspired',
            'strength': 0.75,
          },
          maskId: 'mask-1',
        ),
      ],
      masks: <EditMask>[
        EditMask(
          id: 'mask-1',
          type: 'brush',
          params: <String, Object?>{'feather': 0.25},
        ),
      ],
    );

    final restored = EditGraphDocument.decode(graph.encode());

    expect(restored.schemaVersion, pixelCraftEditGraphSchemaVersion);
    expect(restored.nodes, hasLength(1));
    expect(restored.nodes.single.type, EditNodeType.filmProfile);
    expect(restored.nodes.single.maskId, 'mask-1');
    expect(restored.nodes.single.params['profileId'], 'provia_inspired');
    expect(restored.masks.single.type, 'brush');
  });

  test('edit graph rejects unsupported schema versions', () {
    expect(
      () => EditGraphDocument.decode(
        '{"schemaVersion":99,"document":{"nodes":[],"masks":[],"overlays":[]}}',
      ),
      throwsFormatException,
    );
  });

  test('edit graph rejects dangling mask references', () {
    expect(
      () => EditGraphDocument.decode(
        '{"schemaVersion":3,"document":{"nodes":[{"id":"n1","type":"adjustment","maskId":"missing"}],"masks":[],"overlays":[]}}',
      ),
      throwsFormatException,
    );
  });

  test('edit graph rejects duplicate stable ids', () {
    expect(
      () => EditGraphDocument.decode(
        '{"schemaVersion":3,"document":{"nodes":[{"id":"n1","type":"adjustment"},{"id":"n1","type":"filmProfile"}],"masks":[],"overlays":[]}}',
      ),
      throwsFormatException,
    );
  });
}
