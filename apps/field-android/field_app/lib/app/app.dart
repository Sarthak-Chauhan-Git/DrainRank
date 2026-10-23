part of '../main.dart';

class MunicipalCrewApp extends StatelessWidget {
  const MunicipalCrewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swachh Pravah Sarthi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0F766E),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFF0FDFA),
          onPrimaryContainer: Color(0xFF0F172A),
          secondary: Color(0xFF124170),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFDCEBFA),
          onSecondaryContainer: Color(0xFF1E3A5F),
          tertiary: Color(0xFF67C090),
          onTertiary: Color(0xFF0F172A),
          tertiaryContainer: Color(0xFFEAF8EF),
          onTertiaryContainer: Color(0xFF047857),
          error: Color(0xFFB91C1C),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFEE2E2),
          onErrorContainer: Color(0xFF9F1239),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          onSurfaceVariant: Color(0xFF475569),
          outline: Color(0xFFB9DED3),
          outlineVariant: Color(0xFFD7E5E7),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF0F172A),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF124170),
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: Color(0xFF0F766E)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          indicatorColor: Color(0xFFE8F8F1),
          iconTheme: WidgetStatePropertyAll(
            IconThemeData(color: Color(0xFF0F766E)),
          ),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600),
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFF3FAF6),
          surfaceTintColor: Colors.transparent,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF0F766E),
          textColor: Color(0xFF334155),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0F766E),
            side: const BorderSide(color: Color(0xFFB9DED3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 1.6),
          ),
          labelStyle: const TextStyle(color: Color(0xFF1E3A5F)),
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0FDFA),
          selectedColor: const Color(0xFFE8F8F1),
          side: const BorderSide(color: Color(0xFFB9DED3)),
          labelStyle: const TextStyle(color: Color(0xFF1E3A5F)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        dividerColor: const Color(0xFFE7EEF0),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: Color(0xFF124170),
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF124170),
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF1E3A5F),
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: Color(0xFF334155)),
          bodyMedium: TextStyle(color: Color(0xFF334155)),
          bodySmall: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
