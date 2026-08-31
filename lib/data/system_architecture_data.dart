/// アプリのシステム構成・外部サービス・アカウント関係を整理したデータ。
///
/// 【重要】この情報は最高管理者(superAdmin)のみ閲覧可能。
/// 開発過程で導入した外部サービスのAPIキー・課金主体・権限範囲を
/// 一元的に把握できるようにし、退職者対応・引き継ぎ・セキュリティ監査の
/// 際に「どこに何のアカウントがあるか分からない」事態を防ぐ目的で作成。
///
/// ※このファイル自体には実際のパスワード・APIキーの値は一切含めない。
///   あくまで「何がどこにあるか」の管理台帳として機能させる。
library;

/// 「バージョン名(1.1.9など)」と「ビルド番号(強制アップデートゲートで
/// 入力する数字)」の対応記録。
///
/// 【使い方】強制アップデートゲートの「最低利用可能ビルド番号」には、
/// バージョン名ではなく、この表の「ビルド番号」列の数字を入力する。
/// (pubspec.yaml の "version: 1.1.9+8" の "+" の後ろの数字がビルド番号)
///
/// 【重要】新しいAPKをビルドするたびに、このリストの先頭に1行追加すること。
/// これを忘れると、次にゲートのビルド番号を確認する際にここが古いままになる。
class VersionBuildRecord {
  final String versionName; // 例: "1.1.9"
  final int buildNumber; // 例: 8
  final String releaseDate; // 例: "2026-08-24"
  final String summary; // その版の主な変更点(短く)

  const VersionBuildRecord({
    required this.versionName,
    required this.buildNumber,
    required this.releaseDate,
    required this.summary,
  });
}

/// 新しいバージョンほどリストの先頭に追加すること。
const List<VersionBuildRecord> versionBuildHistory = [
  VersionBuildRecord(
    versionName: '1.2.40',
    buildNumber: 49,
    releaseDate: '2026-09-01',
    summary: '端末側二重保存(Outbox)による恒久的データ消失防止対策(★配布中の最新版)',
  ),
  VersionBuildRecord(
    versionName: '1.2.39',
    buildNumber: 48,
    releaseDate: '2026-09-01',
    summary: '案件化対象を定期点検・故障対応・修理・新設設置に限定+未グルーピング一覧のスクロール対応',
  ),
  VersionBuildRecord(
    versionName: '1.2.38',
    buildNumber: 47,
    releaseDate: '2026-09-01',
    summary: '未グルーピング日報を全員が「案件として登録」できる機能を追加',
  ),
  VersionBuildRecord(
    versionName: '1.2.37',
    buildNumber: 46,
    releaseDate: '2026-09-01',
    summary: '設計図・運用ルール(WEB/APK同時リリース等)をプロフィール内から閲覧可能に',
  ),
  VersionBuildRecord(
    versionName: '1.2.36',
    buildNumber: 45,
    releaseDate: '2026-09-01',
    summary: '日報→案件反映の不具合対応・入力エラー通知の改善',
  ),
  VersionBuildRecord(
    versionName: '1.2.13',
    buildNumber: 22,
    releaseDate: '2026-08-26',
    summary: 'ホーム画面に「新しいバージョンがあります」お知らせバナーを追加',
  ),
  VersionBuildRecord(
    versionName: '1.2.12',
    buildNumber: 21,
    releaseDate: '2026-08-25',
    summary: '月次CSVエクスポート機能を追加(管理者ダッシュボード)',
  ),
  VersionBuildRecord(
    versionName: '1.2.3',
    buildNumber: 12,
    releaseDate: '2026-08-24',
    summary: 'マニュアル(PDF/Web/MD)にAPK版QRコード・インストール手順を追加',
  ),
  VersionBuildRecord(
    versionName: '1.2.2',
    buildNumber: 11,
    releaseDate: '2026-08-24',
    summary: '作業報告書スキャンのエラー表示に診断情報(実行環境・バージョン・画像サイズ)を追加(調査継続中)',
  ),
  VersionBuildRecord(
    versionName: '1.2.1',
    buildNumber: 10,
    releaseDate: '2026-08-24',
    summary: '作業報告書スキャンの「サーバー接続失敗」エラーを修正(タイムアウト値が短すぎた不具合)',
  ),
  VersionBuildRecord(
    versionName: '1.2.0',
    buildNumber: 9,
    releaseDate: '2026-08-24',
    summary: '作業報告書スキャンにタイムアウト短縮の不具合を含むリトライ機能を追加(1.2.1で修正)',
  ),
  VersionBuildRecord(
    versionName: '1.1.9',
    buildNumber: 8,
    releaseDate: '2026-08-24',
    summary: 'CSV出力に「このデバイスに保存」ボタンを追加',
  ),
  VersionBuildRecord(
    versionName: '1.1.8',
    buildNumber: 7,
    releaseDate: '2026-08-22',
    summary: 'WEB版マニュアルにホーム画面追加(PWA)手順を追加',
  ),
  VersionBuildRecord(
    versionName: '1.1.7',
    buildNumber: 6,
    releaseDate: '2026-08-21',
    summary: '強制アップデートゲート機能を追加',
  ),
  VersionBuildRecord(
    versionName: '1.1.6',
    buildNumber: 5,
    releaseDate: '2026-08-21',
    summary: 'ホーム画面に更新通知バナーを追加',
  ),
  VersionBuildRecord(
    versionName: '1.1.5',
    buildNumber: 4,
    releaseDate: '2026-08-21',
    summary: '作業報告書スキャンの導線を改善',
  ),
  VersionBuildRecord(
    versionName: '1.1.4',
    buildNumber: 3,
    releaseDate: '2026-08-21',
    summary: '作業者氏名を従業員リストからの選択方式に変更',
  ),
  VersionBuildRecord(
    versionName: '1.1.0',
    buildNumber: 2,
    releaseDate: '2026-08-20',
    summary: '入力マニュアル画面からPDF/Web/編集可能版をダウンロード可能に',
  ),
  VersionBuildRecord(
    versionName: '1.0.0',
    buildNumber: 1,
    releaseDate: '2026-08-18',
    summary: '初回リリース',
  ),
];

/// サービスの現在の状態
enum ServiceStatus {
  active, // 現在使用中
  newlyAdded, // 今回の開発過程で新規導入
  deprecated, // 使われなくなった/廃止予定
  removed, // 既に削除・解約済み
}

class ExternalService {
  final String name; // サービス名
  final String category; // カテゴリ(認証, データベース, AI/OCR, ホスティング等)
  final ServiceStatus status;
  final String provider; // 提供元(Google, Microsoft等)
  final String purpose; // 用途
  final String accountOwner; // 契約・アカウントの名義/管理場所
  final String costNote; // 課金体系の注意点
  final String credentialLocation; // 認証情報の保管場所(値そのものは書かない)
  final List<String> notes; // 補足事項

  const ExternalService({
    required this.name,
    required this.category,
    required this.status,
    required this.provider,
    required this.purpose,
    required this.accountOwner,
    required this.costNote,
    required this.credentialLocation,
    this.notes = const [],
  });
}

/// 現在アプリが依存している外部サービス一覧
const List<ExternalService> externalServices = [
  ExternalService(
    name: 'Firebase (sn-report プロジェクト)',
    category: '認証 / データベース',
    status: ServiceStatus.active,
    provider: 'Google (Firebase)',
    purpose: 'ユーザー認証(Firebase Auth)、日報・社員・店舗データの保存(Firestore)',
    accountOwner: '会社のGoogleアカウントに紐づくFirebaseプロジェクト「sn-report」',
    costNote: 'Sparkプラン(無料枠)を想定。データ量・読み書き回数が増えた場合はBlazeプラン(従量課金)への移行を検討',
    credentialLocation:
        'Admin SDKキー(サーバー操作用)・google-services.json(Android用)は開発環境の設定フォルダで管理',
    notes: [
      'アプリの心臓部。日報・社員名簿・店舗マスタなど全データがここに保存される',
      '退職者アカウントの削除・権限変更もこのFirebase Authから行う',
    ],
  ),
  ExternalService(
    name: 'Azure AI Document Intelligence',
    category: 'AI / OCR',
    status: ServiceStatus.newlyAdded,
    provider: 'Microsoft Azure',
    purpose: 'カメラで撮影した紙の作業報告書から、店番・メーカー名・型式など23項目を自動抽出するAI-OCR',
    accountOwner: '御社のAzureサブスクリプション(テナント: sapporonakano.onmicrosoft.com)',
    costNote:
        'Standard S0プラン。ページ数に応じた従量課金(カスタムモデルの解析は1ページあたり数円〜十数円程度)。'
        '利用頻度が増える場合はAzure Portalで実際の請求額を確認すること',
    credentialLocation:
        'サブスクリプションキーは中継API(下記 Azure Functions)側にのみ保管。'
        'このアプリ自体はキーを持たない設計',
    notes: [
      'カスタムテンプレートモデル「sdrs-repair-report-v1」を学習済み',
      'AIの抽出結果は必ず「確認・修正画面」を経由させる設計(AI一発登録は行わない)',
      'モデルの追加学習やAzure Portalでの管理はAzureサブスクリプションの管理者権限が必要',
    ],
  ),
  ExternalService(
    name: 'Azure Functions (nakano-scan-proxy)',
    category: 'バックエンドAPI(中継サーバー)',
    status: ServiceStatus.newlyAdded,
    provider: 'Microsoft Azure',
    purpose:
        'スマホアプリとAzure AI Document Intelligenceの間に立つ中継サーバー。'
        'アプリ本体にAIサービスの本物の鍵(サブスクリプションキー)を持たせないためのセキュリティ対策として新規導入',
    accountOwner: '御社のAzureサブスクリプション(リソースグループ: nakano-reikiken-rg、東日本リージョン)',
    costNote:
        'Consumption(従量課金)プラン。呼び出し回数が少ないうちは月額ほぼ無料〜数百円程度。'
        '1日に何百回もスキャンするような使い方に変わった場合はコスト再確認が必要',
    credentialLocation:
        'AIサービスの鍵はAzure Functionsのアプリ設定(サーバー側)にのみ保管。'
        'アプリ側はこの中継サーバーを呼び出すための限定的な鍵のみ保持(AI鍵そのものへのアクセス権はない)',
    notes: [
      '今回の開発で新規に追加したサービス',
      '「アプリにAIの本物の鍵を埋め込まない」というセキュリティ改善のために導入',
      '中継サーバーのプログラム自体はAzure上で稼働しており、アプリの見た目には現れない裏方の仕組み',
    ],
  ),
  ExternalService(
    name: 'Google Play Console / Androidアプリ配布',
    category: 'アプリ配布',
    status: ServiceStatus.active,
    provider: 'Google',
    purpose: '社員のスマホへのアプリ配布(APK/AABビルド)',
    accountOwner: '会社のGoogleアカウント',
    costNote: 'アプリ内で完結する範囲では追加費用なし(社外への一般公開をする場合は別途登録費用が必要)',
    credentialLocation: 'アプリの署名鍵(リリースビルド用)は開発環境内で厳重に管理',
    notes: ['現状は社内配布(野良アプリ形式)を想定。ストア公開する場合は別途申請が必要'],
  ),
];

/// 過去に検討したが不要と判断した、または導入を見送ったサービス
const List<ExternalService> consideredButNotAdopted = [
  ExternalService(
    name: 'プロワン本体とのリアルタイムAPI連携',
    category: 'バックエンドAPI(検討のみ・不採用)',
    status: ServiceStatus.removed,
    provider: '－(プロワン側システムの提供元)',
    purpose:
        'プロワン管轄案件(SE店舗以外)のスキャン時に、プロワン本体の'
        'データベースへ直接アクセスして案件情報(顧客名・作業内容等)を'
        'リアルタイムに取得することを将来構想として検討していた',
    accountOwner: '－(採用見送りのため契約・アカウント自体が存在しない)',
    costNote: '－',
    credentialLocation: '－(構築していないため認証情報自体が存在しない)',
    notes: [
      '2026-08-28: 「プロワンとのAPI連携は考えにくい」との判断により、'
          '将来構想として不採用に確定。プロワン側にAPI提供の仕組みが'
          'あるかどうか自体が不明であり、仮に実現できたとしても先方システム'
          'への外部連携許可・仕様公開が必要になるなど実現可能性が低いため',
      '【代替として採用していた方式(こちらも廃止)】プロワン側が日次で'
          'エクスポートするCSVをFirestore上のキャッシュ'
          '(prowan_job_cache コレクション)に取り込み、現場スキャン時に'
          '伝票No(案件管理番号)で照合する「CSV照合方式」を2026-08中旬に'
          '一時導入していたが、現場でのスキャン入力がCSV取込より'
          '時系列的に先行するため直近案件が「該当なし」になりやすいという'
          '根本的な限界があり、2026-08-28に廃止(詳細は更新履歴v1.2.30参照)',
      '【最終的な採用方式】CSV照合・API連携のどちらにも依存せず、作業'
          '報告書PDF自体をAI-OCR(Azure AI Document Intelligence)で直接'
          '読み取り、18項目全てを各入力欄へそのまま反映する方式に変更。'
          '外部システムとの連携を一切必要としないため、プロワン側の'
          '都合に左右されない安定した仕組みになっている',
      '【削除したコード】旧CSV照合方式のために作成していた'
          'csv_cache_backend/配下のPythonスクリプト一式(CSV取込・曖昧'
          '一致・日次再照合)、Flutter側の関連ファイル(prowan_job_cache.dart'
          'モデル、prowan_job_cache_service.dart)、Firestoreセキュリティ'
          'ルールの prowan_job_cache コレクション定義を、2026-08-28に'
          '全て削除済み',
    ],
  ),
  ExternalService(
    name: 'Firebase Cloud Functions',
    category: 'バックエンドAPI(検討のみ)',
    status: ServiceStatus.removed,
    provider: 'Google (Firebase)',
    purpose: '当初、AIサービスの鍵を隠す中継サーバーとしてこちらを検討',
    accountOwner: '－(採用見送り)',
    costNote: '－',
    credentialLocation: '－(構築していないため認証情報自体が存在しない)',
    notes: [
      'デプロイに開発者本人のブラウザ認証が必要な仕組みのため、今回の開発環境では構築できなかった',
      '代わりにAzure Functionsを採用(Azure側は既存の御社契約で認証済みだったため)',
      '今後Google Cloud側の運用に統一したい場合は、改めてFirebase CLIでのログインが必要',
    ],
  ),
];

/// アカウント・権限に関する整理事項
class AccountNote {
  final String title;
  final String description;
  const AccountNote({required this.title, required this.description});
}

/// 今後の課題として意識的に「宿題」として残している項目。
///
/// 現時点では実装・意思決定を見送っているが、将来的に検討が必要な事項を
/// 明文化しておくことで、担当者が変わっても引き継ぎ漏れが起きないようにする。
class FutureConsideration {
  final String title;
  final String description;
  const FutureConsideration({required this.title, required this.description});
}

const List<FutureConsideration> futureConsiderations = [
  FutureConsideration(
    title: 'Google Play内部テストへの移行(今後の課題)',
    description:
        '現状はAPKファイルを直接配布する「野良アプリ」形式で運用している。'
        'この方式では、社員が新しいAPKを自発的に再インストールしない限りアプリは'
        '古いバージョンのまま残り続けるという課題があり、今回「強制アップデート'
        'ゲート」機能を導入した背景の一つとなっている。\n\n'
        'Google Play Consoleの「内部テスト」機能を使えば、Playストア経由で自動更新'
        'が可能になり、この課題自体を構造的に解消できる可能性がある。ただし、'
        'Google Play Consoleへの登録(登録料・審査対応)や、会社としての公開方針'
        '(社内配布のみか、将来的な一般公開の可能性があるか)の意思決定が必要となる'
        'ため、中長期の検討課題として保留している。',
  ),
  FutureConsideration(
    title: 'Firebase Blazeプラン移行によるサーバー完全自動化(今後の課題)',
    description:
        '月次CSVエクスポート機能(v1.2.12で実装済み)は、現状「管理者が'
        'ダッシュボードでボタンを押して出力する」半自動方式(NASへの常時接続PCが'
        'ないための運用)。今後、NASへ常時アクセス可能な社内PCを用意できる場合や、'
        'Firebase Blazeプラン(従量課金)への移行が可能になった場合は、Cloud '
        'Functions + Cloud Schedulerによる完全自動化(月初に自動でCSVを生成し'
        'NASへ転送)へ切り替えることを検討する。現時点ではコスト・運用体制の'
        '観点から見送っている。',
  ),
];

const List<AccountNote> accountStructureNotes = [
  AccountNote(
    title: '【設計原則】案件化の対象は「定期点検・故障対応・修理・新設設置」のみ(2026-09-01追加)',
    description:
        '案件管理は「お客様先での現場対応」を追跡する仕組みであり、事務・'
        '現場事務・倉庫作業・環境整備・その他の社内業務は対象外とする。'
        '本来は日報(現場対応)ありきで案件が生まれる設計のはずが、'
        '過去バージョンでは対応区分を一切見ずに全日報を無差別に案件化'
        'ロジックへ通していたため、設計と実態が逆転していた'
        '(2026-09-01ユーザー指摘により発覚・修正)。新しい対応区分を'
        '追加する際は、CaseEligible判定(WorkReport.isCaseEligible)への'
        '反映を必ず検討すること',
  ),
  AccountNote(
    title: '【運用ルール】WEB版とAPK版は必ず同時リリース(2026-09-01追加)',
    description:
        '過去にWeb版のみ本番デプロイを忘れ、APK版と表示バージョンが'
        '食い違ったまま運用されていた事故があった。以後、機能変更・'
        '不具合修正を行う際は、Firebase Hosting(Web版)へのデプロイと'
        'APKビルドを必ずセットで実施すること。詳細と最新の設計図は'
        '本画面上部の「設計図を見る」から確認できる',
  ),
  AccountNote(
    title: '【運用ルール】APKビルド後は必ずGitHub Releaseも作成する(2026-09-01追加)',
    description:
        'APK版の「最新版をダウンロード」ボタンはGitHub Releasesの"Latest"'
        'タグが指すファイルを固定URLで参照する仕組みになっている。ローカルで'
        'APKをビルドしただけではGitHub Release自体は更新されず、結果として'
        '「新しいビルドをFirestore上は最新と設定したのに、実際にダウンロード'
        'されるAPKは古いまま」という不整合(更新案内バナーが消えない不具合)'
        'が発生した事故があった(2026-09-01発覚)。以後、APKをビルドしたら'
        '`gh release create vX.Y.Z <apkパス>` でGitHub Releaseを必ず作成し、'
        '`gh release list`で"Latest"が新しいバージョンになっているか確認すること',
  ),
  AccountNote(
    title: 'アプリ内の権限は3段階',
    description:
        '一般ユーザー(日報の作成・自分の日報の編集、全社員の日報・業務内容の閲覧が可能。'
        '2026-08より一般作業員から改称し、他ユーザーの業務内容も閲覧できるよう変更)、'
        '一般管理者(上記に加え、一般ユーザーの追加が可能)、'
        '最高管理者(社員の役割変更・削除・退職処理など、全ての操作が可能)。'
        '誤操作や権限乱用を防ぐため、一般管理者には「他人の管理者権限の付与/剥奪」「社員の削除」の権限をあえて与えていない',
  ),
  AccountNote(
    title: 'このアプリのアカウントとAzure/Google契約のアカウントは別物',
    description:
        'アプリにログインする社員アカウント(Firebase Auth)は、Azure・Google Cloudの契約者アカウントとは完全に別の仕組み。'
        '社員を追加してもAzure/Googleの請求には影響しない。逆に、外部サービスの契約解除・鍵の再発行などは、'
        'このアプリの「社員の権限・登録を管理する」画面ではなく、各サービスの管理コンソール(Azure Portal、'
        'Firebase Console等)で直接行う必要がある',
  ),
  AccountNote(
    title: '退職者が出た場合の対応箇所',
    description:
        '①このアプリの「社員の権限・登録を管理する」画面でアカウントを削除(Firebase Authからもログインできなくなる)。'
        '②もしその社員がAzure/Google Cloudの管理コンソールへの直接アクセス権も持っていた場合は、'
        '別途Azure Portal・Google Cloud Consoleでの権限剥奪も必要(アプリ側の削除だけでは連動しない)',
  ),
  AccountNote(
    title: 'APIキー漏洩時の対応履歴',
    description:
        '開発の過程で、AzureのAIサービスの鍵が一時的にチャット上に表示された経緯があったため、'
        '該当の鍵は再生成(旧鍵は完全に失効)し、かつアプリ本体には鍵を持たせない構成(中継サーバー方式)に'
        '変更済み。同様の事態が今後発生した場合も、Azure Portalでの鍵再生成のみで復旧可能な設計になっている',
  ),
];
