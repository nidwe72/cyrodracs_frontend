import 'package:flutter/material.dart';
import 'package:flutter_bootstrap5/flutter_bootstrap5.dart';
import 'home_page.dart';

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
              tabBarTheme: TabBarTheme(
                labelColor: bs.colors.primary,
                unselectedLabelColor: bs.colors.secondary,
                indicatorColor: bs.colors.primary,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: bs.colors.primary,
                  foregroundColor: bs.colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: bs.colors.secondary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: bs.colors.black50, width: 2),
                ),
                floatingLabelStyle: const TextStyle(color: Colors.black),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
