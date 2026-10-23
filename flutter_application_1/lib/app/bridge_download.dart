import 'dart:convert';
import 'dart:typed_data';

/// Bounded, ordered download assembly. Blob URLs are meaningful only within the
/// WebView; their bytes must be transferred before the website revokes the URL.
class BridgeDownload {
  BridgeDownload({required String filename, required this.expectedBytes})
    : filename = safeFilename(filename) {
    if (expectedBytes < 0 || expectedBytes > maxBytes) {
      throw const FormatException('The export exceeds the 50 MB limit.');
    }
  }

  static const maxBytes = 50 * 1024 * 1024;
  static const chunkBytes = 48 * 1024;
  final String filename;
  final int expectedBytes;
  final _bytes = BytesBuilder(copy: false);
  final createdAt = DateTime.now();
  int _sequence = 0;
  bool _finished = false;

  int get receivedBytes => _bytes.length;

  void add(int sequence, String encoded) {
    if (_finished || sequence != _sequence || encoded.length > 65536) {
      throw const FormatException('Invalid export chunk. Please try again.');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length > chunkBytes ||
        _bytes.length + bytes.length > expectedBytes) {
      throw const FormatException('Export size does not match.');
    }
    _bytes.add(bytes);
    _sequence++;
  }

  Uint8List finish() {
    if (_finished || _bytes.length != expectedBytes) {
      throw const FormatException('Incomplete export. Please try again.');
    }
    _finished = true;
    return _bytes.takeBytes();
  }

  static String safeFilename(String filename) {
    final name = filename
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..') return 'social9-export';
    return name.length > 180 ? name.substring(name.length - 180) : name;
  }
}
