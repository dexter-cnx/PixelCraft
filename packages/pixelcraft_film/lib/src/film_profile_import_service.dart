import 'dart:convert';

import 'package:pixelcraft_editing/pixelcraft_editing.dart';

enum FilmProfileImportSourceKind { pixelcraftProfile, genericRecipe }

class FilmProfileImportResult {
  const FilmProfileImportResult({
    required this.profile,
    required this.sourceKind,
    this.report,
  });

  final FilmProfileV1 profile;
  final FilmProfileImportSourceKind sourceKind;
  final FilmProfileImportReport? report;
}

class FilmProfileImportService {
  const FilmProfileImportService();

  FilmProfileImportResult parse(
    String source, {
    required String importedId,
    String? importedName,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Import must be a JSON object.');
    }

    if (decoded['schema'] == pixelCraftProfileSchema) {
      return FilmProfileImportResult(
        profile: FilmProfileV1.decode(source).copyWith(
          origin: FilmProfileOrigin.imported,
        ),
        sourceKind: FilmProfileImportSourceKind.pixelcraftProfile,
      );
    }

    final report = importRecipeMap(
      decoded.cast<String, Object?>(),
      id: importedId,
      name: importedName,
    );
    return FilmProfileImportResult(
      profile: report.profile,
      sourceKind: FilmProfileImportSourceKind.genericRecipe,
      report: report,
    );
  }
}
