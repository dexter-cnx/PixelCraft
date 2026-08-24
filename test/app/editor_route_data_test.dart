import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/app_routes.dart';
import 'package:pixelcraft/app/editor_source_contract.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';

void main() {
  test('typed Gallery source survives route handoff', () {
    final descriptor = MediaSourceDescriptor(
      uri: Uri.file('/tmp/gallery.png'),
      provenance: MediaSourceProvenance.gallery,
      mimeType: 'image/png',
      externalId: 'gallery-7',
    );
    final source = EditorSourceFactory().fromDescriptor(descriptor);

    final route = EditorRouteData(source: source);

    expect(route.isValid, isTrue);
    expect(route.source, same(source));
    expect(route.source!.original, same(descriptor));
    expect(route.imagePath, '/tmp/gallery.png');
    expect(route.imageBytes, isNull);
    expect(route.hasInitialFilm, isFalse);
  });

  test('non-file typed source remains preserved without inventing a path', () {
    final source = EditorSourceFactory().fromDescriptor(
      MediaSourceDescriptor(
        uri: Uri.parse('content://gallery/item/42'),
        provenance: MediaSourceProvenance.gallery,
        mimeType: 'image/jpeg',
        externalId: '42',
      ),
    );

    final route = EditorRouteData(source: source);

    expect(route.isValid, isTrue);
    expect(route.source, same(source));
    expect(route.imagePath, isNull);
    expect(route.source!.externalId, '42');
  });

  test('legacy camera path remains compatible with initial Film handoff', () {
    const route = EditorRouteData(
      imagePath: '/tmp/capture.jpg',
      initialFilmProfileId: 'film-01',
      initialFilmStrength: 0.75,
    );

    expect(route.isValid, isTrue);
    expect(route.imagePath, '/tmp/capture.jpg');
    expect(route.source, isNull);
    expect(route.hasInitialFilm, isTrue);
  });

  test(
    'route validation rejects missing editor source in release-safe path',
    () {
      const route = EditorRouteData();

      expect(route.isValid, isFalse);
    },
  );

  test('route validation rejects multiple editor sources', () {
    const route = EditorRouteData(
      imagePath: '/tmp/capture.jpg',
      imageBytes: <int>[1, 2, 3],
    );

    expect(route.isValid, isFalse);
  });

  test('initial Film handoff requires legacy file-backed source', () {
    final source = EditorSourceFactory().fromDescriptor(
      MediaSourceDescriptor(
        uri: Uri.file('/tmp/gallery.jpg'),
        provenance: MediaSourceProvenance.gallery,
        mimeType: 'image/jpeg',
      ),
    );
    final route = EditorRouteData(
      source: source,
      initialFilmProfileId: 'film-01',
    );

    expect(route.isValid, isFalse);
  });
}
