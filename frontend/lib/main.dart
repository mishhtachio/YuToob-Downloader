import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(MyApp());
}

class AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const card = Color(0xFF1C1C1E);
  static const accent = Color(0xFFFF1A1A);
  static const text = Colors.white;
  static const muted = Colors.grey;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        fontFamily: 'Mono',
        colorScheme: ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.card,
          surface: AppColors.card,
        ),
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: AppColors.text),
          bodySmall: TextStyle(color: AppColors.muted),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.card,
          hintStyle: TextStyle(color: AppColors.muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: MainScreen(),
    );
  }
}