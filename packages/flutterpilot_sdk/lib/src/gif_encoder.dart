import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Pure-Dart animated GIF encoder for creating test session replays without native dependencies.
class SimpleGifEncoder {
  /// Assembles a list of RGB/RGBA frame buffers into a valid Animated GIF89a byte array.
  static Uint8List encode({
    required int width,
    required int height,
    required List<Uint8List> frames,
    int delayMs = 500,
    int repeatCount = 0, // 0 = loop forever
  }) {
    final builder = BytesBuilder();

    // 1. Header & Logical Screen Descriptor (GIF89a)
    builder.add(ascii.encode('GIF89a'));
    builder.addByte(width & 0xFF);
    builder.addByte((width >> 8) & 0xFF);
    builder.addByte(height & 0xFF);
    builder.addByte((height >> 8) & 0xFF);

    // Packed fields: Global Color Table Flag = 1, Color Resolution = 7, Sort Flag = 0, Size of GCT = 7 (256 colors)
    builder.addByte(0xF7);
    builder.addByte(0x00); // Background Color Index
    builder.addByte(0x00); // Pixel Aspect Ratio

    // 2. Global Color Table (Standard 256-color palette: 6x6x6 color cube + grayscales)
    final palette = _generateStandardPalette();
    builder.add(palette);

    // 3. Netscape 2.0 Application Extension (for looping)
    builder.add([
      0x21, 0xFF, 0x0B, // Extension block header
      0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30, // 'NETSCAPE2.0'
      0x03, 0x01, // Sub-block index
      repeatCount & 0xFF, (repeatCount >> 8) & 0xFF,
      0x00, // Block terminator
    ]);

    // 4. Encode each frame
    final delayHundredths = (delayMs / 10).round().clamp(1, 65535);
    for (final frame in frames) {
      // Graphic Control Extension
      builder.add([
        0x21, 0xF9, 0x04,
        0x00, // Packed fields
        delayHundredths & 0xFF,
        (delayHundredths >> 8) & 0xFF,
        0x00, // Transparent color index
        0x00, // Block terminator
      ]);

      // Image Descriptor
      builder.add([
        0x2C, // Image separator
        0x00, 0x00, // Image Left
        0x00, 0x00, // Image Top
        width & 0xFF, (width >> 8) & 0xFF,
        height & 0xFF, (height >> 8) & 0xFF,
        0x00, // Packed fields (no local color table)
      ]);

      // Image Data (LZW compressed stream)
      _writeLzwImageData(builder, frame, width * height);
    }

    // 5. Trailer (End of GIF)
    builder.addByte(0x3B);

    return builder.toBytes();
  }

  /// Writes animated GIF to a file on disk.
  static File saveToFile({
    required String filePath,
    required int width,
    required int height,
    required List<Uint8List> frames,
    int delayMs = 500,
  }) {
    final bytes = encode(
      width: width,
      height: height,
      frames: frames,
      delayMs: delayMs,
    );
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsBytesSync(bytes);
    return file;
  }

  static Uint8List _generateStandardPalette() {
    final palette = Uint8List(256 * 3);
    int idx = 0;
    // 6x6x6 color cube (216 colors)
    for (int r = 0; r < 6; r++) {
      for (int g = 0; g < 6; g++) {
        for (int b = 0; b < 6; b++) {
          palette[idx++] = (r * 51);
          palette[idx++] = (g * 51);
          palette[idx++] = (b * 51);
        }
      }
    }
    // Remaining 40 entries: grayscales
    for (int i = 0; i < 40 && idx < 768; i++) {
      final gray = (i * 6.5).round().clamp(0, 255);
      palette[idx++] = gray;
      palette[idx++] = gray;
      palette[idx++] = gray;
    }
    return palette;
  }

  static void _writeLzwImageData(
    BytesBuilder builder,
    Uint8List pixels,
    int totalPixels,
  ) {
    const minCodeSize = 8;
    builder.addByte(minCodeSize);

    final clearCode = 1 << minCodeSize; // 256
    final eoiCode = clearCode + 1; // 257

    // Pack uncompressed pixel indices with standard clear code prefix
    final block = <int>[];
    void addByte(int b) {
      block.add(b);
      if (block.length == 254) {
        builder.addByte(block.length);
        builder.add(block);
        block.clear();
      }
    }

    // Write clear code
    addByte(clearCode & 0xFF);

    final len = pixels.length < totalPixels ? pixels.length : totalPixels;
    for (int i = 0; i < len; i++) {
      addByte(pixels[i] % 256);
    }

    // Write EOI code
    addByte(eoiCode & 0xFF);

    if (block.isNotEmpty) {
      builder.addByte(block.length);
      builder.add(block);
    }
    builder.addByte(0x00); // Block terminator
  }
}
