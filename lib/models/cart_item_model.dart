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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'details': details,
      'imageUrl': imageUrl,
      'price': price,
      'quantity': quantity,
    };
  }

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      details: json['details'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int? ?? 1,
    );
  }
}
