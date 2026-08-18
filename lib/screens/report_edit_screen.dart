import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/part_used.dart';
import '../models/work_report.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class ReportEditScreen extends StatefulWidget {
  final WorkReport? existing;

  const ReportEditScreen({super.key, this.existing});

  @override
  State<ReportEditScreen> createState() => _ReportEditScreenState();
}

class _ReportEditScreenState extends State<ReportEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _clientNameCtrl;
  late TextEditingController _workContentCtrl;
  late TextEditingController _equipmentModelCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _successCtrl;
  late TextEditingController _issuesCtrl;
  late TextEditingController _proWanCtrl;
  late TextEditingController _storeSystemCtrl;
  late TextEditingController _tagInputCtrl;

  DateTime _visitDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();
  ResponseType _responseType = ResponseType.regularInspection;
  final List<PartUsed> _parts = [];
  final List<String> _tags = [];
  final List<String> _photoPaths = [];

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _clientNameCtrl = TextEditingController(text: e?.clientName ?? '');
    _workContentCtrl = TextEditingController(text: e?.workContent ?? '');
    _equipmentModelCtrl = TextEditingController(text: e?.equipmentModel ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _successCtrl = TextEditingController(text: e?.successPoints ?? '');
    _issuesCtrl = TextEditingController(text: e?.issuesPoints ?? '');
    _proWanCtrl = TextEditingController(text: e?.proWanRefNumber ?? '');
    _storeSystemCtrl = TextEditingController(
      text: e?.storeSystemReportCopy ?? '',
    );
    _tagInputCtrl = TextEditingController();

    if (e != null) {
      _visitDate = e.visitDate;
      _startTime = TimeOfDay.fromDateTime(e.startTime);
      _endTime = TimeOfDay.fromDateTime(e.endTime);
      _responseType = e.responseType;
      _parts.addAll(e.partsUsed);
      _tags.addAll(e.tags);
      _photoPaths.addAll(e.photoPaths);
    }
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _workContentCtrl.dispose();
    _equipmentModelCtrl.dispose();
    _notesCtrl.dispose();
    _successCtrl.dispose();
    _issuesCtrl.dispose();
    _proWanCtrl.dispose();
    _storeSystemCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
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

    if (isEditing) {
      final r = widget.existing!;
      r.clientName = _clientNameCtrl.text.trim();
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
      r.storeSystemReportCopy = _storeSystemCtrl.text.trim();
      await appState.updateReport(r);
    } else {
      final report = WorkReport(
        id: appState.newId(),
        authorId: user.id,
        authorName: user.name,
        clientName: _clientNameCtrl.text.trim(),
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
        storeSystemReportCopy: _storeSystemCtrl.text.trim(),
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

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '日報編集' : '日報作成')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SectionTitle('基本情報'),
            const SizedBox(height: 8),
            _buildField(
              controller: _clientNameCtrl,
              label: _responseType.isBackOffice ? '対象・場所(任意)' : '訪問先(顧客名)',
              icon: _responseType.isBackOffice
                  ? Icons.apartment
                  : Icons.storefront,
              validator: (v) =>
                  (!_responseType.isBackOffice &&
                      (v == null || v.trim().isEmpty))
                  ? '必須項目です'
                  : null,
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
                            t.isBackOffice
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

            const SizedBox(height: 20),
            _SectionTitle(_responseType.isBackOffice ? '業務内容' : '作業内容'),
            const SizedBox(height: 8),
            _buildField(
              controller: _workContentCtrl,
              label: _responseType.isBackOffice ? '業務内容' : '作業内容',
              icon: Icons.build,
              maxLines: 4,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '必須項目です' : null,
            ),
            const SizedBox(height: 12),

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
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _issuesCtrl,
              label: '課題・失敗・改善点',
              icon: Icons.report_problem_outlined,
              maxLines: 3,
              iconColor: AppColors.warning,
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
            _SectionTitle('コンビニ側システム入力控え'),
            const SizedBox(height: 4),
            Text(
              'コンビニ側の義務システムはデータ抽出ができないため、社内保管用にここへ同じ内容を控えとして記録してください。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            _buildField(
              controller: _storeSystemCtrl,
              label: 'コンビニ側システム入力内容の控え',
              icon: Icons.receipt_long,
              maxLines: 4,
            ),

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
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor),
        alignLabelWithHint: maxLines > 1,
      ),
    );
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
