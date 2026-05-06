// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:squash_social/core/seeder.dart';
import 'package:squash_social/presentation/tablet/tablet_home_screen.dart';
import 'package:squash_social/presentation/controllers/scheduling_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Seeder().seedIfNeeded();
  runApp(const ProviderScope(child: SquashSocialApp()));
}

class SquashSocialApp extends ConsumerWidget {
  const SquashSocialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Boot the scheduling controller — keeps it alive for the session.
    ref.watch(schedulingControllerProvider);

    return MaterialApp(
      title: 'Squash Social',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const TabletHomeScreen(),
    );
  }
}
