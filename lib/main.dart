import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://zwhyrnhhazjsciyyeijc.supabase.co',
    publishableKey: 'sb_publishable_ud5v1EnN4a-7FSSRrgHefg_A1EwCyrr',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JomRide',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthRedirectHandler(),
    );
  }
}

class AuthRedirectHandler extends StatefulWidget {
  const AuthRedirectHandler({super.key});

  @override
  State<AuthRedirectHandler> createState() => _AuthRedirectHandlerState();
}

class _AuthRedirectHandlerState extends State<AuthRedirectHandler> {
  final _supabase = Supabase.instance.client;
  bool _initialized = false;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _checkSession();
    // Listen to session changes
    _supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _session = data.session;
        });
      }
    });
  }

  Future<void> _checkSession() async {
    final session = _supabase.auth.currentSession;
    setState(() {
      _session = session;
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (_session != null) {
      return const HomeScreen();
    } else {
      return const AuthScreen();
    }
  }
}
