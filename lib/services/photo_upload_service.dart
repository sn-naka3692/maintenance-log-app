import 'package:firebase_storage/firebase_storage.dart';
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
    final bytes = await file.readAsBytes();
    final ext = _extensionFor(file.name);
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
