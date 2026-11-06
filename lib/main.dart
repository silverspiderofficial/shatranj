import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const ShatranjApp()));
}

class ShatranjApp extends ConsumerStatefulWidget {
  const ShatranjApp({super.key});

  @override
  ConsumerState<ShatranjApp> createState() => _ShatranjAppState();
}

class _ShatranjAppState extends ConsumerState<ShatranjApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Free the native Stockfish engine when the app is closed.
    _lifecycle = AppLifecycleListener(onDetach: () => ref.read(engineProvider).shutdown());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dpr = WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio;
      ChessgroundImages.instance.loadAll(ref.read(settingsProvider).pieceSet.assets, devicePixelRatio: dpr);
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B5530), brightness: b),
    fontFamily: 'Vazirmatn',
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    ref.listen(settingsProvider.select((s) => s.pieceSet), (prev, next) {
      ChessgroundImages.instance.clear();
      ChessgroundImages.instance.loadAll(next.assets);
    });
    final locale = settings.languageFa ? const Locale('fa', 'IR') : const Locale('en', 'US');
    return MaterialApp(
      title: settings.languageFa ? 'شطرنج آفلاین' : 'Offline Chess',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: settings.themeMode,
      home: const HomeScreen(),
    );
  }
}
