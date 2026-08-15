import 'package:dxtr_pixs_editing/pixelcraft_editing.dart';

abstract interface class FilmProfileRepository {
  Future<List<FilmProfileV1>> loadAll();

  Future<void> save(FilmProfileV1 profile);

  Future<void> delete(String id);
}
