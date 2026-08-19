import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

/// Firebase Authenticationのログイン状態に応じて
/// ログイン画面またはメイン画面を表示する。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _reloadedForUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final fbUser = snapshot.data;
        if (fbUser == null) {
          _reloadedForUid = null;
          return const LoginScreen();
        }

        final appState = context.watch<AppState>();

        // ログイン済みだが、AppState側のcurrentUserがまだ
        // Firestoreユーザー情報と紐付いていない場合は一度だけ再読込する。
        if (!appState.isLoading &&
            appState.currentUser == null &&
            _reloadedForUid != fbUser.uid) {
          _reloadedForUid = fbUser.uid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appState.init();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.currentUser == null) {
          // Firestoreに対応するユーザー情報が見つからない場合。
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'ユーザー情報が見つかりません。\n管理者にお問い合わせください。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => appState.signOut(),
                      child: const Text('ログアウト'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const MainNavigation();
      },
    );
  }
}
