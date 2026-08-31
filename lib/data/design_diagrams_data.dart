/// アプリの主要な動作フロー(設計図)を管理するデータ。
///
/// 【運用ルール・2026-09-01追加(社長指示)】
/// 最新の設計図はここに反映し、プロフィール画面
/// (プロフィール → システム構成・アカウント整理 → 設計図)から
/// 常に閲覧できる状態を維持すること。機能変更・不具合修正を行った際は、
/// このファイルも合わせて更新する(コードだけ直して図が古いままにしない)。
///
/// 各フローは「画面内で見やすいステップ形式の表示」用データ(steps)と、
/// 「開発者向けにMermaid記法のソースをコピーして外部ツールで見る」用の
/// mermaidSource の両方を持つ(Flutter自体はMermaidを描画できないため)。
library;

enum FlowStepType { start, process, decision, warning, end }

class FlowStep {
  final FlowStepType type;
  final String label;
  final String? detail;

  const FlowStep({required this.type, required this.label, this.detail});
}

class DesignFlow {
  final String title;
  final String summary;
  final String lastUpdatedVersion; // この図が最後に更新されたアプリバージョン
  final String lastUpdatedDate;
  final List<FlowStep> steps;
  final String mermaidSource;

  const DesignFlow({
    required this.title,
    required this.summary,
    required this.lastUpdatedVersion,
    required this.lastUpdatedDate,
    required this.steps,
    required this.mermaidSource,
  });
}

/// 新しい設計図ほどリストの先頭に追加すること。
const List<DesignFlow> designFlows = [
  DesignFlow(
    title: '① 日報 入力検証フロー',
    summary:
        '必須項目未入力時に「先に進めない・通知する」という設計原則を実装したフロー。'
        '保存ボタン押下から、成功/失敗それぞれの通知までの分岐を示す。',
    lastUpdatedVersion: '1.2.36',
    lastUpdatedDate: '2026-09-01',
    steps: [
      FlowStep(type: FlowStepType.start, label: '保存ボタンを押す'),
      FlowStep(
        type: FlowStepType.decision,
        label: '多重押下チェック',
        detail: '保存処理中(_isSaving)なら何もしない(二重保存防止)',
      ),
      FlowStep(
        type: FlowStepType.decision,
        label: 'フォーム全体を検証(_formKey.validate())',
        detail: '必須項目(作業内容・冷媒種類・冷媒量など)が未入力/不正な値でないか確認',
      ),
      FlowStep(
        type: FlowStepType.warning,
        label: '【NG】赤色スナックバー通知',
        detail: '「入力に不備があります。赤字の項目をご確認ください(保存されていません)」を表示',
      ),
      FlowStep(
        type: FlowStepType.warning,
        label: '【NG】最初の不正項目までスクロール',
        detail: '_scrollToFirstInvalidField() が該当欄まで自動スクロール+フォーカス移動',
      ),
      FlowStep(
        type: FlowStepType.end,
        label: '【NG】保存処理は実行されない',
        detail: 'ここで処理終了。従業員は必ず不備を認識できる(=先に進めない設計)',
      ),
      FlowStep(
        type: FlowStepType.process,
        label: '【OK】Firestoreへ保存実行',
        detail: 'addReport() / updateReport() をtry-catchで実行',
      ),
      FlowStep(type: FlowStepType.process, label: '【OK成功】保存完了スナックバー+画面を閉じる'),
      FlowStep(
        type: FlowStepType.warning,
        label: '【OK失敗=通信エラー等】赤色スナックバー通知',
        detail: '「保存に失敗しました。もう一度お試しください」+エラー内容を表示(画面は無反応にならない)',
      ),
    ],
    mermaidSource: '''
flowchart TD
    A[保存ボタンを押す] --> B{多重押下中?}
    B -->|Yes| Z1[何もしない]
    B -->|No| C{フォーム検証OK?}
    C -->|NG| D[赤色スナックバー通知:\\n入力に不備があります]
    D --> E[最初の不正項目まで\\n自動スクロール+フォーカス]
    E --> F[保存処理は実行しない]
    C -->|OK| G[Firestoreへ保存実行\\ntry-catch]
    G -->|成功| H[成功スナックバー+画面を閉じる]
    G -->|失敗/通信エラー| I[赤色スナックバー通知:\\n保存に失敗しました]
''',
  ),
  DesignFlow(
    title: '② 日報保存 → 案件反映フロー',
    summary:
        '1件の日報保存が、裏側で自動的に「案件(cases)」へグルーピングされる仕組み。'
        '伝票No/受付Noの有無で判定優先度が変わる。',
    lastUpdatedVersion: '1.2.36',
    lastUpdatedDate: '2026-09-01',
    steps: [
      FlowStep(type: FlowStepType.start, label: '日報の保存が完了'),
      FlowStep(
        type: FlowStepType.process,
        label: 'CaseService.syncCaseForReport() を呼ぶ',
        detail: '日報保存の直後に自動実行(従業員には見えない裏側処理)',
      ),
      FlowStep(
        type: FlowStepType.decision,
        label: 'プロワン伝票No(pro_wan_ref_number)が入力済み?',
      ),
      FlowStep(
        type: FlowStepType.process,
        label: '【最優先】伝票Noで確実グルーピング(confirmed)',
        detail: 'ドキュメントID: prowan_slip_伝票No。同じ伝票Noの日報は必ず同一案件に集約',
      ),
      FlowStep(
        type: FlowStepType.decision,
        label: '(伝票Noなしの場合)SE受付No(receipt_number)が入力済み?',
      ),
      FlowStep(
        type: FlowStepType.process,
        label: '【次点】受付Noで確実グルーピング(confirmed)',
        detail: 'ドキュメントID: se_receipt_受付No',
      ),
      FlowStep(
        type: FlowStepType.process,
        label: '【番号なし】曖昧グルーピング(suggested)',
        detail: '同じ店舗+訪問日が近い(3日以内)+作業内容の類似度0.5以上の既存日報と自動で合流を試みる',
      ),
      FlowStep(
        type: FlowStepType.warning,
        label: '【重要・過去の不具合原因】古いコードで保存された日報',
        detail:
            'このsyncCaseForReport()自体が実行されない/実行時のコードが古いと'
            'case_idキー自体が欠落し、案件に反映されない(Bug②の実体)。'
            '③のバージョン整合性フローで防止する',
      ),
      FlowStep(
        type: FlowStepType.end,
        label: '案件(cases)コレクションに反映完了',
        detail: '参加者・合計作業時間・冷媒充填有無などを自動集計',
      ),
    ],
    mermaidSource: '''
flowchart TD
    A[日報の保存が完了] --> B[CaseService.syncCaseForReport呼び出し]
    B --> C{伝票No入力済み?}
    C -->|Yes| D[確実グルーピング confirmed\\nprowan_slip_伝票No]
    C -->|No| E{SE受付No入力済み?}
    E -->|Yes| F[確実グルーピング confirmed\\nse_receipt_受付No]
    E -->|No| G[曖昧グルーピング suggested\\n同店舗+近い訪問日+類似度0.5以上]
    D --> H[案件cases コレクションに反映]
    F --> H
    G --> H
    I[古いバージョンのコードで実行された場合] -.->|不具合の原因| B
''',
  ),
  DesignFlow(
    title: '③ バージョン整合性フロー(Web/APK共通)',
    summary:
        '「実行中のコードが古いまま使われ続ける」不具合(Bug②)を防止する仕組み。'
        'Web版はコンパイル時定数、APK版はビルド番号で判定する。',
    lastUpdatedVersion: '1.2.36',
    lastUpdatedDate: '2026-09-01',
    steps: [
      FlowStep(type: FlowStepType.start, label: 'アプリ起動 / ログイン後'),
      FlowStep(
        type: FlowStepType.process,
        label: '現在の実行バージョンを取得',
        detail:
            'Web版: build_info.dart の kCompiledBuildNumber(コンパイル時に焼き込み済み)\n'
            'APK版: PackageInfo.fromPlatform()(AndroidManifestのversionCode)',
      ),
      FlowStep(
        type: FlowStepType.process,
        label:
            'Firestore app_config/settings から'
            'min_supported_build(強制)/latest_build_number(お知らせ)を取得',
      ),
      FlowStep(
        type: FlowStepType.decision,
        label: '現在バージョン < min_supported_build ?',
      ),
      FlowStep(
        type: FlowStepType.warning,
        label: '【強制ブロック】更新必須画面を表示',
        detail:
            'Web版: 「ページを再読み込みしてください」ボタン(Service Worker解除+リロード)\n'
            'APK版: 「新しいアプリ(APK)をダウンロード」ボタン',
      ),
      FlowStep(
        type: FlowStepType.decision,
        label: '現在バージョン < latest_build_number ?',
      ),
      FlowStep(
        type: FlowStepType.process,
        label: '【任意お知らせ】ホーム画面に更新バナー表示',
        detail: 'ブロックはしない。押すと同じく更新導線へ',
      ),
      FlowStep(type: FlowStepType.end, label: '通常利用可能'),
    ],
    mermaidSource: '''
flowchart TD
    A[アプリ起動/ログイン後] --> B[現在の実行バージョンを取得]
    B --> C[Firestore app_config/settings\\nmin_supported_build / latest_build_number を取得]
    C --> D{現在 < min_supported_build?}
    D -->|Yes| E[強制ブロック画面\\nWeb:再読み込み / APK:再インストール]
    D -->|No| F{現在 < latest_build_number?}
    F -->|Yes| G[ホーム画面に更新お知らせバナー表示\\nブロックはしない]
    F -->|No| H[通常利用可能]
    G --> H
''',
  ),
];

/// 運用ルール(社長からの指示・2026-09-01追加)。
/// 開発・リリース作業を行う際は必ずこれに従うこと。
class OperationalRule {
  final String title;
  final String description;
  final String addedDate;

  const OperationalRule({
    required this.title,
    required this.description,
    required this.addedDate,
  });
}

const List<OperationalRule> operationalRules = [
  OperationalRule(
    title: 'WEB版とAPK版は必ず同時リリースする',
    description:
        '過去に「サンドボックス内でビルド・検証は完了していたが、本番Firebase '
        'Hostingへの実デプロイを忘れていた」という事故(Web版が旧バージョンの'
        'まま残った)が発生した。以後、機能変更・不具合修正を行った際は、'
        'Web版のFirebase Hostingへのデプロイと、APK版のビルド(署名済みapk生成)'
        'を必ずセットで実施し、片方だけ更新された状態を作らないこと。'
        'バージョン番号(pubspec.yaml・build_info.dart・Firestoreの'
        'latest_build_number)も両版で必ず一致させる。',
    addedDate: '2026-09-01',
  ),
  OperationalRule(
    title: '設計図・マニュアル等の管理情報はプロフィール内から常時閲覧できる状態を維持する',
    description:
        'アプリの動作フロー(設計図)・入力マニュアル・システム構成の情報は、'
        '担当者が変わってもすぐ参照できるよう、チャットのやり取りだけに'
        '留めず、必ずアプリ内(プロフィール → システム構成・アカウント整理)'
        'から閲覧できる形でコードに反映すること。機能変更のたびに、'
        '対応する設計図(design_diagrams_data.dart)・マニュアル'
        '(manual_data.dart)・システム構成情報'
        '(system_architecture_data.dart)も併せて更新する。',
    addedDate: '2026-09-01',
  ),
];
