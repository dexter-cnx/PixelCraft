import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/bridge.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeRustBridge();
  runApp(const ProviderScope(child: PixelCraftApp()));
}

class PixelCraftApp extends StatelessWidget {
  const PixelCraftApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PixelCraft',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF7259E7),
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8F7FC),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF9D8CFF),
      brightness: Brightness.dark,
    ),
    home: const HomeScreen(),
  );
}
