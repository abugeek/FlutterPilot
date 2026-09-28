import 'dart:convert';
import 'dart:math';

import 'package:image/image.dart' as img;

/// mcp_dart validates image data with a regular expression that overflows
/// the stack above ~3 MB of base64, turning the whole call into "Internal
/// server error". Images are also paid for in tokens: keep them well below.
const int maxImageBase64Chars = 2000000;

/// [base64Png] scaled down until it fits [maxChars], or unchanged when it
/// already fits or isn't a PNG.
String fitBase64Png(String base64Png, {int maxChars = maxImageBase64Chars}) {
  if (base64Png.length <= maxChars) return base64Png;
  final image = img.decodePng(base64Decode(base64Png));
  if (image == null) return base64Png;
  var factor = sqrt(maxChars / base64Png.length) * 0.9;
  while (true) {
    final resized = base64Encode(
      img.encodePng(
        img.copyResize(
          image,
          width: max(1, (image.width * factor).round()),
          interpolation: img.Interpolation.average,
        ),
      ),
    );
    if (resized.length <= maxChars || factor < 0.05) return resized;
    factor *= 0.7;
  }
}
