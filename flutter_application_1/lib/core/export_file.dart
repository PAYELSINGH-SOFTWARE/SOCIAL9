import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> exportCsv(String filename, List<List<Object?>> rows) async {
  String cell(Object? value) {
    var text = value?.toString() ?? '';
    if (RegExp(r'^[=+@\-\t\r\n]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  final text =
      '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}';
  await FilePicker.platform.saveFile(
    dialogTitle: 'Export report',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: Uint8List.fromList(utf8.encode(text)),
  );
}
