import 'package:flutter/foundation.dart';

import 'platform_flow_foundation.dart';

const externalEditContractVersion = 1;

enum ExternalEditResultStatus { completed, cancelled, failed }

@immutable
class ExternalEditRequestV1 {
  const ExternalEditRequestV1({
    required this.requestId,
    required this.catalogAssetId,
    required this.source,
    this.preferredOutputMimeType,
  }) : assert(requestId != ''),
       assert(catalogAssetId != '');

  static const schemaVersion = externalEditContractVersion;

  final String requestId;

  /// Stable asset identity owned by the calling catalog (for example Nixin).
  /// PixelCraft correlates against this value but must not replace or reinterpret
  /// the caller's catalog identity.
  final String catalogAssetId;

  /// Read-only source supplied by the caller.
  ///
  /// External edit requests must use [MediaSourceProvenance.externalEdit].
  final MediaSourceDescriptor source;

  /// Optional transport-level output preference. This does not enable formats
  /// that PixelCraft cannot currently render/export.
  final String? preferredOutputMimeType;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'requestId': requestId,
    'catalogAssetId': catalogAssetId,
    'source': _mediaSourceToJson(source),
    if (preferredOutputMimeType != null)
      'preferredOutputMimeType': preferredOutputMimeType,
  };

  factory ExternalEditRequestV1.fromJson(Map<String, Object?> json) {
    _requireVersion(json);
    final requestId = _requireNonEmptyString(json, 'requestId');
    final catalogAssetId = _requireNonEmptyString(json, 'catalogAssetId');
    final source = _mediaSourceFromJson(_requireMap(json, 'source'));
    if (source.provenance != MediaSourceProvenance.externalEdit) {
      throw const FormatException(
        'External edit request source must use externalEdit provenance.',
      );
    }

    return ExternalEditRequestV1(
      requestId: requestId,
      catalogAssetId: catalogAssetId,
      source: source,
      preferredOutputMimeType: _optionalString(
        json,
        'preferredOutputMimeType',
      ),
    );
  }
}

@immutable
class ExternalEditOutputV1 {
  const ExternalEditOutputV1({
    required this.uri,
    required this.mimeType,
    this.suggestedFileName,
    this.authoritativeRecipeJson,
  }) : assert(mimeType != '');

  final Uri uri;
  final String mimeType;
  final String? suggestedFileName;

  /// Optional PixelCraft/Rust-authored recipe payload for future re-edit.
  /// Callers may persist this value opaquely but must not become edit authority
  /// by interpreting or mutating its internal schema.
  final String? authoritativeRecipeJson;

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri.toString(),
    'mimeType': mimeType,
    if (suggestedFileName != null) 'suggestedFileName': suggestedFileName,
    if (authoritativeRecipeJson != null)
      'authoritativeRecipeJson': authoritativeRecipeJson,
  };

  factory ExternalEditOutputV1.fromJson(Map<String, Object?> json) {
    final rawUri = _requireNonEmptyString(json, 'uri');
    final uri = Uri.tryParse(rawUri);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('External edit output URI is invalid.');
    }

    return ExternalEditOutputV1(
      uri: uri,
      mimeType: _requireNonEmptyString(json, 'mimeType'),
      suggestedFileName: _optionalString(json, 'suggestedFileName'),
      authoritativeRecipeJson: _optionalString(
        json,
        'authoritativeRecipeJson',
      ),
    );
  }
}

@immutable
class ExternalEditResultV1 {
  const ExternalEditResultV1._({
    required this.requestId,
    required this.catalogAssetId,
    required this.status,
    this.output,
    this.failureCode,
    this.failureMessage,
  });

  const ExternalEditResultV1.completed({
    required String requestId,
    required String catalogAssetId,
    required ExternalEditOutputV1 output,
  }) : this._(
         requestId: requestId,
         catalogAssetId: catalogAssetId,
         status: ExternalEditResultStatus.completed,
         output: output,
       );

  const ExternalEditResultV1.cancelled({
    required String requestId,
    required String catalogAssetId,
  }) : this._(
         requestId: requestId,
         catalogAssetId: catalogAssetId,
         status: ExternalEditResultStatus.cancelled,
       );

  const ExternalEditResultV1.failed({
    required String requestId,
    required String catalogAssetId,
    required String failureCode,
    String? failureMessage,
  }) : this._(
         requestId: requestId,
         catalogAssetId: catalogAssetId,
         status: ExternalEditResultStatus.failed,
         failureCode: failureCode,
         failureMessage: failureMessage,
       );

  static const schemaVersion = externalEditContractVersion;

  final String requestId;
  final String catalogAssetId;
  final ExternalEditResultStatus status;
  final ExternalEditOutputV1? output;
  final String? failureCode;
  final String? failureMessage;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'requestId': requestId,
    'catalogAssetId': catalogAssetId,
    'status': status.name,
    if (output != null) 'output': output!.toJson(),
    if (failureCode != null) 'failureCode': failureCode,
    if (failureMessage != null) 'failureMessage': failureMessage,
  };

  factory ExternalEditResultV1.fromJson(Map<String, Object?> json) {
    _requireVersion(json);
    final requestId = _requireNonEmptyString(json, 'requestId');
    final catalogAssetId = _requireNonEmptyString(json, 'catalogAssetId');
    final statusName = _requireNonEmptyString(json, 'status');
    final status = ExternalEditResultStatus.values
        .where((candidate) => candidate.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw FormatException('Unsupported external edit status: $statusName');
    }

    return switch (status) {
      ExternalEditResultStatus.completed => ExternalEditResultV1.completed(
        requestId: requestId,
        catalogAssetId: catalogAssetId,
        output: ExternalEditOutputV1.fromJson(_requireMap(json, 'output')),
      ),
      ExternalEditResultStatus.cancelled => ExternalEditResultV1.cancelled(
        requestId: requestId,
        catalogAssetId: catalogAssetId,
      ),
      ExternalEditResultStatus.failed => ExternalEditResultV1.failed(
        requestId: requestId,
        catalogAssetId: catalogAssetId,
        failureCode: _requireNonEmptyString(json, 'failureCode'),
        failureMessage: _optionalString(json, 'failureMessage'),
      ),
    };
  }
}

Map<String, Object?> _mediaSourceToJson(MediaSourceDescriptor source) =>
    <String, Object?>{
      'uri': source.uri.toString(),
      'provenance': source.provenance.name,
      if (source.mimeType != null) 'mimeType': source.mimeType,
      if (source.externalId != null) 'externalId': source.externalId,
    };

MediaSourceDescriptor _mediaSourceFromJson(Map<String, Object?> json) {
  final rawUri = _requireNonEmptyString(json, 'uri');
  final uri = Uri.tryParse(rawUri);
  if (uri == null || !uri.hasScheme) {
    throw const FormatException('External edit source URI is invalid.');
  }

  final provenanceName = _requireNonEmptyString(json, 'provenance');
  final provenance = MediaSourceProvenance.values
      .where((candidate) => candidate.name == provenanceName)
      .firstOrNull;
  if (provenance == null) {
    throw FormatException('Unsupported source provenance: $provenanceName');
  }

  return MediaSourceDescriptor(
    uri: uri,
    provenance: provenance,
    mimeType: _optionalString(json, 'mimeType'),
    externalId: _optionalString(json, 'externalId'),
  );
}

void _requireVersion(Map<String, Object?> json) {
  final version = json['schemaVersion'];
  if (version != externalEditContractVersion) {
    throw FormatException(
      'Unsupported external edit contract version: $version',
    );
  }
}

Map<String, Object?> _requireMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Expected object for $key.');
  }
  return value.cast<String, Object?>();
}

String _requireNonEmptyString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-empty string for $key.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected string for $key.');
  }
  return value;
}
