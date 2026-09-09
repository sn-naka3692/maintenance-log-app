import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 撮影画像のピンボケ(手ブレ・ピント外れ)を検出するための軽量ユーティリティ。
///
/// 【背景・目的】
/// document_scan_flow.dart は、撮影した画像を一切加工せずそのまま
/// Azure Document Intelligenceに送信している。ピンボケ画像を送っても
/// OCRはエラーにならず「読み取れる範囲だけ」を返すため、現場は
/// 「登録できたはずなのに項目が全部空欄/文字が違う」という原因不明の
/// 不具合として認識しやすい。実際には撮影品質が原因であることが多い。
///
/// 【設計方針・2026-09導入(Step1)】
/// - あくまで「判定」のみを行い、画像そのものには一切加工を加えない。
///   画像補正(傾き補正・コントラスト強化等)はStep2以降の検討事項とし、
///   まずは「ピンボケの可能性を検知して現場に知らせる」ことだけに
///   スコープを絞る(既存の撮影〜送信フローへの影響を最小化するため)。
/// - 判定に使っても、送信は必ずユーザーの選択に委ねる(このユーティリティ
///   は「送信をブロックする」機能ではない。呼び出し元がダイアログ等で
///   再撮影を促すか、そのまま続行するかをユーザーに選ばせる想定)。
/// - 判定アルゴリズムは Laplacian分散(エッジ強度の分散)を用いる。
///   ピントが合っている画像は文字の輪郭(エッジ)がはっきりしているため
///   分散が大きく、ピンボケ画像はエッジがなだらかになるため分散が
///   小さくなる、という古典的な手法(OpenCVの
///   `cv2.Laplacian(img, cv2.CV_64F).var()` と同じ考え方をDartで
///   自前実装したもの)。
/// - 処理負荷を抑えるため、判定前に画像を小さく(最大400px幅)縮小して
///   から計算する。この縮小はあくまで「判定用の一時コピー」であり、
///   OCR送信用の元画像(呼び出し元が保持するUint8List)は一切変更しない。
class BlurDetectionResult {
  /// ピンボケの可能性が高いと判定されたか。
  final bool isLikelyBlurry;

  /// 判定に使った Laplacian分散値(スケール調整済み)。
  /// デバッグ・閾値調整の参考値として保持する。値が小さいほどボケている。
  /// 画像が解析できなかった場合は -1 になる(判定不能を示す)。
  final double variance;

  const BlurDetectionResult({
    required this.isLikelyBlurry,
    required this.variance,
  });
}

/// Laplacian分散がこの値未満の場合、ピンボケの可能性が高いと判定する。
///
/// 【閾値の根拠・今後の調整について】
/// 一般的なピント確認手法(OpenCVのvarianceOfLaplacian)ではしばしば
/// 100前後の閾値が使われるが、本実装では判定用に縮小するサイズ・輝度の
/// 正規化方式(0〜1スケール)が異なるため、その数値をそのまま使うことは
/// できない。
/// 実装時に高コントラストの合成画像(チェッカーボード)へ段階的に
/// ガウシアンブラーを掛けて検証したところ、初期の暫定値(30.0)では
/// かなり強いブラー(半径8px相当、実際の手ブレ写真に近いレベル)でも
/// 「ブレなし」と誤判定してしまうことが確認できたため、60.0に見直した。
/// それでもあくまで合成画像での検証値であり、実際の紙の作業報告書
/// (文字の太さ・行間・用紙の反射等)とは特性が異なる。運用開始後に
/// 「誤って再撮影を促してしまうケースが多い(閾値が高すぎる)」
/// 「ボケた画像を通してしまうケースが多い(閾値が低すぎる)」といった
/// 現場の声を踏まえて調整することを想定している。
const double blurVarianceThreshold = 60.0;

/// 判定用に画像を縮小する際の最大幅(px)。
/// この値を大きくすると判定精度は上がるが処理時間も増える。
const int blurAnalysisMaxWidth = 400;

/// [imageBytes] (JPEG/PNG等、image_pickerから得られる撮影画像のバイト列)
/// を解析し、ピンボケの可能性を判定する。
///
/// 【重要】この関数は判定のみを行い、[imageBytes] 自体は変更しない
/// (内部で縮小コピーを作って解析するのみ)。
///
/// 画像のデコードに失敗した場合(未対応フォーマット等)は、誤って
/// 再撮影を強制することを避けるため、安全側(ピンボケなし扱い)に倒す。
BlurDetectionResult detectBlur(Uint8List imageBytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(imageBytes);
  } catch (_) {
    decoded = null;
  }

  if (decoded == null) {
    return const BlurDetectionResult(isLikelyBlurry: false, variance: -1);
  }

  img.Image resized = decoded;
  if (decoded.width > blurAnalysisMaxWidth) {
    final newHeight =
        (decoded.height * blurAnalysisMaxWidth / decoded.width).round();
    resized = img.copyResize(
      decoded,
      width: blurAnalysisMaxWidth,
      height: newHeight,
    );
  }

  final width = resized.width;
  final height = resized.height;

  if (width < 3 || height < 3) {
    // Laplacianカーネル(3x3)を適用できないほど小さい画像は判定不能とする。
    return const BlurDetectionResult(isLikelyBlurry: false, variance: -1);
  }

  // 輝度(グレースケール、0.0〜1.0に正規化)の2次元配列を作る。
  final gray = List<List<double>>.generate(
    height,
    (_) => List<double>.filled(width, 0),
  );
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      gray[y][x] = resized.getPixel(x, y).luminanceNormalized.toDouble();
    }
  }

  // Laplacianカーネル [[0,1,0],[1,-4,1],[0,1,0]] を適用し、
  // 各画素のエッジ強度を求める(画像の端1pxは計算対象から除外)。
  final laplacianValues = <double>[];
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final value = gray[y - 1][x] +
          gray[y + 1][x] +
          gray[y][x - 1] +
          gray[y][x + 1] -
          4 * gray[y][x];
      laplacianValues.add(value);
    }
  }

  if (laplacianValues.isEmpty) {
    return const BlurDetectionResult(isLikelyBlurry: false, variance: -1);
  }

  final mean =
      laplacianValues.reduce((a, b) => a + b) / laplacianValues.length;
  final variance = laplacianValues
          .map((v) => (v - mean) * (v - mean))
          .reduce((a, b) => a + b) /
      laplacianValues.length;

  // luminanceNormalizedは0.0〜1.0スケールのため、分散値もそのままでは
  // 非常に小さくなる(閾値と比較しにくい)。桁を揃えるため10000倍する。
  final scaledVariance = variance * 10000;

  return BlurDetectionResult(
    isLikelyBlurry: scaledVariance < blurVarianceThreshold,
    variance: scaledVariance,
  );
}
