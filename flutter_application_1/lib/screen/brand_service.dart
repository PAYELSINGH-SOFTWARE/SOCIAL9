import '../core/api_client.dart';
import '../core/workspace_session.dart';

class BrandService {
  static Future<List<Map<String, dynamic>>> list() async {
    final brands = (await ApiClient.get('/brands') as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (brands.isNotEmpty &&
        !brands.any((item) => item['id'] == WorkspaceSession.brandId.value)) {
      await WorkspaceSession.selectBrand(brands.first['id'] as int);
    }
    return brands;
  }

  static Future<void> create(String name) async {
    final brand =
        await ApiClient.post('/brands', body: {'name': name.trim()}) as Map;
    await WorkspaceSession.selectBrand(brand['id'] as int);
  }
}
