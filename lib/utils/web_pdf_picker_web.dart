// Web専用実装。package:webはWebターゲットのみでビルドされるため、
// このファイル自体がAndroidビルド時にコンパイルされることはない
// (web_pdf_picker.dartのconditional importで切り替わる)。
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 【不具合対応・2026-08-27】
/// これまで file_picker パッケージ経由でPDFファイルを選択していたが、
/// ビルド環境のキャッシュ不整合により file_picker のWeb実装
/// (FilePickerWeb.registerWith)がビルドに含まれず、
/// 「MissingPluginException」が発生してファイルを一切選択できない
/// 不具合が本番環境で発生した。
///
/// file_picker はWeb版においても内部的には単純な
/// `<input type="file">` 要素を生成しているだけであり、プラグインの
/// 仕組み(MethodChannel経由の登録)を経由する必要が本質的にはない。
/// そこで、プラグイン登録の問題を根本的に回避するため、
/// package:web(dart:js_interopベースの標準Web API)を直接使い、
/// `<input type="file">` を自前で生成・操作する方式に切り替える。
/// これにより、ビルド時のプラグイン登録状態に一切依存しなくなる。
///
/// 端末のダウンロードフォルダを含む、ブラウザが提供するファイル選択
/// ダイアログでアクセスできる場所であればどこからでも選択可能。
///
/// 戻り値: 選択されたPDFファイルのバイト列とファイル名。
/// ユーザーがキャンセルした場合は null。
Future<WebPickedPdf?> pickPdfFileWeb() async {
  final completer = Completer<WebPickedPdf?>();

  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = '.pdf,application/pdf'
    ..style.display = 'none';

  web.document.body?.appendChild(input);

  void cleanup() {
    input.remove();
  }

  // ファイルが選択された場合。
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
      // Blob.arrayBuffer()で非同期にバイト列を取得する。
      file.arrayBuffer().toDart.then(
        (buffer) {
          if (!completer.isCompleted) {
            completer.complete(
              WebPickedPdf(bytes: buffer.toDart.asUint8List(), name: fileName),
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

  // ファイル選択ダイアログを開かずにキャンセルした場合。
  // 【重要】modern browsers(Chrome 113+・Firefox最新版)は input要素の
  // 'cancel' イベントに対応しており、window の focus/blur タイミングに
  // 依存する不安定な判定(以前のfile_picker実装で問題になっていた
  // 競合状態)を使う必要がない。
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

/// Web版で選択されたPDFファイルの情報(バイト列とファイル名)。
class WebPickedPdf {
  final Uint8List bytes;
  final String name;

  const WebPickedPdf({required this.bytes, required this.name});
}
