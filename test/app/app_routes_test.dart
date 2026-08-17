import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/app/app_routes.dart';
import 'package:pixelcraft/app/platform_flow_foundation.dart';

void main() {
  group('AppRoutePaths', () {
    test('maps platform intents to workspace routes', () {
      expect(
        AppRoutePaths.initialLocationForIntent(AppRouteIntent.camera),
        AppRoutePaths.camera,
      );
      expect(
        AppRoutePaths.initialLocationForIntent(AppRouteIntent.desktopHome),
        AppRoutePaths.desktop,
      );
      expect(
        AppRoutePaths.initialLocationForIntent(AppRouteIntent.editor),
        AppRoutePaths.editor,
      );
    });
  });

  group('EditorRouteData', () {
    test('supports a file-backed camera Film handoff', () {
      const route = EditorRouteData(
        imagePath: '/tmp/capture.jpg',
        initialFilmProfileId: 'provia',
        initialFilmStrength: 0.75,
      );

      expect(route.hasInitialFilm, isTrue);
      expect(route.initialFilmStrength, 0.75);
    });

    test('supports an in-memory recovery source without Film handoff', () {
      const route = EditorRouteData(
        imageBytes: <int>[1, 2, 3],
        recoveryRecipe: '{}',
      );

      expect(route.hasInitialFilm, isFalse);
      expect(route.imagePath, isNull);
    });
  });
}
