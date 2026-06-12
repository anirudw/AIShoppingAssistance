class CartItemModel {
  final String id;
  final String name;
  final String details;
  final String imageUrl;
  final double price;
  int quantity;

  CartItemModel({
    required this.id,
    required this.name,
    required this.details,
    required this.imageUrl,
    required this.price,
    this.quantity = 1,
  });

  CartItemModel copyWith({
    String? id,
    String? name,
    String? details,
    String? imageUrl,
    double? price,
    int? quantity,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      details: details ?? this.details,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }
}
