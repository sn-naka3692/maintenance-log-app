import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 日報の写真をFirebase Storageへアップロードするサービス。
///
/// 【背景・2026-08】従来、写真は端末のローカルファイルパス(image_picker
/// が返す File.path)をそのままFirestoreへ保存していたため、撮影した
/// 本人の端末以外では画像が一切表示できなかった(パスが指す実体が
/// 存在しないため)。この不具合を解消するため、Firebase Storageへ
/// アップロードし、誰の端末からでも参照可能なダウンロードURLを
/// photoPathsに保存する方式へ変更する。
///
/// 保存先パス: report_photos/{reportId}/{uuid}.jpg
/// (reportIdごとにフォルダを分けることで、日報削除時に一括削除しやすくする)
///
/// 【背景・2026-09】image_pickerが返す画像バイト列には、機種によって
/// EXIF Orientationタグ(縦横判定情報)が付与されたまま、生ピクセルは
/// 回転前の状態になっているケースがある(例: Galaxy A54等)。これを
/// 未処理のままアップロードすると、Azure Document Intelligence等の
/// 後続処理はEXIFを正しく解釈するのに対し、単純な正規化座標→ピクセル
/// 変換だけを行う画面表示側ではズレが生じる。そのため、アップロード前に
/// EXIF情報に従って画像を正立化(ベイク)し、以降の処理を全てEXIF非依存
/// にする。
class PhotoUploadService {
  PhotoUploadService._();
  static final PhotoUploadService instance = PhotoUploadService._();

  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// XFile(image_pickerの選択結果)をアップロードし、ダウンロードURLを返す。
  /// Web/モバイル両対応のため、File.path(モバイル専用)ではなく
  /// XFile.readAsBytes()でバイト列を取得してアップロードする。
  Future<String> uploadPhoto({
    required XFile file,
    required String reportId,
  }) async {
    final rawBytes = await file.readAsBytes();
    final ext = _extensionFor(file.name);
    final bytes = normalizeOrientation(rawBytes, ext);
    final fileName = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final ref = _storage.ref().child('report_photos/$reportId/$fileName');
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeFor(ext)),
    );
    return ref.getDownloadURL();
  }

  /// アップロード済みの写真(ダウンロードURL)をStorageから削除する。
  /// URL形式でない値(旧・ローカルパス形式の残存データ等)は無視する。
  Future<void> deletePhoto(String downloadUrl) async {
    if (!downloadUrl.startsWith('http')) return;
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
    } catch (_) {
      // 既に削除済み・URL形式不正等は無視(削除操作は冪等であるべき)
    }
  }

  /// EXIF Orientationタグに従って画像ピクセルを正立化(ベイク)する。
  /// PNG等、そもそもEXIF回転を持たない形式や、デコードに失敗した場合は
  /// 元のバイト列をそのまま返す(安全側フォールバック)。
  ///
  /// 【重要】ここで正立化しておくことで、Azure Document Intelligence
  /// (EXIFを解釈して正立座標を返す)と、この後Flutter側で画像を表示・
  /// 保存する際の座標系を一致させる。
  static Uint8List normalizeOrientation(Uint8List rawBytes, String ext) {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return rawBytes;

      // decodeImageは通常EXIF Orientationを自動適用済みの場合もあるが、
      // 念のためbakeOrientation相当の処理を明示的に通し、EXIF情報自体は
      // 出力から除去する(以降EXIF非依存のバイト列にする)。
      final baked = img.bakeOrientation(decoded);

      if (ext == '.png') {
        return Uint8List.fromList(img.encodePng(baked));
      }
      return Uint8List.fromList(img.encodeJpg(baked, quality: 90));
    } catch (_) {
      // デコード不可(未対応フォーマット等)の場合は元のバイト列を維持する。
      return rawBytes;
    }
  }

  String _extensionFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    final ext = fileName.substring(dot).toLowerCase();
    const allowed = ['.jpg', '.jpeg', '.png', '.webp', '.heic'];
    return allowed.contains(ext) ? ext : '.jpg';
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
