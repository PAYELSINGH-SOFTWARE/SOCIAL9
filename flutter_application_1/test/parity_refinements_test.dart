import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app/export_transfer.dart';
import 'package:flutter_application_1/app/website_policy.dart';

void main() {
  test('browser launcher preserves route, query and fragment', () {
    final target = WebsitePolicy().browserDestination(
      Uri.parse('http://localhost:3000/calendar?brand=4#day-23'),
    );
    expect(target.toString(), 'https://www.social9.io/calendar?brand=4#day-23');
  });
  test('launcher root still opens login and retains its query/fragment', () {
    final target = WebsitePolicy().browserDestination(
      Uri.parse('http://localhost:3000/?plan=starter#pricing'),
    );
    expect(
      target.toString(),
      'https://www.social9.io/login?plan=starter#pricing',
    );
  });
  test('disk export metadata does not enforce the previous 50 MB limit', () {
    final export = ExportTransfer(
      filename: '../../large.csv',
      expectedBytes: 100 * 1024 * 1024,
    );
    expect(export.filename, 'large.csv');
    expect(export.expectedBytes, 100 * 1024 * 1024);
  });
  test(
    'streaming export validates chunks and final length without retaining bytes',
    () {
      final export = ExportTransfer(
        filename: 'report.csv',
        expectedBytes: null,
      );
      export.validateChunk(0, base64Encode([0, 128, 255]));
      export.validateChunk(1, base64Encode([1, 2]));
      expect(export.receivedBytes, 5);
      export.finish();
      expect(
        () => export.validateChunk(2, base64Encode([1])),
        throwsFormatException,
      );
      expect(() => export.finish(), throwsFormatException);
    },
  );
  test(
    'streaming export rejects duplicate chunks, oversized messages and truncation',
    () {
      final export = ExportTransfer(filename: 'report.csv', expectedBytes: 4);
      expect(
        () => export.validateChunk(1, base64Encode([0])),
        throwsFormatException,
      );
      expect(() => export.validateChunk(0, 'A' * 65540), throwsFormatException);
      expect(() => export.finish(), throwsFormatException);
      expect(
        () => ExportTransfer(filename: 'x', expectedBytes: -1),
        throwsFormatException,
      );
    },
  );
}
