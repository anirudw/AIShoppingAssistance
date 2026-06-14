import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item_model.dart';

/// Singleton cart service that acts as the session-scoped cart database.
/// Persists cart state across page refreshes via SharedPreferences and syncs
/// with Supabase for logged-in users.
class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;

  final _supabase = Supabase.instance.client;

  CartService._internal() {
    // Listen for auth state changes to load/clear user cart reactively
    _supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _loadActiveCartFromSupabase(user.id);
      } else {
        _items.clear();
        _persist();
        notifyListeners();
      }
    });
  }

  static const String _cartKey = 'cart_items_v1';

  final List<CartItemModel> _items = [];
  bool _isLoaded = false;

  /// Read-only view of the cart contents.
  List<CartItemModel> get items => List.unmodifiable(_items);

  /// Total item count (sum of quantities).
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Total price in Rupees (₹).
  double get totalPrice =>
      _items.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  bool get isEmpty => _items.isEmpty;

  bool get isLoaded => _isLoaded;

  // ─────────────────────────── Persistence ───────────────────────────────────

  /// Loads cart from SharedPreferences. Call once during app init.
  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cartKey);
      if (raw != null) {
        final List<dynamic> decoded = jsonDecode(raw);
        _items.clear();
        _items.addAll(decoded.map((e) => CartItemModel.fromJson(e)));
      }

      // If already logged in on startup, sync the latest active cart from Supabase
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _loadActiveCartFromSupabase(user.id);
      }
    } catch (e) {
      debugPrint('[CartService] load error: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cartKey,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[CartService] persist error: $e');
    }
  }

  // ────────────────────────── Supabase Syncing ────────────────────────────────

  /// Restoration method to fetch active cart from Supabase on login or app start.
  Future<void> _loadActiveCartFromSupabase(String userId) async {
    try {
      final activeCart = await _supabase
          .from('user_carts')
          .select('items')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (activeCart != null && activeCart['items'] != null) {
        final List<dynamic> dbItems = activeCart['items'] as List<dynamic>;
        _items.clear();
        _items.addAll(dbItems.map((e) => CartItemModel.fromJson(e as Map<String, dynamic>)));
        _persist();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CartService] Error loading active cart from Supabase: $e');
    }
  }

  /// Pushes changes to Supabase in the background whenever the cart is modified.
  Future<void> _syncActiveCart() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final activeCart = await _supabase
          .from('user_carts')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .maybeSingle();

      if (activeCart != null) {
        await _supabase
            .from('user_carts')
            .update({
              'items': _items.map((e) => e.toJson()).toList(),
              'total_price': totalPrice,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', activeCart['id']);
      } else {
        // Only create active cart record if there are items to store
        if (_items.isNotEmpty) {
          await _supabase
              .from('user_carts')
              .insert({
                'user_id': user.id,
                'items': _items.map((e) => e.toJson()).toList(),
                'total_price': totalPrice,
                'status': 'active',
              });
        }
      }
    } catch (e) {
      debugPrint('[CartService] Supabase active cart sync error: $e');
    }
  }

  // ─────────────────────────── CRUD ──────────────────────────────────────────

  /// Adds [item] to the cart. If an item with the same [name] already exists,
  /// its quantity is incremented instead of adding a duplicate.
  void addItem(CartItemModel item) {
    final existingIdx = _items.indexWhere((e) => e.name == item.name);
    if (existingIdx != -1) {
      _items[existingIdx].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    _persist();
    _syncActiveCart();
    notifyListeners();
  }

  void incrementQuantity(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index].quantity++;
    _persist();
    _syncActiveCart();
    notifyListeners();
  }

  void decrementQuantity(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_items[index].quantity > 1) {
      _items[index].quantity--;
      _persist();
      _syncActiveCart();
    } else {
      removeItem(index);
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    _persist();
    // If the cart becomes empty, delete the active cart from Supabase
    final user = _supabase.auth.currentUser;
    if (user != null && _items.isEmpty) {
      _supabase
          .from('user_carts')
          .delete()
          .eq('user_id', user.id)
          .eq('status', 'active')
          .then((_) => null, onError: (e) => debugPrint('[CartService] Error deleting active cart: $e'));
    } else {
      _syncActiveCart();
    }
    notifyListeners();
  }

  // ─────────────────────────── Checkout ──────────────────────────────────────

  /// Completes the checkout: marks the active cart as processed in Supabase,
  /// clears the in-memory cart, and wipes local storage.
  Future<void> checkout() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final activeCart = await _supabase
            .from('user_carts')
            .select('id')
            .eq('user_id', user.id)
            .eq('status', 'active')
            .maybeSingle();

        if (activeCart != null) {
          // Progress state to 'processed'
          await _supabase
              .from('user_carts')
              .update({
                'status': 'processed',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', activeCart['id']);
        } else if (_items.isNotEmpty) {
          // If no active cart exists in DB but we have local items, write direct processed entry
          await _supabase
              .from('user_carts')
              .insert({
                'user_id': user.id,
                'items': _items.map((e) => e.toJson()).toList(),
                'total_price': totalPrice,
                'status': 'processed',
              });
        }
      } catch (e) {
        debugPrint('[CartService] Supabase checkout sync error: $e');
      }
    }

    _items.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cartKey);
    } catch (e) {
      debugPrint('[CartService] checkout clear error: $e');
    }
    notifyListeners();
  }
}
