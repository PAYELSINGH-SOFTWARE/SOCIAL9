import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;
@JS('document')
external _Document get _document;
extension type _Document(JSObject _) implements JSObject {
  external JSObject createElement(String tag);
  external _Head get head;
}
extension type _Head(JSObject _) implements JSObject {
  external void appendChild(JSObject child);
}
@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSObject options);
  external void open();
  external void on(String name, JSFunction handler);
}

Future<void> _loadScript() async {
  if (_window.hasProperty('Razorpay'.toJS).toDart) return;
  final ready = Completer<void>();
  final script = _document.createElement('script');
  script.setProperty(
    'src'.toJS,
    'https://checkout.razorpay.com/v1/checkout.js'.toJS,
  );
  script.setProperty(
    'onload'.toJS,
    (() {
      if (!ready.isCompleted) ready.complete();
    }).toJS,
  );
  script.setProperty(
    'onerror'.toJS,
    (() {
      if (!ready.isCompleted) {
        ready.completeError(Exception('Unable to load secure checkout.'));
      }
    }).toJS,
  );
  _document.head.appendChild(script);
  await ready.future.timeout(const Duration(seconds: 30));
}

Future<Map<String, dynamic>?> openCheckout(Map session) async {
  await _loadScript();
  final done = Completer<Map<String, dynamic>?>();
  final options =
      {
            'key': session['key_id'],
            'order_id': session['order_id'],
            'name': session['name'],
            'description': session['description'],
            'prefill': {
              'name': session['customer_name'],
              'email': session['customer_email'],
            },
            'theme': {'color': '#6D4AFF'},
          }.jsify()!
          as JSObject;
  options.setProperty(
    'handler'.toJS,
    ((JSObject response) {
      if (!done.isCompleted) {
        done.complete(Map<String, dynamic>.from(response.dartify() as Map));
      }
    }).toJS,
  );
  final modal = JSObject();
  modal.setProperty(
    'ondismiss'.toJS,
    (() {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
  );
  options.setProperty('modal'.toJS, modal);
  final checkout = _Razorpay(options);
  checkout.on(
    'payment.failed',
    ((JSObject response) {
      final error = response.dartify() as Map;
      if (!done.isCompleted) {
        done.completeError(
          Exception(
            (error['error'] as Map?)?['description']?.toString() ??
                'Payment failed.',
          ),
        );
      }
    }).toJS,
  );
  checkout.open();
  return done.future;
}
