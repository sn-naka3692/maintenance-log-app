import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'screens/auth_gate.dart';
import 'services/report_outbox_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ja_JP');

  // 【恒久対策・2026-09導入】Firestoreのローカルキャッシュだけに依存せず、
  // アプリ独自の送信控え(Outbox)をHiveで管理する。起動直後にまず
  // Hiveを初期化し、その後「まだサーバー到達が確認できていない日報」が
  // 残っていないかを必ず確認・再送信する。これにより、前回起動時に
  // 何らかの理由(強制終了・電波断・ストレージ整理等)で送信が完了
  // しなかった日報も、次にアプリが開かれた瞬間に自動で復旧を試みる。
  await Hive.initFlutter();
  await ReportOutboxService.instance.init();
  // 起動をブロックしないよう、再送信はバックグラウンドで実行する。
  unawaited(_flushOutboxOnStartup());

  runApp(const MyApp());
}

Future<void> _flushOutboxOnStartup() async {
  try {
    final count = await ReportOutboxService.instance.flushPending();
    if (kDebugMode && count > 0) {
      debugPrint('起動時Outbox再送信: $count件をサーバーへ再送信しました');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('起動時Outbox再送信でエラー: $e');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Firestoreはログイン済みユーザーのみ読み書き可能なため、
      // ここでは即時initを呼ばず、AuthGateがログイン確認後にinit()を呼び出す。
      create: (_) => AppState(),
      child: MaterialApp(
        title: '札幌中野冷機 日報アプリ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('ja', 'JP'),
        supportedLocales: const [Locale('ja', 'JP'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AuthGate(),
      ),
    );
  }
}
