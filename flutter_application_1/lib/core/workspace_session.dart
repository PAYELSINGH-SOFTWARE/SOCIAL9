import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkspaceSession {
  static final brandId = ValueNotifier<int?>(null);
  static VoidCallback? onExpired;

  static Future<void> restoreBrand() async {
    brandId.value = (await SharedPreferences.getInstance()).getInt(
      'social9_active_brand_id',
    );
  }

  static Future<void> selectBrand(int id) async {
    await (await SharedPreferences.getInstance()).setInt(
      'social9_active_brand_id',
      id,
    );
    brandId.value = id;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'token',
      'user_name',
      'user_email',
      'social9_active_brand_id',
    ]) {
      await prefs.remove(key);
    }
    brandId.value = null;
  }
}
