import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app/bridge_download.dart';
import 'package:flutter_application_1/app/website_policy.dart';

void main() {
  final policy = WebsitePolicy();
  group('website navigation policy', () {
    test('uses the real website and required Render backend', () {
      expect(policy.startPage.toString(), 'https://www.social9.io/login');
      expect(
        WebsitePolicy.backendOrigin,
        'https://social9-backend-ghqu.onrender.com',
      );
    });
    test('keeps every website route, including admin, inside the app', () {
      for (final route in [
        '/dashboard',
        '/create-post',
        '/analytics',
        '/templates',
        '/calendar',
        '/agency',
        '/billing',
        '/admin',
        '/admin/coupons',
        '/admin/operations',
        '/product-tour',
        '/data-deletion',
      ]) {
        expect(policy.isWebsite(policy.page(route)), isTrue, reason: route);
      }
    });
    test(
      'page paths cannot become protocol-relative or external redirects',
      () {
        expect(() => policy.page('//evil.test/login'), throwsArgumentError);
        expect(
          () => policy.page('https://evil.test/login'),
          throwsArgumentError,
        );
        expect(
          policy.appLink(Uri.parse('https://www.social9.io//evil.test')),
          isNull,
        );
        expect(policy.page('/%2f%2fevil.test').host, 'www.social9.io');
      },
    );
    test(
      'rejects lookalike hosts, credentials, insecure HTTP and unusual ports',
      () {
        for (final url in [
          'https://www.social9.io.evil.test/login',
          'https://evil.test/www.social9.io',
          'https://user@www.social9.io/login',
          'http://www.social9.io',
          'https://www.social9.io:444/',
          'javascript:alert(1)',
          'file:///storage/private',
          'data:text/html,bad',
        ]) {
          expect(policy.isWebsite(Uri.parse(url)), isFalse, reason: url);
        }
      },
    );
    test(
      'a configured staging origin does not implicitly trust production',
      () {
        final staging = WebsitePolicy(website: 'https://preview.example.test');
        expect(
          staging.isWebsite(Uri.parse('https://preview.example.test/login')),
          isTrue,
        );
        expect(staging.isWebsite(policy.startPage), isFalse);
      },
    );
    test('configuration must be an HTTPS origin', () {
      for (final origin in [
        'http://localhost:3000',
        'file:///index.html',
        'https://user@social9.io',
        'https://social9.io/login',
        'https://social9.io?url=evil',
        'https://social9.io#fragment',
      ]) {
        expect(() => WebsitePolicy(website: origin), throwsArgumentError);
      }
    });
    test('real provider authorization is classified for browser handoff', () {
      for (final url in [
        'https://www.instagram.com/oauth/authorize?state=test',
        'https://api.instagram.com/oauth/authorize',
        'https://www.linkedin.com/oauth/v2/authorization?state=test',
        'https://www.facebook.com/v24.0/dialog/oauth?state=test',
      ]) {
        expect(
          policy.isProviderAuthorization(Uri.parse(url)),
          isTrue,
          reason: url,
        );
      }
      expect(
        policy.isProviderAuthorization(
          Uri.parse('https://www.linkedin.com/feed'),
        ),
        isFalse,
      );
      expect(
        policy.isProviderAuthorization(
          Uri.parse('https://www.instagram.com.evil.test/oauth/authorize'),
        ),
        isFalse,
      );
    });
    test('checkout frames have a strict hostname boundary', () {
      expect(
        policy.isPaymentFrame(Uri.parse('https://api.razorpay.com/')),
        isTrue,
      );
      expect(
        policy.isPaymentFrame(Uri.parse('https://razorpay.com.evil.test')),
        isFalse,
      );
      expect(
        policy.isPaymentFrame(Uri.parse('http://api.razorpay.com')),
        isFalse,
      );
    });
    test('supports safe external schemes, never local file or JavaScript', () {
      for (final url in [
        'https://help.example.test',
        'mailto:support@social9.io',
        'tel:1234',
        'upi://pay?pa=test',
        'intent://pay#Intent;scheme=upi;end',
      ]) {
        expect(policy.isExternal(Uri.parse(url)), isTrue);
      }
      for (final url in [
        'javascript:alert(1)',
        'file:///private',
        'content://private',
        'data:text/html,x',
        'http://insecure.example.test',
      ]) {
        expect(policy.isExternal(Uri.parse(url)), isFalse);
      }
    });
    test('verification and reset links retain their query tokens on-site', () {
      expect(
        policy.appLink(Uri.parse('social9://verify-email?token=email-token')),
        Uri.parse('https://www.social9.io/verify-email?token=email-token'),
      );
      expect(
        policy.appLink(
          Uri.parse('https://social9.io/reset-password?token=reset-token'),
        ),
        Uri.parse('https://www.social9.io/reset-password?token=reset-token'),
      );
      expect(
        policy.appLink(Uri.parse('social9://accounts?connected=instagram')),
        Uri.parse('https://www.social9.io/accounts?connected=instagram'),
      );
    });
    test(
      'app links cannot redirect to an arbitrary origin or custom route',
      () {
        for (final url in [
          'https://evil.test/reset-password?token=t',
          'social9://evil.test',
          'social9://accounts@evil.test',
          'social9:///../evil',
          'javascript:alert(1)',
          'social9://service/auth/me',
        ]) {
          expect(policy.appLink(Uri.parse(url)), isNull, reason: url);
        }
      },
    );
  });
  group('bounded export assembly', () {
    test('reassembles ordered binary chunks, not just text/CSV', () {
      final download = BridgeDownload(filename: 'photo.jpg', expectedBytes: 5);
      download.add(0, base64Encode([0, 128, 255]));
      download.add(1, base64Encode([25, 1]));
      expect(download.finish(), [0, 128, 255, 25, 1]);
      expect(() => download.finish(), throwsFormatException);
    });
    test('rejects missing or out-of-order chunks and truncated exports', () {
      final download = BridgeDownload(filename: 'report.csv', expectedBytes: 5);
      expect(() => download.add(1, base64Encode([1])), throwsFormatException);
      expect(() => download.finish(), throwsFormatException);
    });
    test('rejects oversized and invalid base64 payloads', () {
      expect(
        () => BridgeDownload(
          filename: 'big',
          expectedBytes: BridgeDownload.maxBytes + 1,
        ),
        throwsFormatException,
      );
      expect(
        () => BridgeDownload(filename: 'negative', expectedBytes: -1),
        throwsFormatException,
      );
      final download = BridgeDownload(filename: 'small', expectedBytes: 1);
      expect(
        () => download.add(0, base64Encode([1, 2])),
        throwsFormatException,
      );
      expect(() => download.add(0, '%invalid%'), throwsFormatException);
    });
    test('accepts an empty export and sanitizes filenames', () {
      final download = BridgeDownload(
        filename: '../../report.csv',
        expectedBytes: 0,
      );
      expect(download.filename, 'report.csv');
      expect(download.finish(), isEmpty);
      expect(BridgeDownload.safeFilename(r'C:\private\cover.jpg'), 'cover.jpg');
      expect(BridgeDownload.safeFilename(''), 'social9-export');
      expect(BridgeDownload.safeFilename('../..'), 'social9-export');
    });
  });
}
