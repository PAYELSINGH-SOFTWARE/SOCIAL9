import 'dart:async';
import 'dart:io';
import 'package:razorpay_flutter/razorpay_flutter.dart';

Future<Map<String, dynamic>?> openCheckout(Map session) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw Exception('Checkout is available on Android, iOS, and the browser.');
  }
  final completer = Completer<Map<String, dynamic>?>();
  final checkout = Razorpay();
  checkout.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
    PaymentSuccessResponse response,
  ) {
    if (!completer.isCompleted) {
      completer.complete({
        'razorpay_payment_id': response.paymentId,
        'razorpay_order_id': response.orderId,
        'razorpay_signature': response.signature,
      });
    }
  });
  checkout.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
    if (!completer.isCompleted) {
      completer.completeError(
        Exception(response.message ?? 'Payment was cancelled or failed.'),
      );
    }
  });
  try {
    checkout.open({
      'key': session['key_id'],
      'order_id': session['order_id'],
      'currency': session['currency'],
      'name': session['name'],
      'description': session['description'],
      'prefill': {
        'name': session['customer_name'],
        'email': session['customer_email'],
      },
      'theme': {'color': '#6D4AFF'},
    });
    return await completer.future;
  } finally {
    checkout.clear();
  }
}
