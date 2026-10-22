import 'dart:js_interop';

@JS('window.open')
external _Popup? _open(String url, String target, String features);

extension type _Popup(JSObject _) implements JSObject {
  external set location(String value);
  external set opener(JSAny? value);
  external bool get closed;
  external void close();
}

class OAuthWindow {
  OAuthWindow._(this._popup);
  final _Popup _popup;
  bool get closed => _popup.closed;
  Future<void> navigate(String url) async => _popup.location = url;
  void close() => _popup.close();
}

OAuthWindow? reserveOAuthWindow() {
  final popup = _open('about:blank', '_blank', 'popup,width=560,height=780');
  if (popup == null) return null;
  popup.opener = null;
  return OAuthWindow._(popup);
}
