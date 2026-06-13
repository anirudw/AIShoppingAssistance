import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item_model.dart';

/// Singleton cart service that acts as the session-scoped cart database.
/// Persists cart state across page refreshes via SharedPreferences.
/// Calling [checkout] atomically clears both the in-memory state and the
/// persisted storage, effectively resetting the cart for a new session.
class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

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
    notifyListeners();
  }

  void incrementQuantity(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index].quantity++;
    _persist();
    notifyListeners();
  }

  void decrementQuantity(int index) {
    if (index < 0 || index >= _items.length) return;
    if (_items[index].quantity > 1) {
      _items[index].quantity--;
    } else {
      _items.removeAt(index);
    }
    _persist();
    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    _persist();
    notifyListeners();
  }

  // ─────────────────────────── Checkout ──────────────────────────────────────

  /// Completes the checkout: clears the in-memory cart and wipes the persisted
  /// storage so the next session starts fresh.
  Future<void> checkout() async {
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
