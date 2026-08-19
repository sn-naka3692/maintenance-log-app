import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

/// Firebase Authenticationのログイン状態に応じて
/// ログイン画面またはメイン画面を表示する。
///
/// 重要: Firestoreのセキュリティルールはログイン済みユーザーのみ
/// アクセス可能なため、AppState.init()(Firestore読み込み)は
/// ログイン確認が取れてから呼び出す(未ログイン時に呼ぶと権限エラーになる)。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _initializedForUid;

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
          _initializedForUid = null;
          return const LoginScreen();
        }

        final appState = context.watch<AppState>();

        // ログインを確認できたので、このユーザーに対してまだデータ読み込みを
        // 行っていない場合は一度だけ init() を呼び出す。
        if (_initializedForUid != fbUser.uid) {
          _initializedForUid = fbUser.uid;
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

        if (appState.error != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(appState.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => appState.init(),
                      child: const Text('再試行'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => appState.signOut(),
                      child: const Text('ログアウト'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (appState.currentUser == null) {
          // ログインには成功したが、Firestoreに対応するユーザー情報が
          // 見つからない場合(例: 社員マスタに未登録)。
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.grey,
                    ),
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
