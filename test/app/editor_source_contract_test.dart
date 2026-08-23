import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/editor_source_contract.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';

void main() {
  const factory = EditorSourceFactory();

  group('EditorSourceFactory', () {
    test('prefers MIME type and preserves original source identity', () {
      final descriptor = MediaSourceDescriptor(
        uri: Uri.parse('content://gallery/item/42'),
        provenance: MediaSourceProvenance.gallery,
        mimeType: 'image/jpeg',
        externalId: '42',
      );

      final source = factory.fromDescriptor(descriptor);

      expect(source.original, same(descriptor));
      expect(source.uri, descriptor.uri);
      expect(source.externalId, '42');
      expect(source.format, EditorSourceFormat.jpeg);
      expect(source.inheritsCameraLook, isFalse);
    });

    test('falls back to extension when MIME type is absent', () {
      final source = factory.fromDescriptor(
        MediaSourceDescriptor(
          uri: Uri.file('/tmp/photo.PNG'),
          provenance: MediaSourceProvenance.desktopOpen,
        ),
      );

      expect(source.format, EditorSourceFormat.png);
    });

    test('keeps future RAW identity without activating RAW development', () {
      final source = factory.fromDescriptor(
        MediaSourceDescriptor(
          uri: Uri.file('/tmp/source.NEF'),
          provenance: MediaSourceProvenance.externalEdit,
        ),
      );

      expect(source.format, EditorSourceFormat.raw);
      expect(source.provenance, MediaSourceProvenance.externalEdit);
      expect(source.inheritsCameraLook, isFalse);
    });

    test('unknown formats remain representable', () {
      final source = factory.fromDescriptor(
        MediaSourceDescriptor(
          uri: Uri.file('/tmp/source.custom'),
          provenance: MediaSourceProvenance.gallery,
        ),
      );

      expect(source.format, EditorSourceFormat.unknown);
    });
  });

  group('GalleryEditorSourceCoordinator', () {
    test('returns null when the picker is cancelled', () async {
      const coordinator = GalleryEditorSourceCoordinator(
        picker: _FakePicker(null),
      );

      expect(await coordinator.pickSource(), isNull);
    });

    test('maps the picked descriptor without changing provenance', () async {
      final descriptor = MediaSourceDescriptor(
        uri: Uri.file('/tmp/gallery.jpg'),
        provenance: MediaSourceProvenance.gallery,
        mimeType: 'image/jpeg',
      );
      final coordinator = GalleryEditorSourceCoordinator(
        picker: _FakePicker(descriptor),
      );

      final source = await coordinator.pickSource();

      expect(source, isNotNull);
      expect(source!.original, same(descriptor));
      expect(source.provenance, MediaSourceProvenance.gallery);
      expect(source.inheritsCameraLook, isFalse);
    });
  });

  group('LegacyGalleryEditorRoutingPicker', () {
    test(
      'consumes Gallery descriptor after opening typed editor source',
      () async {
        final descriptor = MediaSourceDescriptor(
          uri: Uri.file('/tmp/gallery.jpg'),
          provenance: MediaSourceProvenance.gallery,
          mimeType: 'image/jpeg',
          externalId: 'gallery-1',
        );
        EditorSource? openedSource;
        final picker = LegacyGalleryEditorRoutingPicker(
          picker: _FakePicker(descriptor),
          onOpenEditor: (source) async => openedSource = source,
        );

        final legacyResult = await picker.pickImage();

        expect(legacyResult, isNull);
        expect(openedSource, isNotNull);
        expect(openedSource!.original, same(descriptor));
        expect(openedSource!.externalId, 'gallery-1');
        expect(openedSource!.inheritsCameraLook, isFalse);
      },
    );

    test('passes non-Gallery provenance back to legacy validation', () async {
      final descriptor = MediaSourceDescriptor(
        uri: Uri.file('/tmp/drop.jpg'),
        provenance: MediaSourceProvenance.desktopDrop,
        mimeType: 'image/jpeg',
      );
      var opened = false;
      final picker = LegacyGalleryEditorRoutingPicker(
        picker: _FakePicker(descriptor),
        onOpenEditor: (_) async => opened = true,
      );

      final legacyResult = await picker.pickImage();

      expect(legacyResult, same(descriptor));
      expect(opened, isFalse);
    });
  });
}

class _FakePicker implements MediaPickerService {
  const _FakePicker(this.result);

  final MediaSourceDescriptor? result;

  @override
  Future<MediaSourceDescriptor?> pickImage() async => result;
}
