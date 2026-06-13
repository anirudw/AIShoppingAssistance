import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CartItem extends StatefulWidget {
  final String imageUrl;
  final String name;
  final String details;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const CartItem({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.details,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  State<CartItem> createState() => _CartItemState();
}

class _CartItemState extends State<CartItem> {
  late int _previousQuantity;

  @override
  void initState() {
    super.initState();
    _previousQuantity = widget.quantity;
  }

  @override
  void didUpdateWidget(CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity) {
      _previousQuantity = oldWidget.quantity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: const Color(0xFFF3F4F6),
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF23C8D9)),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.shopping_bag_outlined,
                        color: Color(0xFF9CA3AF),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x0F1A1A1A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x051A1A1A),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: widget.onDecrement,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.remove, size: 14, color: Color(0xFF23C8D9)),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final childKey = child.key as ValueKey<int>;
                    final isCurrent = childKey.value == widget.quantity;
                    final goingUp = widget.quantity > _previousQuantity;
                    final offset = goingUp ? 1.0 : -1.0;

                    return ClipRect(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: isCurrent ? Offset(0.0, offset) : Offset(0.0, -offset),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey<int>(widget.quantity),
                    width: 18,
                    height: 20,
                    child: Center(
                      child: Text(
                        widget.quantity.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onIncrement,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.add, size: 14, color: Color(0xFF23C8D9)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
