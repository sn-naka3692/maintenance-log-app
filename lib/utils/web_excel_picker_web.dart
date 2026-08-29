// Web専用実装。package:webはWebターゲットのみでビルドされるため、
// このファイル自体がAndroidビルド時にコンパイルされることはない
// (web_excel_picker.dartのconditional importで切り替わる)。
//
// web_pdf_picker_web.dartと同じ実装方式(file_pickerのプラグイン登録
// 問題を根本回避するため、<input type="file">を自前で生成・操作)。
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 拡張子.xlsxのExcelファイルを選択する。
/// 戻り値: 選択されたExcelファイルのバイト列とファイル名。
/// ユーザーがキャンセルした場合は null。
Future<WebPickedExcel?> pickExcelFileWeb() async {
  final completer = Completer<WebPickedExcel?>();

  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept =
        '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ..style.display = 'none';

  web.document.body?.appendChild(input);

  void cleanup() {
    input.remove();
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      if (completer.isCompleted) return;
      final files = input.files;
      if (files == null || files.length == 0) {
        completer.complete(null);
        cleanup();
        return;
      }
      final file = files.item(0);
      if (file == null) {
        completer.complete(null);
        cleanup();
        return;
      }
      final fileName = file.name;
      file.arrayBuffer().toDart.then(
        (buffer) {
          if (!completer.isCompleted) {
            completer.complete(
              WebPickedExcel(
                bytes: buffer.toDart.asUint8List(),
                name: fileName,
              ),
            );
          }
          cleanup();
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) {
            completer.completeError(e, st);
          }
          cleanup();
        },
      );
    }.toJS,
  );

  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      cleanup();
    }.toJS,
  );

  input.click();

  return completer.future;
}

/// Web版で選択されたExcelファイルの情報(バイト列とファイル名)。
class WebPickedExcel {
  final Uint8List bytes;
  final String name;

  const WebPickedExcel({required this.bytes, required this.name});
}
