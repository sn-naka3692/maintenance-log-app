import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/part_used.dart';
import '../models/store.dart';
import '../models/store_system_report.dart';
import '../models/user.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
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

  String? _selectedStoreId;
  final List<String> _selectedCoWorkerIds = [];
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

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    final e = widget.existing;
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
    final ss = e?.storeSystemReportCopy ?? StoreSystemReport();
    _ssCtrls = {
      'receiptNumber': TextEditingController(text: ss.receiptNumber),
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
    };
    _tagInputCtrl = TextEditingController();

    if (e != null) {
      _visitDate = e.visitDate;
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endTime = TimeOfDay.fromDateTime(e.endTime);
      _responseType = e.responseType;
      _parts.addAll(e.partsUsed);
      _tags.addAll(e.tags);
      _photoPaths.addAll(e.photoPaths);
      _selectedCoWorkerIds.addAll(e.coWorkerIds);
    }
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
    _tagInputCtrl.dispose();
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
    if (picked != null) setState(() => _visitDate = picked);
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
    );
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (file != null) {
        setState(() => _photoPaths.add(file.path));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写真の選択に失敗しました(Web環境では制限があります)')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

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
      await appState.updateReport(r);
    } else {
      final report = WorkReport(
        id: appState.newId(),
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await appState.addReport(report);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? '日報を更新しました' : '日報を保存しました')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy年M月d日 (E)', 'ja_JP');
    final appState = context.watch<AppState>();
    final selectedStore = _selectedStoreId != null
        ? appState.getStoreById(_selectedStoreId!)
        : null;
    final isSEStore = selectedStore?.isSE ?? false;
    // コンビニ側システム入力控えは、SE店舗かつ修理・故障対応の場合のみ必須(マニュアルの入力ルールに準拠)。
    final showStoreSystemSection =
        isSEStore &&
        (_responseType == ResponseType.repair ||
            _responseType == ResponseType.breakdown);
    // プロワン管轄案件(SE店舗以外)の現場作業では、請求業務効率化のため
    // 冷媒種類・冷媒量の入力を必須とする(バックオフィス業務は対象外)。
    final showNonSeRefrigerantSection =
        !isSEStore && !_responseType.isBackOffice;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '日報編集' : '日報作成')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SectionTitle('基本情報'),
            const SizedBox(height: 8),
            if (_responseType.isBackOffice)
              _buildField(
                controller: _clientNameCtrl,
                label: '対象・場所(任意)',
                icon: Icons.apartment,
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
                decoration: const InputDecoration(
                  labelText: '訪問日',
                  prefixIcon: Icon(Icons.calendar_today),
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
            if (_responseType.isBackOffice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'バックオフィス業務は機器型番・プロワン管理番号の入力は不要です(任意)。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 12),
            _buildField(
              controller: _equipmentModelCtrl,
              label: _responseType.isBackOffice ? '機器型番(任意)' : '機器型番(プロワン参照)',
              icon: Icons.qr_code,
              hint: '例: 冷凍機型番 XR-500',
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _proWanCtrl,
              label: 'プロワン管理番号(任意)',
              icon: Icons.numbers,
              hint: 'プロワン側で管理している案件番号',
            ),
            const SizedBox(height: 12),
            _buildCoWorkerField(),

            const SizedBox(height: 20),
            _SectionTitle(_responseType.isBackOffice ? '業務内容' : '作業内容'),
            const SizedBox(height: 8),
            _buildField(
              controller: _workContentCtrl,
              label: _responseType.isBackOffice ? '業務内容' : '作業内容',
              icon: Icons.build,
              maxLines: 4,
              enableVoice: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '必須項目です' : null,
            ),
            if (!_responseType.isBackOffice)
              _buildWorkContentSupport(isSEStore),
            const SizedBox(height: 12),

            if (showNonSeRefrigerantSection) _buildNonSeRefrigerantSection(),

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
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2, size: 20),
                    title: Text('${p.name} × ${p.quantity}'),
                    subtitle: p.note != null && p.note!.isNotEmpty
                        ? Text(p.note!)
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _parts.removeAt(i)),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),
            // 写真
            Row(
              children: [
                const Text('写真', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            if (_photoPaths.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photoPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 90,
                            height: 90,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image, color: Colors.grey),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _photoPaths.removeAt(i)),
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

            const SizedBox(height: 20),
            _SectionTitle('ナレッジ共有(社内評価・マニュアル反映用)'),
            const SizedBox(height: 4),
            Text(
              'ここに記録した内容は、社内でのノウハウ共有・人事評価・現場マニュアル更新の元データとして活用されます。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
              _buildField(
                controller: _ssCtrls['receiptNumber']!,
                label: '弊社受付No.',
                icon: Icons.confirmation_number_outlined,
              ),
              const SizedBox(height: 16),
              Text(
                '冷媒情報',
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
                      controller: _ssCtrls['refrigerantType']!,
                      label: '冷媒種類',
                      icon: Icons.ac_unit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _ssCtrls['refrigerantAmount']!,
                      label: '充填量',
                      icon: Icons.opacity,
                    ),
                  ),
                ],
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
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(isEditing ? '更新する' : '日報を保存'),
            ),
          ],
        ),
      ),
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
  }) {
    final isListening = _activeListenController == controller;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor),
        alignLabelWithHint: maxLines > 1,
        suffixIcon: enableVoice
            ? IconButton(
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  color: isListening ? Colors.red : Colors.grey.shade500,
                ),
                tooltip: isListening ? '音声入力を停止' : '音声入力を開始',
                onPressed: () => _toggleVoiceInput(controller),
              )
            : null,
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
          const SizedBox(height: 4),
          Text(
            '充填していない場合は「冷媒種類」に「なし」、「冷媒量」に「0」と入力してください。'
            '充填有無に関わらず両方の入力が必須です。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.teal.shade900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildField(
                  controller: _nonSeRefrigerantTypeCtrl,
                  label: '冷媒種類',
                  icon: Icons.ac_unit,
                  hint: '例: R410A / なし',
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
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '必須項目です(未充填時は「0」)'
                      : null,
                ),
              ),
            ],
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
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
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
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '補足(型番等・任意)'),
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
