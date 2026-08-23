import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/external_edit_contract.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';

void main() {
  group('ExternalEditRequestV1', () {
    test('round trips caller catalog identity and external source metadata', () {
      final request = ExternalEditRequestV1(
        requestId: 'request-1',
        catalogAssetId: 'nixin-asset-42',
        source: MediaSourceDescriptor(
          uri: Uri.parse('file:///photos/source.heic'),
          provenance: MediaSourceProvenance.externalEdit,
          mimeType: 'image/heic',
          externalId: 'provider-item-7',
        ),
        preferredOutputMimeType: 'image/jpeg',
      );

      final decoded = ExternalEditRequestV1.fromJson(request.toJson());

      expect(decoded.requestId, 'request-1');
      expect(decoded.catalogAssetId, 'nixin-asset-42');
      expect(decoded.source.uri, Uri.parse('file:///photos/source.heic'));
      expect(decoded.source.provenance, MediaSourceProvenance.externalEdit);
      expect(decoded.source.mimeType, 'image/heic');
      expect(decoded.source.externalId, 'provider-item-7');
      expect(decoded.preferredOutputMimeType, 'image/jpeg');
    });

    test('rejects unsupported contract versions', () {
      expect(
        () => ExternalEditRequestV1.fromJson(<String, Object?>{
          'schemaVersion': 2,
          'requestId': 'request-1',
          'catalogAssetId': 'asset-1',
          'source': <String, Object?>{
            'uri': 'file:///photos/source.jpg',
            'provenance': 'externalEdit',
          },
        }),
        throwsFormatException,
      );
    });

    test('rejects sources that are not explicitly external edit provenance', () {
      expect(
        () => ExternalEditRequestV1.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'request-1',
          'catalogAssetId': 'asset-1',
          'source': <String, Object?>{
            'uri': 'file:///photos/source.jpg',
            'provenance': 'gallery',
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('ExternalEditResultV1', () {
    test('completed result round trips output and authoritative recipe', () {
      final result = ExternalEditResultV1.completed(
        requestId: 'request-1',
        catalogAssetId: 'nixin-asset-42',
        output: ExternalEditOutputV1(
          uri: Uri.parse('file:///exports/edited.jpg'),
          mimeType: 'image/jpeg',
          suggestedFileName: 'edited.jpg',
          authoritativeRecipeJson: '{"version":1}',
        ),
      );

      final decoded = ExternalEditResultV1.fromJson(result.toJson());

      expect(decoded.status, ExternalEditResultStatus.completed);
      expect(decoded.requestId, 'request-1');
      expect(decoded.catalogAssetId, 'nixin-asset-42');
      expect(decoded.output?.uri, Uri.parse('file:///exports/edited.jpg'));
      expect(decoded.output?.mimeType, 'image/jpeg');
      expect(decoded.output?.suggestedFileName, 'edited.jpg');
      expect(decoded.output?.authoritativeRecipeJson, '{"version":1}');
      expect(decoded.failureCode, isNull);
    });

    test('failed result requires a stable failure code', () {
      expect(
        () => ExternalEditResultV1.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'request-1',
          'catalogAssetId': 'asset-1',
          'status': 'failed',
        }),
        throwsFormatException,
      );
    });

    test('cancelled result carries correlation without inventing output', () {
      final result = ExternalEditResultV1.cancelled(
        requestId: 'request-1',
        catalogAssetId: 'nixin-asset-42',
      );

      final decoded = ExternalEditResultV1.fromJson(result.toJson());

      expect(decoded.status, ExternalEditResultStatus.cancelled);
      expect(decoded.output, isNull);
      expect(decoded.failureCode, isNull);
    });

    test('completed result requires an explicit output object', () {
      expect(
        () => ExternalEditResultV1.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'requestId': 'request-1',
          'catalogAssetId': 'asset-1',
          'status': 'completed',
        }),
        throwsFormatException,
      );
    });
  });
}
