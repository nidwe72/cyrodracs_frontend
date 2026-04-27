import 'package:flutter/material.dart';
import 'package:flutter_bootstrap5/flutter_bootstrap5.dart';
import 'home_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FlutterBootstrap5(
      builder: (ctx) {
        final bs = BootstrapTheme.of(ctx);
        return MaterialApp(
          title: 'Cyrodracs',
          theme: bs.toTheme(
            theme: ThemeData(
              appBarTheme: AppBarTheme(
                backgroundColor: bs.colors.dark,
                foregroundColor: bs.colors.white,
                elevation: 0,
              ),
              tabBarTheme: TabBarThemeData(
                labelColor: bs.colors.primary,
                unselectedLabelColor: bs.colors.secondary,
                indicatorColor: bs.colors.primary,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: bs.colors.primary,
                  foregroundColor: bs.colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: bs.colors.secondary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: bs.colors.black50, width: 2),
                ),
                floatingLabelStyle: const TextStyle(color: Colors.black),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              cardTheme: CardThemeData(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                elevation: 0,
                margin: EdgeInsets.zero,
              ),
              dialogTheme: const DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              dataTableTheme: DataTableThemeData(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                headingTextStyle: AppTheme.tableHeaderStyle,
                dataTextStyle: const TextStyle(fontSize: 13),
                columnSpacing: AppTheme.spacingLg,
                horizontalMargin: AppTheme.spacingMd,
              ),
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
