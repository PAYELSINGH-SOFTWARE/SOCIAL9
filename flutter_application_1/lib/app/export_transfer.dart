import 'dart:convert';
import 'bridge_download.dart';

/// Validates a disk-backed export without retaining the exported file in RAM.
class ExportTransfer {
  ExportTransfer({required String filename, required this.expectedBytes})
    : filename = BridgeDownload.safeFilename(filename) {
    if (expectedBytes != null && expectedBytes! < 0) {
      throw const FormatException('Invalid export size.');
    }
  }
  final String filename;
  final int? expectedBytes;
  var receivedBytes = 0;
  var _sequence = 0;
  var _finished = false;

  int validateChunk(int sequence, String encoded) {
    if (_finished || sequence != _sequence || encoded.length > 65536) {
      throw const FormatException('Invalid export chunk.');
    }
    final length = base64Decode(encoded).length;
    if (length > 48 * 1024 ||
        (expectedBytes != null && receivedBytes + length > expectedBytes!)) {
      throw const FormatException('Export size does not match.');
    }
    receivedBytes += length;
    _sequence++;
    return length;
  }

  void finish() {
    if (_finished ||
        (expectedBytes != null && expectedBytes != receivedBytes)) {
      throw const FormatException('Incomplete export.');
    }
    _finished = true;
  }
}
