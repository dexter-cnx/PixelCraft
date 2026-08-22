import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/core/export_file_service.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'pixelcraft-export-test-',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('writes backup first and retries transient Gallery failure once', () async {
    var calls = 0;
    final service = ExportFileService(
      directoryProvider: () async => tempDirectory,
      isMobilePlatform: true,
      gallerySaver: (bytes, fileName) async {
        calls++;
        return GallerySaveResult(
          isSuccess: calls == 2,
          errorMessage: calls == 1 ? 'temporary failure' : null,
        );
      },
    );

    final exported = await service.save(
      Uint8List.fromList([1, 2, 3, 4]),
      format: 'jpeg',
    );

    expect(calls, 2);
    expect(exported.savedToGallery, isTrue);
    expect(exported.gallerySaveAttempts, 2);
    expect(exported.galleryError, isNull);
    expect(await File(exported.path).readAsBytes(), [1, 2, 3, 4]);
  });

  test('keeps app backup when Gallery fails twice', () async {
    var calls = 0;
    final service = ExportFileService(
      directoryProvider: () async => tempDirectory,
      isMobilePlatform: true,
      gallerySaver: (bytes, fileName) async {
        calls++;
        return const GallerySaveResult(
          isSuccess: false,
          errorMessage: 'permission denied',
        );
      },
    );

    final exported = await service.save(
      Uint8List.fromList([8, 9, 10]),
      format: 'png',
    );

    expect(calls, 2);
    expect(exported.savedToGallery, isFalse);
    expect(exported.gallerySaveAttempts, 2);
    expect(exported.galleryError, 'permission denied');
    expect(await File(exported.path).exists(), isTrue);
    expect(await File(exported.path).readAsBytes(), [8, 9, 10]);
  });

  test('explicit retry uses backup without re-rendering source', () async {
    var calls = 0;
    final service = ExportFileService(
      directoryProvider: () async => tempDirectory,
      isMobilePlatform: true,
      gallerySaver: (bytes, fileName) async {
        calls++;
        return GallerySaveResult(
          isSuccess: calls >= 3,
          errorMessage: calls < 3 ? 'gallery unavailable' : null,
        );
      },
    );

    final first = await service.save(
      Uint8List.fromList([21, 22, 23]),
      format: 'webp',
    );
    expect(first.savedToGallery, isFalse);
    expect(first.gallerySaveAttempts, 2);

    final retried = await service.retryGallerySave(first);

    expect(retried.savedToGallery, isTrue);
    expect(retried.gallerySaveAttempts, 3);
    expect(retried.path, first.path);
    expect(await File(retried.path).readAsBytes(), [21, 22, 23]);
  });

  test('desktop export writes backup without attempting Gallery', () async {
    var calls = 0;
    final service = ExportFileService(
      directoryProvider: () async => tempDirectory,
      isMobilePlatform: false,
      gallerySaver: (bytes, fileName) async {
        calls++;
        return const GallerySaveResult(isSuccess: true);
      },
    );

    final exported = await service.save(
      Uint8List.fromList([31, 32]),
      format: 'jpg',
    );

    expect(calls, 0);
    expect(exported.format, 'jpeg');
    expect(exported.savedToGallery, isFalse);
    expect(exported.gallerySaveAttempts, 0);
    expect(await File(exported.path).exists(), isTrue);
  });
}
