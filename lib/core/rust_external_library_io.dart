import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

ExternalLibrary? rustExternalLibraryForCurrentPlatform() {
  if (!Platform.isIOS) return null;

  return ExternalLibrary.process(
    iKnowHowToUseIt: true,
    debugInfo: 'pixelcraft_engine statically linked into the iOS Runner',
  );
}
