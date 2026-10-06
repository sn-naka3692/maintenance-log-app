// 【回帰テスト・2026-10-06追加】
//
// 背景: 2026-10-01に発生した実際の事故
// 「Web版の更新お知らせバナーをクリックしても表示が変わらない」
// の原因は、Firestore側の`latest_build_number`は正しく更新したのに、
// クライアント側の自己申告ビルド番号(build_info.dart)の更新を
// 忘れたままデプロイしてしまったことだった(比較ロジック自体は
// 正しかったが、入力値の片方が古いままだったため誤判定になった)。
//
// このテストは、evaluateUpdateAvailability / shouldBlockForOutdatedBuild
// という「サーバー値とクライアント値を比較する」判定ロジックそのものに
// 不具合が入っていないかを検証する。これらの関数はFirestore通信や
// プラットフォーム判定を含まない純粋関数のため、Firebase初期化不要で
// 高速に実行できる。
//
// 【このテストが検知できるもの】
// - 比較演算子の方向を誤って逆にしてしまった(> と >= の混同等)
// - latest_build_number が0/未設定の場合の安全側動作(fail-open)が崩れた
// - 境界値(ちょうど同じビルド番号)の扱いが変わった
//
// 【このテストが検知できないもの(別の対策が必要)】
// - build_info.dart の値そのものを更新し忘れるミス
//   → これは scripts/deploy_web_and_apk.sh 側の整合性チェック
//     (pubspec.yaml と build_info.dart の一致確認)でカバーしている。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/app_config_service.dart';

void main() {
  group('evaluateUpdateAvailability(更新お知らせバナーの判定)', () {
    test('設定が存在しない(null)場合は通知しない', () {
      final result = evaluateUpdateAvailability(
        currentBuild: 56,
        config: null,
      );
      expect(result.hasNewerVersion, false);
    });

    test('latest_build_numberが未設定(0)の場合は通知しない(fail-open)', () {
      final result = evaluateUpdateAvailability(
        currentBuild: 56,
        config: const AppMinVersionConfig(
          minSupportedBuild: 0,
          latestBuildNumber: 0,
          latestVersion: '',
        ),
      );
      expect(result.hasNewerVersion, false);
    });

    test('現在のビルドがサーバーの最新より古い場合は通知する', () {
      final result = evaluateUpdateAvailability(
        currentBuild: 56,
        config: const AppMinVersionConfig(
          minSupportedBuild: 0,
          latestBuildNumber: 57,
          latestVersion: '1.2.48',
        ),
      );
      expect(result.hasNewerVersion, true);
      expect(result.latestVersion, '1.2.48');
    });

    test('現在のビルドとサーバーの最新が同じ場合は通知しない(境界値)', () {
      final result = evaluateUpdateAvailability(
        currentBuild: 57,
        config: const AppMinVersionConfig(
          minSupportedBuild: 0,
          latestBuildNumber: 57,
          latestVersion: '1.2.48',
        ),
      );
      expect(result.hasNewerVersion, false);
    });

    test('現在のビルドがサーバーの最新より新しい場合は通知しない', () {
      final result = evaluateUpdateAvailability(
        currentBuild: 58,
        config: const AppMinVersionConfig(
          minSupportedBuild: 0,
          latestBuildNumber: 57,
          latestVersion: '1.2.48',
        ),
      );
      expect(result.hasNewerVersion, false);
    });

    test(
      '2026-10-01の実際の事故を再現するケース: '
      'サーバー側は更新済み(57)だが、クライアント側の自己申告値を'
      '更新し忘れて古い値(56)のままデプロイした場合、バナーが'
      '正しく表示され続けること(=更新が必要だと正しく分かる)',
      () {
        final result = evaluateUpdateAvailability(
          currentBuild: 56, // build_info.dart更新忘れを想定
          config: const AppMinVersionConfig(
            minSupportedBuild: 0,
            latestBuildNumber: 57, // Firestoreは正しく更新済み
            latestVersion: '1.2.48',
          ),
        );
        expect(
          result.hasNewerVersion,
          true,
          reason: 'クライアント値の更新忘れがあっても、判定ロジック自体は'
              '正しく「更新が必要」と判定できなければならない',
        );
      },
    );
  });

  group('shouldBlockForOutdatedBuild(強制アップデートゲートの判定)', () {
    test('設定が存在しない(null)場合はブロックしない', () {
      expect(
        shouldBlockForOutdatedBuild(currentBuild: 1, config: null),
        false,
      );
    });

    test('min_supported_buildが未設定(0)の場合はブロックしない(fail-open)', () {
      final config = const AppMinVersionConfig(minSupportedBuild: 0);
      expect(
        shouldBlockForOutdatedBuild(currentBuild: 1, config: config),
        false,
      );
    });

    test('現在のビルドが最低利用可能ビルドより古い場合はブロックする', () {
      final config = const AppMinVersionConfig(minSupportedBuild: 10);
      expect(
        shouldBlockForOutdatedBuild(currentBuild: 9, config: config),
        true,
      );
    });

    test('現在のビルドが最低利用可能ビルドと同じ場合はブロックしない(境界値)', () {
      final config = const AppMinVersionConfig(minSupportedBuild: 10);
      expect(
        shouldBlockForOutdatedBuild(currentBuild: 10, config: config),
        false,
      );
    });

    test('現在のビルドが最低利用可能ビルドより新しい場合はブロックしない', () {
      final config = const AppMinVersionConfig(minSupportedBuild: 10);
      expect(
        shouldBlockForOutdatedBuild(currentBuild: 11, config: config),
        false,
      );
    });
  });

  group('AppMinVersionConfig.fromMap(Firestoreからの読み込み)', () {
    test('全フィールドが揃っている場合、正しく復元される', () {
      final config = AppMinVersionConfig.fromMap({
        'min_supported_build': 10,
        'message': 'お知らせ',
        'download_url': 'https://example.com/app.apk',
        'latest_version': '1.2.48',
        'latest_build_number': 57,
      });
      expect(config.minSupportedBuild, 10);
      expect(config.message, 'お知らせ');
      expect(config.downloadUrl, 'https://example.com/app.apk');
      expect(config.latestVersion, '1.2.48');
      expect(config.latestBuildNumber, 57);
    });

    test(
      'latest_build_numberが欠落している場合、0として安全側に倒れる'
      '(fail-open、通知が暴発しない)',
      () {
        final config = AppMinVersionConfig.fromMap({
          'min_supported_build': 10,
        });
        expect(config.latestBuildNumber, 0);
        expect(
          evaluateUpdateAvailability(currentBuild: 1, config: config)
              .hasNewerVersion,
          false,
        );
      },
    );

    test('数値フィールドがnum型(int/double混在)でも正しく変換される', () {
      final config = AppMinVersionConfig.fromMap({
        'min_supported_build': 10.0, // Firestoreがdoubleで返すケースを想定
        'latest_build_number': 57.0,
      });
      expect(config.minSupportedBuild, 10);
      expect(config.latestBuildNumber, 57);
    });
  });

  betaAvailabilityTests();
}

/// 【ベータ版配布・2026-10-06追加】evaluateBetaAvailability の単体テスト。
/// ベータテスター以外には絶対に通知が見えないことを重点的に検証する。
void betaAvailabilityTests() {
  group('evaluateBetaAvailability(ベータ版お知らせバナーの判定)', () {
    test('設定が存在しない(null)場合は通知しない', () {
      final result = evaluateBetaAvailability(
        currentBuild: 10,
        currentUid: 'user1',
        config: null,
      );
      expect(result.hasBetaUpdate, false);
    });

    test('beta_enabledがfalseの場合は通知しない(他の値が揃っていても)', () {
      const config = AppMinVersionConfig(
        minSupportedBuild: 0,
        betaEnabled: false,
        betaBuildNumber: 99,
        betaTesterUids: ['user1'],
      );
      final result = evaluateBetaAvailability(
        currentBuild: 10,
        currentUid: 'user1',
        config: config,
      );
      expect(result.hasBetaUpdate, false);
    });

    test('ベータテスターに指定されていないユーザーには通知しない', () {
      const config = AppMinVersionConfig(
        minSupportedBuild: 0,
        betaEnabled: true,
        betaBuildNumber: 99,
        betaTesterUids: ['user1'],
      );
      final result = evaluateBetaAvailability(
        currentBuild: 10,
        currentUid: 'user2',
        config: config,
      );
      expect(result.hasBetaUpdate, false);
    });

    test('currentUidがnull(未ログイン扱い)の場合は通知しない', () {
      const config = AppMinVersionConfig(
        minSupportedBuild: 0,
        betaEnabled: true,
        betaBuildNumber: 99,
        betaTesterUids: ['user1'],
      );
      final result = evaluateBetaAvailability(
        currentBuild: 10,
        currentUid: null,
        config: config,
      );
      expect(result.hasBetaUpdate, false);
    });

    test('ベータテスターかつ実機ビルドがベータビルド未満の場合は通知する', () {
      const config = AppMinVersionConfig(
        minSupportedBuild: 0,
        betaEnabled: true,
        betaVersion: '1.2.49-beta1',
        betaBuildNumber: 99,
        betaDownloadUrl: 'https://example.com/beta.apk',
        betaTesterUids: ['user1', 'user2'],
      );
      final result = evaluateBetaAvailability(
        currentBuild: 57,
        currentUid: 'user1',
        config: config,
      );
      expect(result.hasBetaUpdate, true);
      expect(result.betaVersion, '1.2.49-beta1');
      expect(result.betaDownloadUrl, 'https://example.com/beta.apk');
    });

    test('ベータテスターでも既にベータビルド以上の場合は通知しない', () {
      const config = AppMinVersionConfig(
        minSupportedBuild: 0,
        betaEnabled: true,
        betaBuildNumber: 99,
        betaTesterUids: ['user1'],
      );
      final result = evaluateBetaAvailability(
        currentBuild: 99,
        currentUid: 'user1',
        config: config,
      );
      expect(result.hasBetaUpdate, false);
    });
  });
}
