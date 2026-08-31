import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// 店舗マスタ一覧・管理画面
/// 管理者/一般ユーザー問わず閲覧可能。新規店舗の追加・編集ができる。
class StoreListScreen extends StatefulWidget {
  const StoreListScreen({super.key});

  @override
  State<StoreListScreen> createState() => _StoreListScreenState();
}

class _StoreListScreenState extends State<StoreListScreen> {
  final _searchCtrl = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openStoreForm({Store? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StoreFormSheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final stores = _keyword.isEmpty
        ? appState.stores
        : appState.searchStores(_keyword);

    return Scaffold(
      appBar: AppBar(
        title: const Text('店舗マスタ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '店舗を追加',
            onPressed: () => _openStoreForm(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _keyword = v),
              decoration: InputDecoration(
                hintText: '店舗名・住所で検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _keyword = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${stores.length}件 / 全${appState.stores.length}件',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: stores.isEmpty
                ? Center(
                    child: Text(
                      '該当する店舗がありません',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: stores.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = stores[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Icon(
                              Icons.storefront,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.address.isNotEmpty)
                                Text(
                                  s.address,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (s.phone.isNotEmpty)
                                Text(
                                  s.phone,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: s.isSE
                                            ? Colors.orange.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.blueGrey.withValues(
                                                alpha: 0.10,
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        s.isSE ? 'SE店舗(コンビニ)' : 'プロワン管轄',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: s.isSE
                                              ? Colors.orange.shade800
                                              : Colors.blueGrey.shade700,
                                        ),
                                      ),
                                    ),
                                    if (s.isCustom)
                                      const Text(
                                        '手動追加',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          isThreeLine:
                              s.address.isNotEmpty && s.phone.isNotEmpty,
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _openStoreForm(existing: s),
                          ),
                          onTap: () => _openStoreForm(existing: s),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StoreFormSheet extends StatefulWidget {
  final Store? existing;
  const _StoreFormSheet({this.existing});

  @override
  State<_StoreFormSheet> createState() => _StoreFormSheetState();
}

class _StoreFormSheetState extends State<_StoreFormSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _zipCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _noteCtrl;
  late bool _isSE;

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _zipCtrl = TextEditingController(text: e?.zipCode ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _keyCtrl = TextEditingController(text: e?.keyLocation ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _isSE = e?.isSE ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _zipCtrl.dispose();
    _addressCtrl.dispose();
    _keyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('店舗名を入力してください')));
      return;
    }
    final appState = context.read<AppState>();
    if (isEditing) {
      final s = widget.existing!;
      s.name = name;
      s.phone = _phoneCtrl.text.trim();
      s.zipCode = _zipCtrl.text.trim();
      s.address = _addressCtrl.text.trim();
      s.keyLocation = _keyCtrl.text.trim();
      s.note = _noteCtrl.text.trim();
      s.isSE = _isSE;
      await appState.updateStore(s);
    } else {
      await appState.addStore(
        name: name,
        phone: _phoneCtrl.text.trim(),
        zipCode: _zipCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        keyLocation: _keyCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        isSE: _isSE,
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? '店舗情報を更新しました' : '店舗を追加しました')),
      );
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('店舗を削除しますか?'),
        content: Text('「${widget.existing!.name}」を店舗マスタから削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.deleteStore(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? '店舗情報を編集' : '店舗を新規追加',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isEditing)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '店舗名 *',
                prefixIcon: Icon(Icons.storefront),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '電話番号',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zipCtrl,
              decoration: const InputDecoration(
                labelText: '郵便番号',
                prefixIcon: Icon(Icons.markunread_mailbox_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: '住所',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: '鍵・動力盤の設置場所',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '備考',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.25),
                ),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isSE,
                onChanged: (v) => setState(() => _isSE = v),
                title: const Text(
                  'SE店舗(セブンイレブン)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  _isSE
                      ? 'ONの場合、修理・故障対応時は「コンビニ側システム入力控え」の入力が必須になります。'
                      : 'OFFの場合(プロワン管轄案件)は基本情報のみで入力が完了します。',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                activeThumbColor: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '※ 店舗名に「SE」が含まれていても、コンビニ以外の場合があります(例:病院名等)。実際の対応区分に合わせて手動で設定してください。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(isEditing ? '更新する' : '追加する'),
            ),
          ],
        ),
      ),
    );
  }
}
