import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// 店舗選択フィールド。
/// 店舗マスタからの選択(検索付き)と、リストにない店舗の自由入力の両方に対応する。
class StorePickerField extends StatefulWidget {
  final String? selectedStoreId;
  final TextEditingController freeTextController; // リスト外・自由入力用コントローラ(親が所有)
  final ValueChanged<Store> onStoreSelected;
  final ValueChanged<String> onFreeTextChanged;

  const StorePickerField({
    super.key,
    required this.selectedStoreId,
    required this.freeTextController,
    required this.onStoreSelected,
    required this.onFreeTextChanged,
  });

  @override
  State<StorePickerField> createState() => _StorePickerFieldState();
}

class _StorePickerFieldState extends State<StorePickerField> {
  Future<void> _openPicker() async {
    final appState = context.read<AppState>();
    final selected = await showModalBottomSheet<Store>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StoreSearchSheet(allStores: appState.stores),
    );
    if (selected != null) {
      widget.onStoreSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedStore = widget.selectedStoreId != null
        ? appState.getStoreById(widget.selectedStoreId!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _openPicker,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: '訪問先店舗',
              prefixIcon: const Icon(Icons.storefront),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              helperText: selectedStore == null ? 'タップして店舗リストから選択' : null,
            ),
            child: selectedStore == null
                ? Text(
                    '店舗を選択してください',
                    style: TextStyle(color: Colors.grey.shade500),
                  )
                : Text(selectedStore.name),
          ),
        ),
        if (selectedStore != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selectedStore.isSE
                    ? Colors.orange.withValues(alpha: 0.12)
                    : Colors.blueGrey.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selectedStore.isSE
                        ? Icons.storefront
                        : Icons.handshake_outlined,
                    size: 14,
                    color: selectedStore.isSE
                        ? Colors.orange.shade800
                        : Colors.blueGrey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    selectedStore.isSE
                        ? 'SE店舗(コンビニ) — 修理・故障対応はコンビニ側入力控えが必須です'
                        : 'プロワン管轄案件 — 基本情報のみで入力完了します',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selectedStore.isSE
                          ? Colors.orange.shade800
                          : Colors.blueGrey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (selectedStore != null &&
            (selectedStore.address.isNotEmpty ||
                selectedStore.keyLocation.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedStore.address.isNotEmpty)
                    _infoRow(Icons.location_on_outlined, selectedStore.address),
                  if (selectedStore.phone.isNotEmpty)
                    _infoRow(Icons.phone_outlined, selectedStore.phone),
                  if (selectedStore.keyLocation.isNotEmpty)
                    _infoRow(
                      Icons.vpn_key_outlined,
                      '鍵・動力盤: ${selectedStore.keyLocation}',
                    ),
                  if (selectedStore.note.isNotEmpty)
                    _infoRow(Icons.info_outline, selectedStore.note),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.freeTextController,
          onChanged: widget.onFreeTextChanged,
          decoration: const InputDecoration(
            labelText: '店舗名(リスト外・自由入力)',
            prefixIcon: Icon(Icons.edit_location_alt_outlined),
            helperText: 'リストにない店舗はこちらに直接入力してください',
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StoreSearchSheet extends StatefulWidget {
  final List<Store> allStores;
  const _StoreSearchSheet({required this.allStores});

  @override
  State<_StoreSearchSheet> createState() => _StoreSearchSheetState();
}

class _StoreSearchSheetState extends State<_StoreSearchSheet> {
  final _searchCtrl = TextEditingController();
  late List<Store> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.allStores;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String kw) {
    setState(() {
      if (kw.trim().isEmpty) {
        _filtered = widget.allStores;
      } else {
        final k = kw.trim().toLowerCase();
        _filtered = widget.allStores
            .where(
              (s) =>
                  s.name.toLowerCase().contains(k) ||
                  s.address.toLowerCase().contains(k),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '店舗を選択',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.allStores.length}件登録',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                autofocus: false,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: '店舗名・住所で検索',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          '該当する店舗がありません\nリスト外の場合は下の自由入力欄をご利用ください',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = _filtered[i];
                          return ListTile(
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
                            title: Text(s.name),
                            subtitle: s.address.isNotEmpty
                                ? Text(
                                    s.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(s),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
