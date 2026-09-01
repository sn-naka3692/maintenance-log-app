import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/part_used.dart';
import '../models/prowan_report_detail.dart';
import '../models/store.dart';
import '../models/store_system_report.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../services/photo_upload_service.dart';
import '../theme/app_theme.dart';
import '../utils/scan_date_parser.dart';
import '../widgets/document_scan_flow.dart';
import '../widgets/store_picker_field.dart';

/// 作業内容の記入サポート(チレアカップ)モード
/// 店舗区分(SE/プロワン)と対応区分によって、重複を避けるべく内容を切り替える。
enum _WorkSupportMode { seRepair, seOther, nonSE }

class ReportEditScreen extends StatefulWidget {
  final WorkReport? existing;

  const ReportEditScreen({super.key, this.existing});

  @override
  State<ReportEditScreen> createState() => _ReportEditScreenState();
}

class _ReportEditScreenState extends State<ReportEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _clientNameCtrl;
  late TextEditingController _storeFreeTextCtrl;
  late TextEditingController _workContentCtrl;
  late TextEditingController _equipmentModelCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _successCtrl;
  late TextEditingController _issuesCtrl;
  late TextEditingController _proWanCtrl;
  late Map<String, TextEditingController> _ssCtrls;
  late TextEditingController _tagInputCtrl;
  late TextEditingController _nonSeRefrigerantTypeCtrl;
  late TextEditingController _nonSeRefrigerantAmountCtrl;
  // 【不具合修正・2026-08】プロワンCSVキャッシュ照合で反映先が無かった項目
  // (店舗住所・部門・系統番号・障害内容・障害機器・原因・依頼内容・訪問結果・
  // 今後の予定・技術者氏名・訪問日)の受け皿(ProWanReportDetail)用コントローラ。
  late Map<String, TextEditingController> _pwCtrls;
  // 「案件においての役割」自由記述用コントローラ(2026-08導入・人事評価データ収集用)
  late TextEditingController _caseRoleNoteCtrl;
  // 「案件においての役割」プルダウン選択値。未選択は null。
  String? _caseRolePreset;

  String? _selectedStoreId;
  final List<String> _selectedCoWorkerIds = [];
  // 作業者氏名(報告書控え)の入力方式:
  // 現場作業者はほぼ全員アプリ登録済みの社員のため、まず従業員マスタから選択する
  // ドロップダウンを用意する。リストにない場合(協力会社・臨時作業者など)のみ
  // 「その他(手入力)」を選び、_ssCtrls['workerName']へ直接入力してもらう。
  // OCR(AIスキャン)はこの項目を対象外とする(誤検出対策・運用効率化のため)。
  static const String _workerNameOtherValue = '__other__';
  String? _workerNameSelection;
  DateTime _visitDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();
  ResponseType _responseType = ResponseType.regularInspection;
  final List<PartUsed> _parts = [];
  final List<String> _tags = [];
  final List<String> _photoPaths = [];

  // 音声入力(speech_to_text)
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  TextEditingController? _activeListenController;

  // ------------------------------------------------------------
  // プロワン管轄案件の入力状態管理
  // ------------------------------------------------------------
  // フィールド名 -> "auto"|"manual"。編集開始時に既存レコードから引き継ぐ
  // (新規作成時は空、つまり全て「手入力」扱いから始まる)。
  // 【設計転換・2026-08-28】従来はCSVキャッシュ照合の自動反映/手入力の
  // 区別に使っていたが、CSV照合ロジック廃止後は「スキャン(OCR)による
  // 自動入力」か「手入力」かの区別として引き続き使う。
  Map<String, String> _fieldSources = {};
  // 【設計転換・2026-08-28で意味変更】従来は「CSVキャッシュとの曖昧一致
  // が未確定」を示すフラグだったが、CSV照合ロジック廃止後はこの画面からは
  // 新規にtrueへ設定することはない(既存レコードの値をそのまま保持・
  // 保存するのみの後方互換フィールド)。
  bool _manualReviewNeeded = false;
  // 【設計転換・2026-08-28で意味変更】従来は照合で一致したキャッシュ側の
  // 伝票Noを保持していたが、CSV照合ロジック廃止後はこの画面からは
  // 新規に設定することはない(既存レコードの値をそのまま保持・保存する
  // のみの後方互換フィールド)。
  String _matchedCacheJobNumber = '';

  bool get isEditing => widget.existing != null;

  // 写真のアップロード先パス(report_photos/{reportId}/...)を決めるために、
  // 新規作成時もこの画面を開いた時点でIDを確定させておく
  // (従来は保存時にappState.newId()を呼んでいたが、それでは写真アップロード
  // 時にまだIDが存在しないため、initStateで先に確定させる方式に変更)。
  late String _reportId;
  // 保存前に選択された写真をアップロード中かどうか(保存ボタンの多重押下防止用)。
  bool _isUploadingPhoto = false;
  // 保存処理中の多重押下防止(Firestore書き込み中に連打されるのを防ぐ)。
  bool _isSaving = false;

  // 【不具合修正・2026-09】必須項目が未入力のまま保存ボタンが押された際、
  // 従来は`Form.validate()`がfalseを返すだけで画面上に何の通知もなく、
  // 保存も進まないという「サイレントバグ」だった(佐藤さんの案件反映漏れの
  // 調査で判明したBug①)。ユーザーが「保存が終わったのに何も起きない」と
  // 感じて操作を諦めてしまい、そのまま日報自体が保存されない事態を防ぐため、
  // (1)明確なエラー通知を表示し、(2)最初に見つかった必須未入力欄まで
  // 自動スクロールしてフォーカスすることで、入力者が確実に気づける設計にする。
  //
  // 対象はスクロールで画面外に隠れがちな「必須」バリデータ付きフィールド
  // (表示条件によって出現する冷媒情報セクションなど)。ListViewには既に
  // cacheExtent: 5000が設定されているため、画面外でもFormFieldStateが
  // 生成済みであり、hasErrorを確実に判定できる。
  final _workContentFieldKey = GlobalKey<FormFieldState<String>>();
  final _nonSeRefrigerantTypeFieldKey = GlobalKey<FormFieldState<String>>();
  final _nonSeRefrigerantAmountFieldKey = GlobalKey<FormFieldState<String>>();
  final _seRefrigerantTypeFieldKey = GlobalKey<FormFieldState<String>>();
  final _seRefrigerantAmountFieldKey = GlobalKey<FormFieldState<String>>();
  // 【2026-09追加】後日の突合(記入漏れチェック・請求確認・お客様問い合わせ対応)
  // を可能にするため、現場で必ず控えてもらう3種の管理番号を必須項目化する。
  // - プロワン管轄案件: 伝票No(_proWanCtrl)
  // - SE店舗案件      : 弊社受付No・お客様受付No(両方)
  final _proWanRefFieldKey = GlobalKey<FormFieldState<String>>();
  final _seReceiptNumberFieldKey = GlobalKey<FormFieldState<String>>();
  final _seCustomerReceiptNumberFieldKey =
      GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    _initSpeech();
    final e = widget.existing;
    _reportId = e?.id ?? context.read<AppState>().newId();
    _selectedStoreId = e?.storeId;
    _clientNameCtrl = TextEditingController(text: e?.clientName ?? '');
    // storeIdが設定されている場合、自由入力欄は空。それ以外はclientNameを自由入力の初期値とする
    _storeFreeTextCtrl = TextEditingController(
      text: (e?.storeId == null) ? (e?.clientName ?? '') : '',
    );
    _workContentCtrl = TextEditingController(text: e?.workContent ?? '');
    _equipmentModelCtrl = TextEditingController(text: e?.equipmentModel ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _successCtrl = TextEditingController(text: e?.successPoints ?? '');
    _issuesCtrl = TextEditingController(text: e?.issuesPoints ?? '');
    _proWanCtrl = TextEditingController(text: e?.proWanRefNumber ?? '');
    _nonSeRefrigerantTypeCtrl = TextEditingController(
      text: e?.nonSeRefrigerantType ?? '',
    );
    _nonSeRefrigerantAmountCtrl = TextEditingController(
      text: e?.nonSeRefrigerantAmountKg ?? '',
    );
    final pw = e?.proWanReportDetail ?? ProWanReportDetail();
    _pwCtrls = {
      'storeAddress': TextEditingController(text: pw.storeAddress),
      'clientName': TextEditingController(text: pw.clientName),
      'receiptDate': TextEditingController(text: pw.receiptDate),
      'department': TextEditingController(text: pw.department),
      'systemNumber': TextEditingController(text: pw.systemNumber),
      'caseNo': TextEditingController(text: pw.caseNo),
      'equipmentLocation': TextEditingController(text: pw.equipmentLocation),
      'requestContent': TextEditingController(text: pw.requestContent),
      'cause': TextEditingController(text: pw.cause),
      'visitResult': TextEditingController(text: pw.visitResult),
      'futurePlan': TextEditingController(text: pw.futurePlan),
      'technicianName': TextEditingController(text: pw.technicianName),
    };
    final ss = e?.storeSystemReportCopy ?? StoreSystemReport();
    _ssCtrls = {
      'receiptNumber': TextEditingController(text: ss.receiptNumber),
      'customerReceiptNumber': TextEditingController(
        text: ss.customerReceiptNumber,
      ),
      'refrigerantType': TextEditingController(text: ss.refrigerantType),
      'refrigerantAmount': TextEditingController(text: ss.refrigerantAmount),
      'requestContent': TextEditingController(text: ss.requestContent),
      'equipmentName': TextEditingController(text: ss.equipmentName),
      'maker': TextEditingController(text: ss.maker),
      'modelNumber': TextEditingController(text: ss.modelNumber),
      'treatmentContent': TextEditingController(text: ss.treatmentContent),
      'part': TextEditingController(text: ss.part),
      'detailPart': TextEditingController(text: ss.detailPart),
      'phenomenon': TextEditingController(text: ss.phenomenon),
      'phenomenonNote': TextEditingController(text: ss.phenomenonNote),
      'cause': TextEditingController(text: ss.cause),
      'treatmentContent2': TextEditingController(text: ss.treatmentContent2),
      'part1': TextEditingController(text: ss.part1),
      'part2': TextEditingController(text: ss.part2),
      'part3': TextEditingController(text: ss.part3),
      'part4': TextEditingController(text: ss.part4),
      'part5': TextEditingController(text: ss.part5),
      'remarks': TextEditingController(text: ss.remarks),
      'storeNumber': TextEditingController(text: ss.storeNumber),
      'scannedAddress': TextEditingController(text: ss.scannedAddress),
      'scannedTel': TextEditingController(text: ss.scannedTel),
      'machineNo': TextEditingController(text: ss.machineNo),
      'assetNo': TextEditingController(text: ss.assetNo),
      'barcode': TextEditingController(text: ss.barcode),
      'deliveryDate': TextEditingController(text: ss.deliveryDate),
      'workerName': TextEditingController(text: ss.workerName),
      'recoveryAmount': TextEditingController(text: ss.recoveryAmount),
    };
    _tagInputCtrl = TextEditingController();
    _caseRoleNoteCtrl = TextEditingController(text: e?.caseRoleNote ?? '');
    _caseRolePreset = (e != null && e.caseRolePreset.isNotEmpty)
        ? e.caseRolePreset
        : null;

    if (e != null) {
      _visitDate = e.visitDate;
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endTime = TimeOfDay.fromDateTime(e.endTime);
      _responseType = e.responseType;
      _parts.addAll(e.partsUsed);
      _tags.addAll(e.tags);
      _photoPaths.addAll(e.photoPaths);
      _selectedCoWorkerIds.addAll(e.coWorkerIds);
      _fieldSources = Map<String, String>.from(e.fieldSources);
      _manualReviewNeeded = e.manualReviewNeeded;
      _matchedCacheJobNumber = e.matchedCacheJobNumber;
    }
    // 既存データの「作業者氏名」(過去の手入力・OCR取り込み分含む)を、
    // 従業員マスタの氏名と照合し、一致すればその社員を選択済み状態にする。
    // 一致しない場合(退職者・協力会社など)は「その他(手入力)」として扱う。
    final existingWorkerName = _ssCtrls['workerName']!.text.trim();
    if (existingWorkerName.isNotEmpty) {
      final users = context.read<AppState>().users;
      final matched = users
          .where((u) => u.name == existingWorkerName)
          .firstOrNull;
      _workerNameSelection = matched?.id ?? _workerNameOtherValue;
    }

    // プロワンCSVキャッシュ照合で自動入力される主要フィールドについて、
    // ユーザーが手動で編集したことを検知したら「manual(手入力確定)」として
    // マークする(前セッションで確定した設計方針: 手入力修正は常時可能・
    // 自動入力/手入力を区別してフラグ管理)。
    // 「auto」のまま保存された場合は、日次CSV再照合バッチが引き続き
    // 自動補完の対象として扱うことができる。
    _clientNameCtrl.addListener(() => _markFieldEditedManually('client_name'));
    _storeFreeTextCtrl.addListener(
      () => _markFieldEditedManually('client_name'),
    );
    _workContentCtrl.addListener(
      () => _markFieldEditedManually('work_content'),
    );
    _equipmentModelCtrl.addListener(
      () => _markFieldEditedManually('equipment_model'),
    );
    _proWanCtrl.addListener(
      () => _markFieldEditedManually('pro_wan_ref_number'),
    );
    _nonSeRefrigerantTypeCtrl.addListener(
      () => _markFieldEditedManually('non_se_refrigerant_type'),
    );
    _nonSeRefrigerantAmountCtrl.addListener(
      () => _markFieldEditedManually('non_se_refrigerant_amount_kg'),
    );
    // プロワン案件詳細(ProWanReportDetail)の各項目も同様に、ユーザーが
    // 手入力で編集したらmanual確定としてマークし、日次CSV再照合の
    // 自動上書き対象から外す。
    for (final entry in _pwFieldKeyMap.entries) {
      _pwCtrls[entry.key]!.addListener(
        () => _markFieldEditedManually('pro_wan_report_detail.${entry.value}'),
      );
    }
  }

  /// _pwCtrlsのキー(camelCase) -> ProWanReportDetail.toMap()のキー(snake_case)
  /// の対応表。_applyProWanScanResult()での自動反映・manual判定の両方で使う。
  static const Map<String, String> _pwFieldKeyMap = {
    'storeAddress': 'store_address',
    'clientName': 'client_name',
    'receiptDate': 'receipt_date',
    'department': 'department',
    'systemNumber': 'system_number',
    'caseNo': 'case_no',
    'equipmentLocation': 'equipment_location',
    'requestContent': 'request_content',
    'cause': 'cause',
    'visitResult': 'visit_result',
    'futurePlan': 'future_plan',
    'technicianName': 'technician_name',
  };

  /// 指定フィールドを「手入力確定(manual)」としてマークする。
  /// すでにmanualの場合は何もしない(不要な再描画を避ける)。
  void _markFieldEditedManually(String fieldKey) {
    if (_fieldSources[fieldKey] == 'manual') return;
    setState(() => _fieldSources[fieldKey] = 'manual');
  }

  @override
  void dispose() {
    _speech.stop();
    _clientNameCtrl.dispose();
    _storeFreeTextCtrl.dispose();
    _workContentCtrl.dispose();
    _equipmentModelCtrl.dispose();
    _notesCtrl.dispose();
    _successCtrl.dispose();
    _issuesCtrl.dispose();
    _proWanCtrl.dispose();
    _nonSeRefrigerantTypeCtrl.dispose();
    _nonSeRefrigerantAmountCtrl.dispose();
    for (final c in _ssCtrls.values) {
      c.dispose();
    }
    for (final c in _pwCtrls.values) {
      c.dispose();
    }
    _tagInputCtrl.dispose();
    _caseRoleNoteCtrl.dispose();
    super.dispose();
  }

  /// 音声認識エンジンの初期化。未対応のブリブザ/デビスでは失敗する可能性があり、
  /// その場合はマイコボコンをタップした時に案内を表示する。
  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _activeListenController = null);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _activeListenController = null);
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  /// 指定したテキストフィールドの音声入力を開始/停止する。
  /// 既入力済みの内容に追記する形で、認識中のタリーをリアルタイムに反映する。
  Future<void> _toggleVoiceInput(TextEditingController controller) async {
    if (_activeListenController == controller) {
      await _speech.stop();
      if (mounted) setState(() => _activeListenController = null);
      return;
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この端末・ブリブザでは音声入力がご利用いただけません')),
      );
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
    }
    final base = controller.text;
    final prefix = base.isEmpty || base.endsWith('\n') || base.endsWith(' ')
        ? base
        : '$base ';
    setState(() => _activeListenController = controller);
    try {
      await _speech.listen(
        localeId: 'ja_JP',
        onResult: (result) {
          controller.text = prefix + result.recognizedWords;
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        },
      );
    } catch (_) {
      if (mounted) setState(() => _activeListenController = null);
    }
  }

  /// 作業内容の記入サポートモードを、店舗区分(SE店舗かどうか)と対応区分から判定する。
  _WorkSupportMode _workSupportMode(bool isSEStore) {
    if (isSEStore) {
      if (_responseType == ResponseType.repair ||
          _responseType == ResponseType.breakdown) {
        return _WorkSupportMode.seRepair;
      }
      return _WorkSupportMode.seOther;
    }
    return _WorkSupportMode.nonSE;
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null) {
      setState(() {
        _visitDate = picked;
        // スキャン自動反映(auto)された訪問日を人間が明示的に変更したら、
        // 以後のスキャン取り込みで無条件に上書きされないよう manual 確定する。
        _fieldSources['visit_date'] = 'manual';
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _addPart() {
    showDialog(
      context: context,
      builder: (_) =>
          _PartInputDialog(onAdd: (part) => setState(() => _parts.add(part))),
    );
  }

  void _addTag() {
    final t = _tagInputCtrl.text.trim();
    if (t.isNotEmpty && !_tags.contains(t)) {
      setState(() {
        _tags.add(t);
        _tagInputCtrl.clear();
      });
    }
  }

  StoreSystemReport _buildStoreSystemReport() {
    return StoreSystemReport(
      receiptNumber: _ssCtrls['receiptNumber']!.text.trim(),
      customerReceiptNumber: _ssCtrls['customerReceiptNumber']!.text.trim(),
      refrigerantType: _ssCtrls['refrigerantType']!.text.trim(),
      refrigerantAmount: _ssCtrls['refrigerantAmount']!.text.trim(),
      requestContent: _ssCtrls['requestContent']!.text.trim(),
      equipmentName: _ssCtrls['equipmentName']!.text.trim(),
      maker: _ssCtrls['maker']!.text.trim(),
      modelNumber: _ssCtrls['modelNumber']!.text.trim(),
      treatmentContent: _ssCtrls['treatmentContent']!.text.trim(),
      part: _ssCtrls['part']!.text.trim(),
      detailPart: _ssCtrls['detailPart']!.text.trim(),
      phenomenon: _ssCtrls['phenomenon']!.text.trim(),
      phenomenonNote: _ssCtrls['phenomenonNote']!.text.trim(),
      cause: _ssCtrls['cause']!.text.trim(),
      treatmentContent2: _ssCtrls['treatmentContent2']!.text.trim(),
      part1: _ssCtrls['part1']!.text.trim(),
      part2: _ssCtrls['part2']!.text.trim(),
      part3: _ssCtrls['part3']!.text.trim(),
      part4: _ssCtrls['part4']!.text.trim(),
      part5: _ssCtrls['part5']!.text.trim(),
      remarks: _ssCtrls['remarks']!.text.trim(),
      storeNumber: _ssCtrls['storeNumber']!.text.trim(),
      scannedAddress: _ssCtrls['scannedAddress']!.text.trim(),
      scannedTel: _ssCtrls['scannedTel']!.text.trim(),
      machineNo: _ssCtrls['machineNo']!.text.trim(),
      assetNo: _ssCtrls['assetNo']!.text.trim(),
      barcode: _ssCtrls['barcode']!.text.trim(),
      deliveryDate: _ssCtrls['deliveryDate']!.text.trim(),
      workerName: _ssCtrls['workerName']!.text.trim(),
      recoveryAmount: _ssCtrls['recoveryAmount']!.text.trim(),
    );
  }

  /// 作業報告書をカメラで撮影し、AI(Azure Document Intelligence)で
  /// 自動抽出する。ユーザーが確認・修正画面で内容をチェック・修正した後、
  /// 「反映」した項目のみをこの画面の各フィールドへ書き込む。
  /// AIの解析結果を確認なしにそのまま登録することは絶対に行わない。
  ///
  /// 【docType対応】サーバー側(nakano-scan-proxy)がSE用・プロワン用の
  /// 2モデルを並行解析し、confidence比較で書式を自動判定する。
  /// - SEDocType: 従来通り23項目をコンビニ側システム入力控えへ反映
  /// - ProWanDocType: 【設計転換・2026-08-28】案件管理番号(伝票No)を
  ///   含む17項目(kProWanScanFieldDefinitions参照。技術者氏名は
  ///   日報作成者と重複するため2026-08-28にOCR対象から除外)を、
  ///   CSV照合を介さず_applyProWanScanResult()で各フォーム欄へ直接反映する
  Future<void> _scanReport() async {
    final confirmed = await DocumentScanFlow.run(context);
    if (confirmed == null || !mounted) return;

    final docType = confirmed['_docType'] ?? '';
    if (docType == 'ProWanDocType') {
      await _applyProWanScanResult(confirmed);
      return;
    }

    setState(() {
      // コンビニ側システム入力控えセクションへ反映
      if ((confirmed['StoreNumber'] ?? '').isNotEmpty) {
        _ssCtrls['storeNumber']!.text = confirmed['StoreNumber']!;
      }
      if ((confirmed['Address'] ?? '').isNotEmpty) {
        _ssCtrls['scannedAddress']!.text = confirmed['Address']!;
      }
      if ((confirmed['Tel'] ?? '').isNotEmpty) {
        _ssCtrls['scannedTel']!.text = confirmed['Tel']!;
      }
      if ((confirmed['EquipmentName'] ?? '').isNotEmpty) {
        _ssCtrls['equipmentName']!.text = confirmed['EquipmentName']!;
      }
      if ((confirmed['MakerName'] ?? '').isNotEmpty) {
        _ssCtrls['maker']!.text = confirmed['MakerName']!;
      }
      if ((confirmed['ModelNo'] ?? '').isNotEmpty) {
        _ssCtrls['modelNumber']!.text = confirmed['ModelNo']!;
      }
      if ((confirmed['MachineNo'] ?? '').isNotEmpty) {
        _ssCtrls['machineNo']!.text = confirmed['MachineNo']!;
      }
      if ((confirmed['AssetNo'] ?? '').isNotEmpty) {
        _ssCtrls['assetNo']!.text = confirmed['AssetNo']!;
      }
      if ((confirmed['Barcode'] ?? '').isNotEmpty) {
        _ssCtrls['barcode']!.text = confirmed['Barcode']!;
      }
      if ((confirmed['DeliveryDate'] ?? '').isNotEmpty) {
        _ssCtrls['deliveryDate']!.text = confirmed['DeliveryDate']!;
      }
      if ((confirmed['PartCategory'] ?? '').isNotEmpty) {
        _ssCtrls['part']!.text = confirmed['PartCategory']!;
      }
      if ((confirmed['PartDetail'] ?? '').isNotEmpty) {
        _ssCtrls['detailPart']!.text = confirmed['PartDetail']!;
      }
      if ((confirmed['Symptom'] ?? '').isNotEmpty) {
        _ssCtrls['phenomenon']!.text = confirmed['Symptom']!;
      }
      if ((confirmed['SymptomDetail'] ?? '').isNotEmpty) {
        _ssCtrls['phenomenonNote']!.text = confirmed['SymptomDetail']!;
      }
      if ((confirmed['Cause'] ?? '').isNotEmpty) {
        _ssCtrls['cause']!.text = confirmed['Cause']!;
      }
      if ((confirmed['ActionContent'] ?? '').isNotEmpty) {
        _ssCtrls['treatmentContent']!.text = confirmed['ActionContent']!;
      }
      // 【方針】作業者氏名はOCR対象外(kScanFieldDefinitionsから除外済み)。
      // 従業員マスタからの選択+手入力併用欄(_buildWorkerNameField)で管理する。
      // 冷媒回収量・充填量(半角英数のみ許可のバリデーション対象欄)
      if ((confirmed['RecoveryAmountKg'] ?? '').isNotEmpty) {
        _ssCtrls['recoveryAmount']!.text = confirmed['RecoveryAmountKg']!;
      }
      if ((confirmed['ChargeAmountKg'] ?? '').isNotEmpty) {
        _ssCtrls['refrigerantAmount']!.text = confirmed['ChargeAmountKg']!;
      }
      // 訪問日・作業開始/終了時刻(パースできた場合のみ反映)
      final visitDateStr = confirmed['VisitDate'];
      if (visitDateStr != null && visitDateStr.isNotEmpty) {
        final parsed = _tryParseDate(visitDateStr);
        if (parsed != null) _visitDate = parsed;
      }
      final startTimeStr = confirmed['StartTime'];
      if (startTimeStr != null && startTimeStr.isNotEmpty) {
        final parsed = _tryParseTime(startTimeStr);
        if (parsed != null) _startTime = parsed;
      }
      final endTimeStr = confirmed['EndTime'];
      if (endTimeStr != null && endTimeStr.isNotEmpty) {
        final parsed = _tryParseTime(endTimeStr);
        if (parsed != null) _endTime = parsed;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('スキャン内容をフォームへ反映しました。他の項目も確認してください。')),
      );
    }
  }

  /// プロワン文書と判定されたスキャン結果を反映する。
  ///
  /// 【設計転換・2026-08-28】従来はスキャンで読み取った伝票NoをキーにCSV
  /// キャッシュ(prowan_job_cache)と照合し、顧客名・作業内容等を反映していた。
  /// しかし、現場の日報入力(スキャン)は事務所側のCSVエクスポートより
  /// 時系列的に先行するため、リアルタイムのCSV照合は原理的に成立しない
  /// ことが判明した。作業報告書PDF自体に必要な項目(17項目、
  /// kProWanScanFieldDefinitions参照)が全て印字されているため、CSV照合を
  /// 廃止し、AI-OCRが読み取った17項目を直接各フォーム欄へマッピングする
  /// 方式に変更した。
  ///
  /// 【マッピング先】
  /// - ProWanRefNumber -> _proWanCtrl(伝票No)
  /// - StoreName -> _storeFreeTextCtrl(店舗選択が未確定の場合のみ。
  ///   店舗マスタから選択済みの場合は自由入力欄へは反映しない)
  /// - ClientName/ReceiptDate/Department/SystemNumber/CaseNo/
  ///   EquipmentLocation/RequestContent/Cause/VisitResult/FuturePlan
  ///   -> _pwCtrls(ProWanReportDetailの11項目)。技術者氏名(technicianName)
  ///   は日報作成者(authorName)と重複するためOCR自動反映の対象外とし、
  ///   手入力専用欄として残す。
  /// - ModelSerial -> _equipmentModelCtrl(機器型番、WorkReport本体と共通)
  /// - WorkContent -> _workContentCtrl(作業内容、WorkReport本体と共通)
  /// - RefrigerantType/RefrigerantAmount -> _nonSeRefrigerantTypeCtrl/
  ///   _nonSeRefrigerantAmountCtrl(WorkReport本体と共通、重複を避けて
  ///   ProWanReportDetail側には持たない)
  /// - WorkStartDate -> _visitDate(訪問日。パース可能な場合のみ反映)
  ///
  /// いずれも、すでに人間が手入力確定(manual)済みのフィールドは
  /// 上書きしない(前セッションで確定した設計方針を維持)。
  Future<void> _applyProWanScanResult(Map<String, String> confirmed) async {
    final refNumber = (confirmed['ProWanRefNumber'] ?? '').trim();
    if (refNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('案件管理番号(伝票No)を読み取れませんでした。他の項目は反映済みです。')),
        );
      }
    }

    int filledCount = 0;

    void applyIfNotManual(
      String fieldKey,
      TextEditingController ctrl,
      String? value,
    ) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return;
      if (_fieldSources[fieldKey] == 'manual') return;
      ctrl.text = v;
      _fieldSources[fieldKey] = 'auto';
      filledCount++;
    }

    setState(() {
      applyIfNotManual('pro_wan_ref_number', _proWanCtrl, refNumber);

      // 店舗名: 店舗マスタから選択済みの場合は自由入力欄を上書きしない
      // (誤った店舗情報での上書きを避けるため)。
      final storeName = (confirmed['StoreName'] ?? '').trim();
      if (_selectedStoreId == null) {
        applyIfNotManual('client_name', _storeFreeTextCtrl, storeName);
      }

      // WorkReport本体と共通のフィールド(重複統合)
      applyIfNotManual(
        'equipment_model',
        _equipmentModelCtrl,
        confirmed['ModelSerial'],
      );
      applyIfNotManual(
        'work_content',
        _workContentCtrl,
        confirmed['WorkContent'],
      );
      applyIfNotManual(
        'non_se_refrigerant_type',
        _nonSeRefrigerantTypeCtrl,
        confirmed['RefrigerantType'],
      );
      applyIfNotManual(
        'non_se_refrigerant_amount_kg',
        _nonSeRefrigerantAmountCtrl,
        confirmed['RefrigerantAmount'],
      );

      // ProWanReportDetail(11項目)へのマッピング。
      // 【2026-08-28】technicianName(技術者氏名)はOCR対象から除外したため
      // ここから除いた。日報作成者(authorName)と重複するため、この欄は
      // 手入力(OCR以外の経路でのみ入力される)専用フィールドとして残す。
      const ocrKeyToPwCtrlKey = {
        'ClientName': 'clientName',
        'ReceiptDate': 'receiptDate',
        'Department': 'department',
        'SystemNumber': 'systemNumber',
        'CaseNo': 'caseNo',
        'EquipmentLocation': 'equipmentLocation',
        'RequestContent': 'requestContent',
        'Cause': 'cause',
        'VisitResult': 'visitResult',
        'FuturePlan': 'futurePlan',
      };
      for (final ocrEntry in ocrKeyToPwCtrlKey.entries) {
        final pwCtrlKey = ocrEntry.value;
        final snakeKey = _pwFieldKeyMap[pwCtrlKey]!;
        applyIfNotManual(
          'pro_wan_report_detail.$snakeKey',
          _pwCtrls[pwCtrlKey]!,
          confirmed[ocrEntry.key],
        );
      }

      // 作業開始日 -> 訪問日(パース可能な場合のみ)。
      // 【2026-08-28】ScanConfirmScreen側で必須確認チェックボックスに
      // チェックが入るまでこの値はそもそも呼び出し元へ返らない
      // (_hasUnconfirmedRequiredFieldでボタン自体が無効化される)ため、
      // ここに来る値は既にユーザーが目視確認済みのもの。ただし訪問日欄を
      // 既に手入力で確定(manual)済みの場合は、他の自動入力フィールドと
      // 同様に上書きしない(_markFieldEditedManuallyで手動修正を検知したら
      // 'manual'になる。日付ピッカーの変更検知は_pickDate側で行う)。
      if (_fieldSources['visit_date'] != 'manual') {
        final workStartDate = (confirmed['WorkStartDate'] ?? '').trim();
        if (workStartDate.isNotEmpty) {
          final parsed = _tryParseDate(workStartDate);
          if (parsed != null) {
            _visitDate = parsed;
            _fieldSources['visit_date'] = 'auto';
            filledCount++;
          }
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filledCount > 0
                ? '作業報告書から$filledCount件の項目を自動入力しました。内容を確認してください。'
                : '読み取れた項目がありませんでした。各項目を手入力してください。',
          ),
        ),
      );
    }
  }

  /// "2025/8/15" のようなAI抽出テキストをDateTimeへ変換する(失敗時はnull)。
  ///
  /// 【共通化・2026-08-28】実装本体は utils/scan_date_parser.dart の
  /// tryParseScanDate() に切り出した(月末チェック機能
  /// submission_check_screen.dart でも同じロジックが必要になったため)。
  /// このメソッドは既存呼び出し箇所を変更せずに済ませるための薄いラッパー。
  DateTime? _tryParseDate(String text) => tryParseScanDate(text);

  /// "16:00" や "~17:00" のようなAI抽出テキストをTimeOfDayへ変換する(失敗時はnull)。
  TimeOfDay? _tryParseTime(String text) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text.trim());
    if (match == null) return null;
    try {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  /// 写真を選択し、Firebase StorageへアップロードしてダウンロードURLを
  /// _photoPathsに追加する。
  ///
  /// 【不具合修正・2026-08】従来はimage_pickerが返すローカルファイルパス
  /// (file.path)をそのまま保存していたため、撮影した端末以外では画像が
  /// 一切表示できなかった。Firebase Storageへアップロードし、誰の端末
  /// からでも参照可能なダウンロードURLを保存する方式に変更。
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写真の選択に失敗しました(Web環境では制限があります)')),
        );
      }
      return;
    }
    if (file == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await PhotoUploadService.instance.uploadPhoto(
        file: file,
        reportId: _reportId,
      );
      if (mounted) {
        setState(() {
          _photoPaths.add(url);
          _isUploadingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('写真のアップロードに失敗しました: $e')));
      }
    }
  }

  /// 写真を一覧から削除する。アップロード済み(URL形式)の場合は
  /// Storage側の実体も削除し、ゴミファイルが残らないようにする。
  Future<void> _removePhotoAt(int index) async {
    final removed = _photoPaths.removeAt(index);
    setState(() {});
    await PhotoUploadService.instance.deletePhoto(removed);
  }

  /// 【不具合修正・2026-09・Bug①対応】必須項目が未入力のまま保存された際、
  /// 画面上に何の通知もなく処理が止まってしまう「サイレントバグ」を防ぐため、
  /// (1)エラー内容を明示するSnackBarを表示し、(2)最初に見つかった
  /// 未入力の必須欄まで自動スクロールしてフォーカスを移す。
  ///
  /// 対象キーは画面上での出現順(上から下)に列挙する。表示条件によって
  /// そもそも画面に存在しない項目のキーは`currentState`がnullになるため、
  /// 自然にスキップされる。
  void _scrollToFirstInvalidField() {
    final candidates = [
      _workContentFieldKey,
      _proWanRefFieldKey,
      _seReceiptNumberFieldKey,
      _seCustomerReceiptNumberFieldKey,
      _seRefrigerantTypeFieldKey,
      _seRefrigerantAmountFieldKey,
      _nonSeRefrigerantTypeFieldKey,
      _nonSeRefrigerantAmountFieldKey,
    ];
    for (final key in candidates) {
      final state = key.currentState;
      if (state != null && state.hasError) {
        Scrollable.ensureVisible(
          state.context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        // フォーカスも合わせて当てることで、入力し直すべき欄が
        // どこかを視覚的にも明確にする(スクロールだけでは
        // 画面が広い場合にどの欄か一瞬わかりにくいため)。
        FocusScope.of(state.context).requestFocus(FocusNode());
        return;
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return; // 多重押下防止

    if (!_formKey.currentState!.validate()) {
      // 【不具合修正・2026-09】従来はここで無言のreturnとなり、
      // どの項目が未入力なのか・保存が失敗したこと自体すら
      // 入力者に伝わらなかった(Bug①)。明確な通知+該当欄への
      // 自動スクロールで、入力者が確実に気づける設計にする。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('入力に不備があります。赤字の項目をご確認ください(保存されていません)'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // ビルド直後は該当欄のcontextがまだ取得できない場合があるため、
      // 1フレーム後に実行する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFirstInvalidField();
      });
      return;
    }

    final appState = context.read<AppState>();
    final user = appState.currentUser;
    if (user == null) return;

    final start = _combine(_visitDate, _startTime);
    var end = _combine(_visitDate, _endTime);
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }

    // 店舗マスタから選択されていればその店名、なければ自由入力欄の値をclientNameとする
    final resolvedClientName = _selectedStoreId != null
        ? (appState.getStoreById(_selectedStoreId!)?.name ?? '')
        : _storeFreeTextCtrl.text.trim();

    if (!_responseType.isBackOffice &&
        _selectedStoreId == null &&
        resolvedClientName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('店舗をリストから選択するか、店舗名を自由入力してください')),
      );
      return;
    }

    // 【設計転換・2026-08-28】プロワン管轄案件専用の案件詳細
    // (店舗住所・得意先名・受付日・部門・系統番号・ケースNo・修理機器・場所・
    // ご依頼内容・原因・訪問結果・今後の予定・技術者氏名)を_pwCtrlsから構築する。
    final pwDetail = ProWanReportDetail(
      storeAddress: _pwCtrls['storeAddress']!.text.trim(),
      clientName: _pwCtrls['clientName']!.text.trim(),
      receiptDate: _pwCtrls['receiptDate']!.text.trim(),
      department: _pwCtrls['department']!.text.trim(),
      systemNumber: _pwCtrls['systemNumber']!.text.trim(),
      caseNo: _pwCtrls['caseNo']!.text.trim(),
      equipmentLocation: _pwCtrls['equipmentLocation']!.text.trim(),
      requestContent: _pwCtrls['requestContent']!.text.trim(),
      cause: _pwCtrls['cause']!.text.trim(),
      visitResult: _pwCtrls['visitResult']!.text.trim(),
      futurePlan: _pwCtrls['futurePlan']!.text.trim(),
      technicianName: _pwCtrls['technicianName']!.text.trim(),
    );

    // 【不具合修正・2026-09・Bug①付随対応】従来はここから下のFirestore
    // 書き込み処理にtry/catchが一切なく、通信エラー等で例外が発生した場合、
    // 画面には何も表示されずに処理が止まる(=保存できていないのに
    // ユーザーには失敗が伝わらない)サイレントバグの温床になっていた。
    // 明示的にエラーを捕捉し、ユーザーに再試行を促す。
    setState(() => _isSaving = true);
    try {
      if (isEditing) {
        final r = widget.existing!;
        r.coWorkerIds = List<String>.from(_selectedCoWorkerIds);
        r.storeId = _selectedStoreId;
        r.clientName = resolvedClientName;
        r.visitDate = _visitDate;
        r.startTime = start;
        r.endTime = end;
        r.workContent = _workContentCtrl.text.trim();
        r.equipmentModel = _equipmentModelCtrl.text.trim();
        r.responseType = _responseType;
        r.partsUsed = _parts;
        r.photoPaths = _photoPaths;
        r.notes = _notesCtrl.text.trim();
        r.successPoints = _successCtrl.text.trim();
        r.issuesPoints = _issuesCtrl.text.trim();
        r.tags = _tags;
        r.proWanRefNumber = _proWanCtrl.text.trim();
        r.storeSystemReportCopy = _buildStoreSystemReport();
        r.nonSeRefrigerantType = _nonSeRefrigerantTypeCtrl.text.trim();
        r.nonSeRefrigerantAmountKg = _nonSeRefrigerantAmountCtrl.text.trim();
        r.proWanReportDetail = pwDetail;
        r.caseRolePreset = _caseRolePreset ?? '';
        r.caseRoleNote = _caseRoleNoteCtrl.text.trim();
        r.fieldSources = _fieldSources;
        r.manualReviewNeeded = _manualReviewNeeded;
        r.matchedCacheJobNumber = _matchedCacheJobNumber;
        // 【代筆編集の記録・2026-08導入】本人以外(一般管理者以上)が編集した
        // 場合のみ、誰が・いつ代筆したかを記録する。現場の入力もれ・訂正対応の
        // ための権限拡大であり、無記録での代筆を避けるための監査証跡。
        // 本人による編集の場合は既存の記録(あれば)をそのまま維持する
        // (本人が後から見返して編集しても、過去の代筆履歴を消さないため)。
        if (r.authorId != user.id) {
          r.lastEditedByAdminId = user.id;
          r.lastEditedByAdminName = user.name;
          r.lastEditedByAdminAt = DateTime.now();
        }
        await appState.updateReport(r);
      } else {
        final report = WorkReport(
          id: _reportId,
          authorId: user.id,
          authorName: user.name,
          coWorkerIds: List<String>.from(_selectedCoWorkerIds),
          storeId: _selectedStoreId,
          clientName: resolvedClientName,
          visitDate: _visitDate,
          startTime: start,
          endTime: end,
          workContent: _workContentCtrl.text.trim(),
          equipmentModel: _equipmentModelCtrl.text.trim(),
          responseType: _responseType,
          partsUsed: _parts,
          photoPaths: _photoPaths,
          notes: _notesCtrl.text.trim(),
          successPoints: _successCtrl.text.trim(),
          issuesPoints: _issuesCtrl.text.trim(),
          tags: _tags,
          proWanRefNumber: _proWanCtrl.text.trim(),
          storeSystemReportCopy: _buildStoreSystemReport(),
          nonSeRefrigerantType: _nonSeRefrigerantTypeCtrl.text.trim(),
          nonSeRefrigerantAmountKg: _nonSeRefrigerantAmountCtrl.text.trim(),
          proWanReportDetail: pwDetail,
          caseRolePreset: _caseRolePreset ?? '',
          caseRoleNote: _caseRoleNoteCtrl.text.trim(),
          fieldSources: _fieldSources,
          manualReviewNeeded: _manualReviewNeeded,
          matchedCacheJobNumber: _matchedCacheJobNumber,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await appState.addReport(report);
      }

      if (mounted) {
        // 【不具合対応・2026-08-31】電波不良でサーバーへの送信が保留中の場合、
        // 保存自体は成功していても本人が気づけるよう注意文言を添える。
        final hasPending = appState.totalPendingCount > 0;
        final baseMsg = isEditing ? '日報を更新しました' : '日報を保存しました';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasPending ? '$baseMsg(電波状況により送信待ちです。ホーム画面をご確認ください)' : baseMsg,
            ),
            duration: Duration(seconds: hasPending ? 5 : 3),
            backgroundColor: hasPending ? Colors.orange.shade800 : null,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 【不具合修正・2026-09・Bug①付随対応】保存処理中の例外(通信断・
      // 権限エラー等)を捕捉し、画面を閉じずにエラーを明示する。
      // 従来はここで例外が握られずに画面遷移も起きない状態のまま
      // 静かに失敗しており、入力者は保存できたのか分からなかった。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました。もう一度お試しください($e)'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy年M月d日 (E)', 'ja_JP');
    final appState = context.watch<AppState>();
    // 【代筆編集の記録・2026-08導入】一般管理者以上が本人以外の日報を
    // 編集している場合、その旨を明示するための判定(入力もれ対応用)。
    final isAdminEditingOthersReport =
        isEditing && widget.existing!.authorId != appState.currentUser?.id;
    final selectedStore = _selectedStoreId != null
        ? appState.getStoreById(_selectedStoreId!)
        : null;
    final isSEStore = selectedStore?.isSE ?? false;
    // コンビニ側システム入力控えは、SE店舗かつ修理・故障対応の場合のみ必須(マニュアルの入力ルールに準拠)。
    final isRepairOrBreakdown =
        _responseType == ResponseType.repair ||
        _responseType == ResponseType.breakdown;
    final showStoreSystemSection = isSEStore && isRepairOrBreakdown;
    // プロワン管轄案件(SE店舗以外)の現場作業では、請求業務効率化のため
    // 冷媒種類・冷媒量の入力を必須とする(バックオフィス業務は対象外)。
    final showNonSeRefrigerantSection =
        !isSEStore && !_responseType.isBackOffice;
    // 【不具合修正・2026-08】作業報告書スキャン機能はSE用・プロワン用の両方の
    // 書式をサーバー側で自動判別する設計(document_scan_service.dart /
    // _scanReport()内のdocType分岐)になっているが、入口カードの表示条件が
    // SE店舗限定になっていたため、プロワン管轄案件(SE以外)ではボタン自体が
    // 表示されず、実装済みの機能に辿り着けなかった。
    // プロワン管轄案件でも「作業報告書(プロワン用)」をスキャンすれば
    // 伝票Noを自動読み取り→CSVキャッシュ照合まで自動実行されるため、
    // 修理・故障対応であれば店舗区分を問わずスキャン入口を表示する。
    final showScanEntryCard = isRepairOrBreakdown;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '日報編集' : '日報作成')),
      body: Form(
        key: _formKey,
        child: ListView(
          // 注意: ListViewは既定では画面外の子要素を遅延構築するため、
          // スクロールして隠れているTextFormFieldがForm.validate()実行時に
          // まだビルドされておらず、必須バリデーションが素通りしてしまう不具合があった。
          // cacheExtentを大きく設定し全フィールドを事前構築することで、
          // 保存時に全項目のバリデーションが確実に実行されるようにする。
          cacheExtent: 5000,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (isAdminEditingOthersReport)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 20,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '管理者権限で ${widget.existing!.authorName} さんの日報を'
                        '代わりに編集しています。入力もれ・訂正対応以外での'
                        '内容変更は控えてください。この編集は記録され、'
                        '日報詳細画面に代筆履歴として表示されます。',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _SectionTitle('基本情報'),
            const SizedBox(height: 8),
            // 【2026-08 導線改善】まず「何の作業か」(対応区分)を最初に選んで
            // もらう方が日報として自然な入力順のため、対応区分の選択を
            // 店舗・訪問日より前に配置する。事務・現場事務・倉庫作業・環境整備
            // (バックオフィス業務)を選んだ場合は、後続の店舗選択欄が
            // 「対象・場所(任意)」の自由入力欄に切り替わる。
            DropdownButtonFormField<ResponseType>(
              initialValue: _responseType,
              decoration: const InputDecoration(
                labelText: '対応区分',
                prefixIcon: Icon(Icons.category),
              ),
              items: ResponseType.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            t == ResponseType.environmentalMaintenance
                                ? Icons.cleaning_services
                                : t.isBackOffice
                                ? Icons.apartment
                                : Icons.build_circle_outlined,
                            size: 16,
                            color: responseTypeColor(t.label),
                          ),
                          const SizedBox(width: 8),
                          Text(t.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _responseType = v!),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _responseType.isBackOffice
                    ? '事務・現場事務・倉庫作業(在庫管理含む)・環境整備(清掃・整理整頓等)は、'
                          '店舗・案件に紐づかない社内業務として記録できます。'
                          '機器型番・プロワン管理番号の入力は不要です(任意)。'
                    : '現場でのお客様対応(定期点検・故障対応・修理・新設)は、'
                          '下の店舗・案件の選択欄で対象を指定してください。'
                          '事務作業や倉庫整理・環境整備など、店舗に紐づかない社内業務の'
                          '場合は、上のプルダウンで該当する区分を選んでください。',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 12),
            if (_responseType.isBackOffice)
              _buildField(
                controller: _clientNameCtrl,
                label: '対象・場所(任意)',
                icon: Icons.apartment,
                fieldKey: 'client_name',
              )
            else
              StorePickerField(
                selectedStoreId: _selectedStoreId,
                freeTextController: _storeFreeTextCtrl,
                onStoreSelected: (Store s) {
                  setState(() {
                    _selectedStoreId = s.id;
                    _storeFreeTextCtrl.clear();
                  });
                },
                onFreeTextChanged: (v) {
                  setState(() {
                    if (v.trim().isNotEmpty) _selectedStoreId = null;
                  });
                },
              ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '訪問日',
                  prefixIcon: const Icon(Icons.calendar_today),
                  // 【2026-08-28】作業開始日(WorkStartDate)からのスキャン
                  // 自動反映は、確認画面で必ず目視確認チェックを経てから
                  // ここに来る値だが、AI抽出自体の精度はまだ低い
                  // (再学習直後confidence=0.346)。反映済みであることが
                  // 一目でわかるよう、他のスキャン自動入力欄と同じ緑バッジを
                  // 表示し、必ずタップして日付を再確認する意識付けをする。
                  helperText: _fieldSources['visit_date'] == 'auto'
                      ? 'スキャンで自動反映済み(必ず実物と照合してください)'
                      : null,
                  helperStyle: _fieldSources['visit_date'] == 'auto'
                      ? TextStyle(color: Colors.green.shade700, fontSize: 11)
                      : null,
                  suffixIcon: _fieldSources['visit_date'] == 'auto'
                      ? Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.green.shade600,
                        )
                      : null,
                ),
                child: Text(dateFmt.format(_visitDate)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(true),
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '開始時刻',
                        prefixIcon: Icon(Icons.play_arrow),
                      ),
                      child: Text(_startTime.format(context)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(false),
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '終了時刻',
                        prefixIcon: Icon(Icons.stop),
                      ),
                      child: Text(_endTime.format(context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCoWorkerField(),
            const SizedBox(height: 12),
            _buildCaseRoleField(),

            // 【2026-08 導線改善】修理・故障対応の場合、他の項目を入力する前に
            // まず「作業報告書をお持ちならスキャン」という導線を最上部付近に
            // 提示する。SE店舗・プロワン管轄案件のどちらの書式もサーバー側で
            // 自動判別されるため、店舗区分を問わず表示する。
            // ここでスキャンしておけば、下の各項目のうちプロワン側システムと
            // 重複する部分(顧客名・作業内容・機器型番・冷媒情報等)は自動入力
            // され、手入力が必要なのは重複しない項目だけになる。
            if (showScanEntryCard) _buildScanEntryCard(isSEStore),

            // 【2026-08 導線改善】ナレッジ共有はこのアプリ独自の価値であり、
            // プロワン側システムには存在しない項目。スキャンボタンのすぐ下に
            // 配置することで、まずスキャンで重複項目を済ませてから、
            // このアプリでしか記録できないナレッジ共有への積極的な入力を促す。
            const SizedBox(height: 20),
            _SectionTitle('ナレッジ共有(社内評価・マニュアル反映用)'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ここはプロワンや店舗側システムには無い、このアプリ独自の項目です。'
                      '社内でのノウハウ共有・人事評価・現場マニュアル更新の元データとして'
                      '活用されますので、積極的にご記入ください。',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _successCtrl,
              label: 'うまくいったこと・工夫した点',
              icon: Icons.thumb_up_alt_outlined,
              maxLines: 3,
              iconColor: AppColors.success,
              enableVoice: true,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _issuesCtrl,
              label: '課題・失敗・改善点',
              icon: Icons.report_problem_outlined,
              maxLines: 3,
              iconColor: AppColors.warning,
              enableVoice: true,
            ),
            const SizedBox(height: 12),
            // タグ
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputCtrl,
                    decoration: const InputDecoration(
                      labelText: 'タグ(症状・機種等)',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _tags
                      .map(
                        (t) => Chip(
                          label: Text(t),
                          onDeleted: () => setState(() => _tags.remove(t)),
                        ),
                      )
                      .toList(),
                ),
              ),

            const SizedBox(height: 20),
            _SectionTitle(_responseType.isBackOffice ? '業務内容' : '作業内容'),
            const SizedBox(height: 8),
            _buildField(
              controller: _workContentCtrl,
              label: _responseType.isBackOffice ? '業務内容' : '作業内容',
              icon: Icons.build,
              maxLines: 4,
              enableVoice: true,
              fieldKey: 'work_content',
              formFieldKey: _workContentFieldKey,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '必須項目です' : null,
            ),
            if (!_responseType.isBackOffice)
              _buildWorkContentSupport(isSEStore),
            const SizedBox(height: 12),
            _buildField(
              controller: _equipmentModelCtrl,
              label: _responseType.isBackOffice ? '機器型番(任意)' : '機器型番(プロワン参照)',
              icon: Icons.qr_code,
              hint: '例: 冷凍機型番 XR-500',
              fieldKey: 'equipment_model',
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _proWanCtrl,
              label: !isSEStore && !_responseType.isBackOffice
                  ? 'プロワン管理番号(伝票No・必須)'
                  : 'プロワン管理番号(伝票No・任意)',
              icon: Icons.numbers,
              hint: 'プロワン側で管理している案件番号(伝票Noと同じ)',
              fieldKey: 'pro_wan_ref_number',
              formFieldKey: _proWanRefFieldKey,
              // 【2026-09追加】プロワン管轄案件(SE店舗以外)では、後日SDRS等の
              // 請求明細・記入漏れチェックとの突合キーとなるため必須とする。
              // SE店舗案件は弊社受付No/お客様受付Noが突合キーの役割を担うため
              // ここでは任意のままとする。
              validator: (!isSEStore && !_responseType.isBackOffice)
                  ? (v) => (v == null || v.trim().isEmpty) ? '必須項目です' : null
                  : null,
            ),
            _buildCaseGroupingHint(_proWanCtrl),
            const SizedBox(height: 12),

            if (showNonSeRefrigerantSection) _buildNonSeRefrigerantSection(),
            if (showNonSeRefrigerantSection) _buildProWanReportDetailSection(),

            // 使用部品
            Row(
              children: [
                const Text(
                  '使用部品',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addPart,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            if (_parts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '使用部品はありません',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              )
            else
              ..._parts.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final hasPartNumber =
                    p.partNumber != null && p.partNumber!.isNotEmpty;
                final hasNote = p.note != null && p.note!.isNotEmpty;
                final subtitleText = [
                  if (hasPartNumber) '図番: ${p.partNumber}',
                  if (hasNote) p.note!,
                ].join(' / ');
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2, size: 20),
                    title: Text('${p.name} × ${p.quantity}'),
                    subtitle: subtitleText.isNotEmpty
                        ? Text(subtitleText)
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _parts.removeAt(i)),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),
            // 写真(現場・作業内容の補完情報用。ここでの撮影・選択内容はAI解析されない)
            Row(
              children: [
                const Text('写真', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isUploadingPhoto ? null : _pickPhoto,
                  icon: _isUploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo, size: 18),
                  label: Text(_isUploadingPhoto ? 'アップロード中...' : '追加'),
                ),
              ],
            ),
            if (showStoreSystemSection)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  '※ ここは現場写真の保存用です。SE作業報告書の自動読み取りは'
                  '上の「作業報告書をスキャンしてAIで自動入力」ボタンをご利用ください。',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
            if (_photoPaths.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photoPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final url = _photoPaths[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 90,
                            height: 90,
                            color: Colors.grey.shade200,
                            child: url.startsWith('http')
                                ? Image.network(
                                    url,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stack) =>
                                        const Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                        ),
                                  )
                                // アップロード前の旧データ(ローカルパスのみ保存されていた
                                // 過去のレコード)は、実体が存在しないため表示できない。
                                : const Icon(
                                    Icons.image_not_supported,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removePhotoAt(i),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            if (showStoreSystemSection) ...[
              const SizedBox(height: 20),
              _SectionTitle('コンビニ側システム入力控え'),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'SE店舗(コンビニ)の修理・故障対応のため、この入力控えは必須です。コンビニ側の業務システムはデータ抽出ができないため、社内保管用にここへ同じ内容を項目ごとに控えとして記録してください。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '受付情報',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _scanReport,
                  icon: const Icon(Icons.document_scanner_outlined),
                  // 画面上部の入口カードでスキャン済みの場合はこちらは「再スキャン」の
                  // 位置づけ(読み取り漏れ・別ページの追加取り込みなどに利用)。
                  label: const Text('作業報告書を(再)スキャンしてAIで自動入力'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  '撮影後、AIの読み取り結果を必ず確認・修正してから反映します。'
                  'まだスキャンしていない場合は、この画面の上部にもスキャン用のボタンがあります。',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['receiptNumber']!,
                label: '弊社受付No.(必須)',
                icon: Icons.confirmation_number_outlined,
                formFieldKey: _seReceiptNumberFieldKey,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '必須項目です' : null,
              ),
              _buildCaseGroupingHint(_ssCtrls['receiptNumber']!),
              const SizedBox(height: 12),
              // 【2026-09追加】コンビニ側システムで発行される「お客様受付No」。
              // SDRSから届く請求明細書等はこの番号で管理されているケースがあり、
              // 後日の突合(記入漏れチェック・請求確認)を確実にするため必須とする。
              _buildField(
                controller: _ssCtrls['customerReceiptNumber']!,
                label: 'お客様受付No.(コンビニ側発行・必須)',
                icon: Icons.confirmation_number,
                hint: 'コンビニ側システムで発行された受付No',
                formFieldKey: _seCustomerReceiptNumberFieldKey,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '必須項目です' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['storeNumber']!,
                label: '店番(スキャン取り込み・任意)',
                icon: Icons.store_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.ac_unit, size: 16, color: Colors.teal.shade800),
                  const SizedBox(width: 6),
                  Text(
                    '冷媒情報(請求業務用・必須)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['refrigerantType']!,
                      label: '冷媒種類',
                      icon: Icons.ac_unit,
                      hint: '例: R410A / NONE',
                      inputFormatters: [_halfWidthAlphaNumFormatter],
                      formFieldKey: _seRefrigerantTypeFieldKey,
                      validator: _halfWidthAlphaNumValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['refrigerantAmount']!,
                      label: '充填量(kg)',
                      icon: Icons.opacity,
                      hint: '例: 1.5 / 0',
                      inputFormatters: [_halfWidthAlphaNumFormatter],
                      formFieldKey: _seRefrigerantAmountFieldKey,
                      validator: _halfWidthAlphaNumValidator,
                    ),
                  ),
                ],
              ),
              _buildRefrigerantNotice(
                '半角英数のみ入力できます。充填していない場合は「冷媒種類」に'
                '「NONE」、「充填量」に「0」と入力してください。',
              ),
              const SizedBox(height: 16),
              Text(
                '依頼・設備情報',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildField(
                controller: _ssCtrls['requestContent']!,
                label: '依頼内容',
                icon: Icons.assignment_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['scannedAddress']!,
                label: '住所(スキャン取り込み・任意)',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['scannedTel']!,
                label: 'TEL(スキャン取り込み・任意)',
                icon: Icons.call_outlined,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['equipmentName']!,
                label: '設備名称',
                icon: Icons.kitchen,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['maker']!,
                      label: 'メーカー',
                      icon: Icons.factory_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['modelNumber']!,
                      label: '型式',
                      icon: Icons.qr_code_2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['machineNo']!,
                      label: '機番(任意)',
                      icon: Icons.confirmation_num_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['assetNo']!,
                      label: '資産管理No(任意)',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['barcode']!,
                      label: 'ランダムバーコード(任意)',
                      icon: Icons.qr_code_scanner_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['deliveryDate']!,
                      label: '納品日(任意)',
                      icon: Icons.local_shipping_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildWorkerNameField(),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['recoveryAmount']!,
                label: '冷媒回収量(kg・任意)',
                icon: Icons.opacity,
              ),
              const SizedBox(height: 16),
              Text(
                '事象・原因・処置',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['part']!,
                      label: '部位',
                      icon: Icons.build_circle_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['detailPart']!,
                      label: '詳細部位',
                      icon: Icons.build_circle_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['phenomenon']!,
                label: '事象',
                icon: Icons.report_gmailerrorred_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['phenomenonNote']!,
                label: '事象補足',
                icon: Icons.notes_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['cause']!,
                label: '原因',
                icon: Icons.psychology_alt_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['treatmentContent']!,
                label: '処置内容',
                icon: Icons.handyman_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['treatmentContent2']!,
                label: '処置内容2(任意)',
                icon: Icons.handyman_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
              const SizedBox(height: 16),
              Text(
                '交換部品(コンビニ側システム登録用・任意)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildField(
                controller: _ssCtrls['part1']!,
                label: '部品1',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _ssCtrls['part2']!,
                label: '部品2',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _ssCtrls['part3']!,
                label: '部品3',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _ssCtrls['part4']!,
                label: '部品4',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _ssCtrls['part5']!,
                label: '部品5',
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _ssCtrls['remarks']!,
                label: '備考(コンビニ側システム用)',
                icon: Icons.sticky_note_2_outlined,
                maxLines: 2,
                enableVoice: true,
              ),
            ], // showStoreSystemSection

            const SizedBox(height: 20),
            _SectionTitle('備考'),
            const SizedBox(height: 8),
            _buildField(
              controller: _notesCtrl,
              label: '備考',
              icon: Icons.notes,
              maxLines: 3,
            ),

            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving ? '保存中...' : (isEditing ? '更新する' : '日報を保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 【案件グルーピング機能・2026-08導入】伝票No/受付Noの入力を促す
  /// ソフトな確認バッジ。
  ///
  /// 【設計方針】この案件番号は保存時にアプリが裏側で自動的に
  /// 「同じ案件の日報」をまとめる際のキーとして使われる(伝票No/受付No
  /// が一致すれば確実にグルーピングされ、空欄の場合は内容の類似度による
  /// 推測グルーピングにフォールバックし精度が落ちる)。
  /// ただし、日報の入力・保存自体を妨げてはならない(A案の前提)ため、
  /// 保存はブロックせず、あくまで「入力した方が案件の照合精度が上がる」
  /// ことを控えめに伝えるのみに留める。
  Widget _buildCaseGroupingHint(TextEditingController controller) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasValue = value.text.trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasValue ? Icons.check_circle_outline : Icons.info_outline,
                size: 13,
                color: hasValue ? AppColors.success : Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  hasValue
                      ? '入力済み: 同じ案件の日報として自動的に照合されます'
                      : '未入力: 空欄のままでも保存できますが、入力すると同じ案件の他の日報と'
                            'より正確に自動でまとめられます',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: hasValue ? AppColors.success : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    Color? iconColor,
    String? Function(String?)? validator,
    bool enableVoice = false,
    List<TextInputFormatter>? inputFormatters,
    // 【重複入力削減・2026-08】スキャン取り込みで自動反映され得るフィールドは
    // fieldKey(_fieldSourcesのキー)を渡すことで、自動反映済みかどうかを
    // 視覚的に示す(プロワン側システムと重複する項目を手入力しなくて済む
    // ことをユーザーに明示するため)。
    String? fieldKey,
    // 【不具合修正・2026-09・Bug①対応】必須項目が未入力のまま保存された際に
    // 該当欄まで自動スクロール・フォーカスするための識別キー。
    // 対象を絞って付与する(全フィールドに付けると却って冗長になるため)。
    GlobalKey<FormFieldState<String>>? formFieldKey,
  }) {
    final isListening = _activeListenController == controller;
    final isAutoFilled = fieldKey != null && _fieldSources[fieldKey] == 'auto';
    return TextFormField(
      key: formFieldKey,
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor),
        alignLabelWithHint: maxLines > 1,
        helperText: isAutoFilled ? 'スキャンで自動反映済み(必要なら修正してください)' : null,
        helperStyle: isAutoFilled
            ? TextStyle(color: Colors.green.shade700, fontSize: 11)
            : null,
        suffixIcon: isAutoFilled
            ? Icon(Icons.auto_awesome, size: 18, color: Colors.green.shade600)
            : (enableVoice
                  ? IconButton(
                      icon: Icon(
                        isListening ? Icons.mic : Icons.mic_none,
                        color: isListening ? Colors.red : Colors.grey.shade500,
                      ),
                      tooltip: isListening ? '音声入力を停止' : '音声入力を開始',
                      onPressed: () => _toggleVoiceInput(controller),
                    )
                  : null),
      ),
    );
  }

  /// 半角英数のみ許可する入力フォーマッタ(コンビニ側システム入力控えの
  /// 冷媒種類・充填量用。コンビニ側の業務システム入力ルールに準拠するため
  /// 全角文字や記号・スペースの混入を防ぐ)。
  static final _halfWidthAlphaNumFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[A-Za-z0-9.]'),
  );

  String? _halfWidthAlphaNumValidator(String? v) {
    if (v == null || v.trim().isEmpty) {
      return '必須項目です(半角英数で入力してください)';
    }
    if (!RegExp(r'^[A-Za-z0-9.]+$').hasMatch(v.trim())) {
      return '半角英数で入力してください';
    }
    return null;
  }

  /// 冷媒充填の入力欄の直下に表示する統一デザインの注意書き。
  ///
  /// 【表記統一・2026-08】以前は「冷媒情報」セクションの説明文の位置が
  /// 画面によって「入力欄の上」「枠で囲って強調」など不統一だった。
  /// 未充填時の入力ルールを見落とされにくくするため、入力欄のすぐ下に
  /// 統一デザイン(注意アイコン+オレンジ系の枠)で表示するようにした。
  Widget _buildRefrigerantNotice(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 15, color: AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade800,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// プロワン管轄案件(SE店舗以外)専用の冷媒種類・冷媒量入力セクション。
  /// 請求業務効率化のため事務からの要望で追加。充填有無に関わらず必須入力
  /// (未充填時は種類「なし」・量「0」を入力してもらう運用)。
  Widget _buildNonSeRefrigerantSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.ac_unit, size: 16, color: Colors.teal.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '冷媒情報(請求業務用・必須)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildField(
                  controller: _nonSeRefrigerantTypeCtrl,
                  label: '冷媒種類',
                  icon: Icons.ac_unit,
                  hint: '例: R410A / なし',
                  fieldKey: 'non_se_refrigerant_type',
                  formFieldKey: _nonSeRefrigerantTypeFieldKey,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '必須項目です(未充填時は「なし」)'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _nonSeRefrigerantAmountCtrl,
                  label: '冷媒量(kg)',
                  icon: Icons.opacity,
                  hint: '例: 1.5 / 0',
                  fieldKey: 'non_se_refrigerant_amount_kg',
                  formFieldKey: _nonSeRefrigerantAmountFieldKey,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '必須項目です(未充填時は「0」)'
                      : null,
                ),
              ),
            ],
          ),
          _buildRefrigerantNotice(
            '充填していない場合は「冷媒種類」に「なし」、「冷媒量」に「0」と'
            '入力してください。充填有無に関わらず両方の入力が必須です。',
          ),
        ],
      ),
    );
  }

  /// 【不具合修正・2026-08】プロワン管轄案件(SE店舗以外)専用の案件詳細
  /// (店舗住所・部門・系統番号・障害内容・障害機器・原因・依頼内容・
  /// 訪問結果・今後の予定・技術者氏名・訪問日)の入力セクション。
  ///
  /// 背景: プロワンCSVキャッシュ(ProwanJobCache)には20項目近い情報が
  /// 保持されているが、これまでアプリ側の反映先(顧客名・作業内容・
  /// 機器型番・冷媒情報のみ)が乏しく、スキャン照合しても大半の情報が
  /// 捨てられていた。SE店舗の「コンビニ側システム入力控え」に相当する
  /// 受け皿として新設。作業報告書スキャンで自動反映された項目には
  /// 「スキャンで自動反映済み」バッジが表示され、重複しない箇所だけ
  /// 手入力すればよいことが一目でわかるようにしている。
  Widget _buildProWanReportDetailSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.assignment, size: 16, color: Colors.indigo.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'プロワン案件詳細(任意・社内保存用)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '作業報告書をスキャンすると自動反映されます。反映されない箇所だけ追加で入力してください。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.indigo.shade900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['storeAddress']!,
            label: '店舗住所',
            icon: Icons.location_on,
            fieldKey: 'pro_wan_report_detail.store_address',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['clientName']!,
            label: '得意先名',
            icon: Icons.apartment,
            fieldKey: 'pro_wan_report_detail.client_name',
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildField(
                  controller: _pwCtrls['receiptDate']!,
                  label: '受付日',
                  icon: Icons.event,
                  fieldKey: 'pro_wan_report_detail.receipt_date',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _pwCtrls['caseNo']!,
                  label: 'ケースNo',
                  icon: Icons.confirmation_number,
                  fieldKey: 'pro_wan_report_detail.case_no',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildField(
                  controller: _pwCtrls['department']!,
                  label: '部門',
                  icon: Icons.business,
                  fieldKey: 'pro_wan_report_detail.department',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _pwCtrls['systemNumber']!,
                  label: '系統番号・名',
                  icon: Icons.tag,
                  fieldKey: 'pro_wan_report_detail.system_number',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['equipmentLocation']!,
            label: '修理機器・場所',
            icon: Icons.place,
            fieldKey: 'pro_wan_report_detail.equipment_location',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['requestContent']!,
            label: 'ご依頼内容',
            icon: Icons.mail_outline,
            maxLines: 2,
            fieldKey: 'pro_wan_report_detail.request_content',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['cause']!,
            label: '原因(故障箇所)',
            icon: Icons.search,
            maxLines: 2,
            fieldKey: 'pro_wan_report_detail.cause',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['visitResult']!,
            label: '訪問結果',
            icon: Icons.fact_check,
            maxLines: 2,
            fieldKey: 'pro_wan_report_detail.visit_result',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['futurePlan']!,
            label: '今後の予定(未完了の場合)',
            icon: Icons.event_note,
            maxLines: 2,
            fieldKey: 'pro_wan_report_detail.future_plan',
          ),
          const SizedBox(height: 10),
          _buildField(
            controller: _pwCtrls['technicianName']!,
            label: '技術者氏名(プロワン側記録・任意/日報作成者と異なる場合のみ入力)',
            icon: Icons.badge,
            fieldKey: 'pro_wan_report_detail.technician_name',
          ),
        ],
      ),
    );
  }

  /// 作業内容欄の記入サポート(ナレガレ共有の前提となる必要情報のもれないチェッキリスト)。
  /// 店舗区分(SE/プロワン)と対応区分に応じて内容を切り替え、他セレクションとの重複を避ける。
  Widget _buildWorkContentSupport(bool isSEStore) {
    final mode = _workSupportMode(isSEStore);
    late String title;
    late String note;
    late List<String> items;
    late MaterialColor color;
    // 【業務ルール追記・2026-08】特定の取引先(ロピア案件等)向けの特記事項。
    // 通常の記入ヒント一覧に混ぜると重要度が伝わりにくいため、
    // 該当モードの場合のみ専用の強調ボックスとして分けて表示する。
    String? specialNotice;
    switch (mode) {
      case _WorkSupportMode.seRepair:
        title = '記入サポート(SE店舗・修理・故障対応)';
        note =
            '事象・原因・処置の詳細はこの下の「コンビニ側システム入力控え」に記入するため、ここでは重複させず、社内のナレッジ共有に役立つ視点を中心に記載してください。';
        color = Colors.orange;
        items = [
          '対応中に気づいたこと・判断に迷った点',
          '工夫した対応・うまくいった進め方',
          '次に同じような対応をする人へのアドバイス',
          '(事象・原因・処置内容の詳細は下の入力控えへ)',
        ];
        break;
      case _WorkSupportMode.seOther:
        title = '記入サポート(SE店舗・点検など)';
        note = '点検などSE店舗対応の場合、コンビニ側システムへの入力控えは不要です。作業内容欄に必要な情報を記載してください。';
        color = Colors.blue;
        items = [
          '点検・確認した設備・箇所',
          '状態(正常/要注意/異常等)の確認結果',
          '気になった点・次回確認すべき点',
          '次に対応する人への引き継ぎ事項',
        ];
        break;
      case _WorkSupportMode.nonSE:
        title = '記入サポート(プロワン管轄案件)';
        note =
            '修理・故障対応の詳細はプロワン側システムに記録されているため、ここでは重複入力を避け、ナレッジ共有に役立つ概要・気づきを中心に記載してください。';
        color = Colors.teal;
        specialNotice =
            'ロピア案件については、プロワン案件画面で手入力対応。'
            '同時に中野冷機(株)提出の紙の作業報告書も提出してください。';
        items = [
          'どんな状況・依頼だったか(概要)',
          '対応の判断ポイント・工夫した点',
          '次に同じ案件を担当する人へ伝えたいこと',
          '(詳細な修理手順・使用部品等はプロワン側システム参照のため省略可)',
        ];
        break;
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, size: 16, color: color.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          if (specialNotice != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.priority_high_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      specialNotice,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: color.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(it, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「作業報告書をスキャンしてAIで自動入力」への入口カード。
  ///
  /// 作業内容や各項目を手入力する前の段階で表示し、報告書がある場合は
  /// 先にスキャンしておけば以降の入力項目を自動で埋められることを案内する。
  /// 実際のスキャン処理は_scanReport()(コンビニ側システム入力控え内の
  /// ボタンと同じ処理)を呼び出すため、二重実装にはならない。
  ///
  /// 【2026-08 不具合修正】SE店舗・プロワン管轄案件のどちらでも表示する
  /// (サーバー側でSE用・プロワン用の書式を自動判別する設計のため)。
  /// isSEStoreに応じて案内文言を出し分ける:
  /// - SE店舗: 従来通り店番・住所・型式・機番・事象・処置内容などを案内
  /// - プロワン管轄案件: 伝票No(案件管理番号)を読み取り、CSVキャッシュと
  ///   自動照合して顧客名・作業内容・機器型番・冷媒情報を自動入力する旨を案内
  Widget _buildScanEntryCard(bool isSEStore) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.document_scanner,
                size: 18,
                color: Colors.blue.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '作業報告書はお持ちですか?',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isSEStore
                ? '先にスキャンすると、店番・住所・型式・機番・事象・処置内容など'
                      'この先の入力項目にAIが自動入力します。'
                      '自動入力された項目には緑色の'
                      '「スキャンで自動反映済み」マークが付くので、'
                      'それ以外の項目だけ追加で入力すればOKです。'
                : '先にスキャンすると、作業報告書に印字されている伝票No・得意先名・'
                      '受付日・部門・系統番号・ケースNo・修理機器・場所・ご依頼内容・原因・'
                      '訪問結果・今後の予定・技術者氏名・機器型番・作業内容・冷媒情報などを'
                      'AIが直接読み取って自動入力します。緑色の'
                      '「スキャンで自動反映済み」マークが付いた項目以外'
                      '(内容の確認・下のナレッジ共有など)だけ追加でご記入ください。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _scanReport,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('作業報告書をスキャンしてAIで自動入力'),
            ),
          ),
        ],
      ),
    );
  }

  /// 作業者氏名(報告書控え)フィールド。
  ///
  /// 【方針】現場作業者はほぼ全員アプリ登録済みの社員であるため、まず従業員マスタ
  /// (appState.users)からの選択を基本とする(表記ゆれ・誤字を防止)。
  /// 協力会社や臨時作業者などマスタに存在しない場合のみ「その他(手入力)」を選び、
  /// 直接氏名を入力できるようにする(併用方式)。
  /// この項目はAI-OCR(作業報告書スキャン)の対象外とし、常に人の手で選択・入力する。
  Widget _buildWorkerNameField() {
    final appState = context.watch<AppState>();
    final users = List<AppUser>.from(appState.users)
      ..sort((a, b) => a.name.compareTo(b.name));
    final isOther = _workerNameSelection == _workerNameOtherValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _workerNameSelection,
          decoration: const InputDecoration(
            labelText: '作業者氏名(報告書控え・任意)',
            prefixIcon: Icon(Icons.person_outline),
          ),
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('選択してください', overflow: TextOverflow.ellipsis),
            ),
            ...users.map(
              (u) => DropdownMenuItem<String?>(
                value: u.id,
                child: Text(u.name, overflow: TextOverflow.ellipsis),
              ),
            ),
            const DropdownMenuItem<String?>(
              value: _workerNameOtherValue,
              child: Text('その他(リストにない場合は手入力)'),
            ),
          ],
          onChanged: (v) {
            setState(() {
              _workerNameSelection = v;
              if (v == null) {
                _ssCtrls['workerName']!.text = '';
              } else if (v == _workerNameOtherValue) {
                // 手入力欄をこのあと表示するので、既存の値はそのまま保持する
                // (社員一覧に見つからず「その他」として復元されたケースを含む)。
              } else {
                final u = users.where((u) => u.id == v).firstOrNull;
                _ssCtrls['workerName']!.text = u?.name ?? '';
              }
            });
          },
        ),
        if (isOther) ...[
          const SizedBox(height: 10),
          _buildField(
            controller: _ssCtrls['workerName']!,
            label: '作業者氏名(手入力)',
            icon: Icons.edit_outlined,
            hint: '協力会社・臨時作業者など、リストにない方の氏名',
          ),
        ],
      ],
    );
  }

  /// 「案件においての役割」フィールド(プルダウン+自由記述の併用・2026-08導入)
  ///
  /// 【今後の開発方向】人事評価制度の項目として、将来的には評価指標との紐づけ・
  /// 点数化を視野に入れているが、現段階ではまず案件ごとの役割データを
  /// 収集できればよい、という位置づけ。そのためUI上も必須項目とはせず、
  /// 「作業内容」に近いこのエリア(基本情報の一部)に軽量に配置している。
  Widget _buildCaseRoleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _caseRolePreset,
          decoration: const InputDecoration(
            labelText: '案件においての役割(任意・人事評価データ収集用)',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('未選択')),
            ...CaseRoleOptions.presets.map(
              (v) => DropdownMenuItem<String?>(value: v, child: Text(v)),
            ),
          ],
          onChanged: (v) => setState(() => _caseRolePreset = v),
        ),
        const SizedBox(height: 8),
        _buildField(
          controller: _caseRoleNoteCtrl,
          label: '役割の補足(自由記述・任意)',
          icon: Icons.edit_note,
          hint: '例: 新人の同行指導を兼ねて主担当を務めた 等',
          maxLines: 2,
        ),
      ],
    );
  }

  /// 共同作業者(複数選択)フィールド
  /// 従業員マスタ(appState.users)から選択する。自由記述は表記ゆれの原因になるため使用しない。
  Widget _buildCoWorkerField() {
    final appState = context.watch<AppState>();
    final currentUserId = appState.currentUser?.id;
    // 主担当者(現在のユーザー)以外の従業員一覧から選択できるようにする
    final candidates = appState.users
        .where((u) => u.id != currentUserId)
        .toList();
    final selectedNames = _selectedCoWorkerIds
        .map((id) {
          final u = appState.users.where((u) => u.id == id).firstOrNull;
          return u?.name;
        })
        .whereType<String>()
        .toList();

    return InkWell(
      onTap: () => _pickCoWorkers(candidates),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '共同作業者(任意・複数選択可)',
          prefixIcon: Icon(Icons.groups_outlined),
        ),
        child: selectedNames.isEmpty
            ? Text(
                '担当者以外に作業した人がいれば選択してください',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selectedNames
                    .map(
                      (n) => Chip(
                        label: Text(n),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _pickCoWorkers(List<AppUser> candidates) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        final tempSelected = List<String>.from(_selectedCoWorkerIds);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('共同作業者を選択'),
              content: SizedBox(
                width: double.maxFinite,
                child: candidates.isEmpty
                    ? const Text('選択可能な従業員がいません')
                    : ListView(
                        shrinkWrap: true,
                        children: candidates.map((u) {
                          final checked = tempSelected.contains(u.id);
                          return CheckboxListTile(
                            value: checked,
                            title: Text(u.name),
                            subtitle: Text(
                              '${u.department} ・ ${u.employeeCode}',
                            ),
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
                                  tempSelected.add(u.id);
                                } else {
                                  tempSelected.remove(u.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(tempSelected),
                  child: const Text('決定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _selectedCoWorkerIds
          ..clear()
          ..addAll(result);
      });
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PartInputDialog extends StatefulWidget {
  final void Function(PartUsed) onAdd;
  const _PartInputDialog({required this.onAdd});

  @override
  State<_PartInputDialog> createState() => _PartInputDialogState();
}

class _PartInputDialogState extends State<_PartInputDialog> {
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _partNumberCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _partNumberCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('使用部品を追加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '部品名'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '数量'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _partNumberCtrl,
            decoration: const InputDecoration(
              labelText: '部品図番(任意)',
              hintText: '分かる場合のみ入力(月次請求明細との突合精度が上がります)',
              hintMaxLines: 2,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '補足(仕入先等・任意)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
            widget.onAdd(
              PartUsed(
                name: name,
                quantity: qty,
                partNumber: _partNumberCtrl.text.trim().isEmpty
                    ? null
                    : _partNumberCtrl.text.trim(),
                note: _noteCtrl.text.trim().isEmpty
                    ? null
                    : _noteCtrl.text.trim(),
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('追加'),
        ),
      ],
    );
  }
}
