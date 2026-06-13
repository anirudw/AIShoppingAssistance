import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  final _supabase = Supabase.instance.client;

  /// Helper to check if credentials are set in .env
  bool _hasCredentials() {
    final url = dotenv.env['SUPABASE_URL'];
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    return url != null && url.isNotEmpty && key != null && key.isNotEmpty;
  }

  /// Queries the 'inventory' table in Supabase for a single product matching the slug.
  Future<Map<String, dynamic>?> getProductBySlug(String slug) async {
    if (!_hasCredentials()) {
      debugPrint('[InventoryService] Cannot query: Supabase credentials are not configured in .env');
      return null;
    }

    debugPrint('[InventoryService] Querying Supabase for slug: "$slug"');
    try {
      final response = await _supabase
          .from('inventory')
          .select('sku, slug, name, price_rupees, staging_dirs')
          .eq('slug', slug)
          .maybeSingle();
      
      if (response != null) {
        debugPrint('[InventoryService] Successfully found product in Supabase: $response');
      } else {
        debugPrint('[InventoryService] No product found in Supabase matching slug: "$slug"');
      }
      return response;
    } catch (e) {
      debugPrint('[InventoryService] Error querying Supabase for slug "$slug": $e');
      return null;
    }
  }

  /// Verifies connection to Supabase by performing a simple query.
  Future<String> checkConnectivity() async {
    if (!_hasCredentials()) {
      return "Failed: Credentials not set in .env";
    }

    try {
      await _supabase
          .from('inventory')
          .select('sku')
          .limit(1);
      return "Connected: OK";
    } on TypeError catch (_) {
      return "Failed: Cast error (check if 'inventory' table exists in Supabase)";
    } catch (e) {
      return "Failed: $e";
    }
  }
}
