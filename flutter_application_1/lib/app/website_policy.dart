/// Only the first-party website runs inside the application. Provider login
/// belongs in the system browser, not an embedded user agent.
class WebsitePolicy {
  WebsitePolicy({String website = canonicalOrigin})
    : origin = Uri.parse(website) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('SOCIAL9_WEB_URL must be an HTTPS origin.');
    }
  }

  static const canonicalOrigin = 'https://www.social9.io';
  static const backendOrigin = 'https://social9-backend-ghqu.onrender.com';
  final Uri origin;

  Uri page(String path) {
    final reference = Uri.parse(path);
    if (reference.hasScheme ||
        reference.hasAuthority ||
        !path.startsWith('/')) {
      throw ArgumentError('Website navigation must use a local absolute path.');
    }
    return origin.replace(
      path: reference.path,
      query: reference.hasQuery ? reference.query : null,
      fragment: reference.hasFragment ? reference.fragment : null,
    );
  }

  Uri get startPage => page('/login');

  Uri browserDestination(Uri source) {
    final path = source.path == '/' || source.path.endsWith('/index.html')
        ? '/login'
        : source.path;
    return page(path).replace(
      query: source.hasQuery ? source.query : null,
      fragment: source.hasFragment ? source.fragment : null,
    );
  }

  bool isWebsite(Uri url) {
    if (url.scheme != 'https' || url.userInfo.isNotEmpty) return false;
    if (url.origin == origin.origin) return true;
    return {'www.social9.io', 'social9.io'}.contains(origin.host) &&
        {'www.social9.io', 'social9.io'}.contains(url.host) &&
        url.port == 443;
  }

  bool isPaymentFrame(Uri url) =>
      url.scheme == 'https' &&
      url.userInfo.isEmpty &&
      (url.host == 'razorpay.com' || url.host.endsWith('.razorpay.com'));

  bool isExternal(Uri url) =>
      url.userInfo.isEmpty &&
      const {
        'https',
        'mailto',
        'tel',
        'upi',
        'tez',
        'gpay',
        'phonepe',
        'paytmmp',
        'paytm',
        'intent',
      }.contains(url.scheme);

  bool isProviderAuthorization(Uri url) {
    if (url.scheme != 'https' || url.userInfo.isNotEmpty) return false;
    final host = url.host.toLowerCase();
    final path = url.path.toLowerCase();
    if ({
      'instagram.com',
      'www.instagram.com',
      'api.instagram.com',
    }.contains(host)) {
      return path.startsWith('/oauth/authorize');
    }
    if ({'facebook.com', 'www.facebook.com', 'm.facebook.com'}.contains(host)) {
      return RegExp(r'^/(v\d+(\.\d+)?/)?dialog/oauth/?$').hasMatch(path);
    }
    if ({'linkedin.com', 'www.linkedin.com'}.contains(host)) {
      return path.startsWith('/oauth/v2/authorization');
    }
    return (host == 'accounts.google.com' && path.startsWith('/o/oauth2/')) ||
        ({'twitter.com', 'api.twitter.com', 'x.com'}.contains(host) &&
            path.startsWith('/oauth')) ||
        ({'pinterest.com', 'www.pinterest.com'}.contains(host) &&
            path.startsWith('/oauth/')) ||
        ({'threads.net', 'www.threads.net'}.contains(host) &&
            path.startsWith('/oauth/authorize'));
  }

  /// App links may navigate but must never execute script or forward to an
  /// arbitrary host. Authentication tokens remain in the website's own storage.
  Uri? appLink(Uri link) {
    if (isWebsite(link)) {
      if (link.path.startsWith('//')) return null;
      return page(link.path + _suffix(link));
    }
    if (link.scheme != 'social9' || link.userInfo.isNotEmpty) return null;
    final route = link.host.isEmpty ? link.path : '/${link.host}${link.path}';
    if (route.startsWith('//') || route.contains('..')) return null;
    const routes = {
      '/accounts',
      '/verify-email',
      '/reset-password',
      '/login',
      '/dashboard',
      '/calendar',
      '/content',
      '/create-post',
      '/billing',
    };
    if (!routes.contains(route)) return null;
    return page(route + _suffix(link));
  }

  String _suffix(Uri uri) =>
      '${uri.hasQuery ? '?${uri.query}' : ''}'
      '${uri.hasFragment ? '#${uri.fragment}' : ''}';
}
