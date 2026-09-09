import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_app/utils/blur_detector.dart';

/// 文字っぽい高コントラストの縞模様(チェッカーボード)画像を作る。
/// エッジがはっきりしているため「鮮明な画像」の代表として使う。
Uint8List _buildSharpImage() {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  const cell = 20;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final isBlack = ((x ~/ cell) + (y ~/ cell)) % 2 == 0;
      if (isBlack) {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  return img.encodeJpg(image, quality: 90);
}

/// 上のチェッカーボードにガウシアンブラーを掛け、
/// 「ピンボケ画像」を模したものを作る。
Uint8List _buildBlurryImage() {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  const cell = 20;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final isBlack = ((x ~/ cell) + (y ~/ cell)) % 2 == 0;
      if (isBlack) {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  final blurred = img.gaussianBlur(image, radius: 10);
  return img.encodeJpg(blurred, quality: 90);
}

/// 真っ白(エッジが全く無い)画像。判定不能ではなく「非常にボケている」
/// 側の極端ケースとして扱われるはず。
Uint8List _buildBlankImage() {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return img.encodeJpg(image, quality: 90);
}

void main() {
  test('鮮明な画像(チェッカーボード)はブレなしと判定される', () {
    final bytes = _buildSharpImage();
    final result = detectBlur(bytes);
    // ignore: avoid_print
    print('sharp variance = ${result.variance}');
    expect(result.isLikelyBlurry, isFalse);
    expect(result.variance, greaterThan(0));
  });

  test('ぼかした画像はブレありと判定される', () {
    final bytes = _buildBlurryImage();
    final result = detectBlur(bytes);
    // ignore: avoid_print
    print('blurry variance = ${result.variance}');
    expect(result.isLikelyBlurry, isTrue);
  });

  test('真っ白画像(エッジ無し)はブレありと判定される', () {
    final bytes = _buildBlankImage();
    final result = detectBlur(bytes);
    // ignore: avoid_print
    print('blank variance = ${result.variance}');
    expect(result.isLikelyBlurry, isTrue);
  });

  test('鮮明な画像の分散値はぼかした画像の分散値より明確に大きい', () {
    final sharpResult = detectBlur(_buildSharpImage());
    final blurryResult = detectBlur(_buildBlurryImage());
    expect(sharpResult.variance, greaterThan(blurryResult.variance));
  });

  test('デコード不能なバイト列は判定不能(ブレなし扱い)として安全側に倒す', () {
    final invalidBytes = Uint8List.fromList([0, 1, 2, 3, 4]);
    final result = detectBlur(invalidBytes);
    expect(result.isLikelyBlurry, isFalse);
    expect(result.variance, -1);
  });
}
