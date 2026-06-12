import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import '../widgets/cart_item.dart';
import '../models/cart_item_model.dart';
import '../services/chromadb_client.dart';

class DashboardScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DashboardScreen({super.key, required this.cameras});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  final ChromaDbClient _chromaClient = ChromaDbClient();
  final TextEditingController _ragController = TextEditingController();
  late AnimationController _cursorController;
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isSearchingImage = false;
  bool _isLoadingRag = false;

  // Shopping Cart State
  final List<CartItemModel> _cartItems = [
    CartItemModel(
      id: "1",
      name: "Organic Milk",
      details: "1 Gallon • \$4.99",
      imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuAdbyeHqrfULuAlpcMzTPG_evGJahFiTkuTn2OiFv7WQyozC0YE6hsWRBWuP7DdvenBb8AcDX6uoher5WVwA9-Tv9dgM8Xuc8vI2fITLKqkZXW_9KsN0iPsb7I57ZWAS4ArN2jv38hoR-sH_FKTswGwD730BTY1pLg8sXK4KM9ViFFzwudDpA0oqbUEsLfA9wqK3CNtx2gXeK4J9B-ELGLyfPA0eOYk9EY55Wzp7VagS5Phnx7CzKNCum9NlHa0zOvW4TxHumOe",
      price: 4.99,
      quantity: 1,
    ),
    CartItemModel(
      id: "2",
      name: "Sourdough Bread",
      details: "500g • \$3.50",
      imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuC6-KsKEKrOZ7iZcg4XGooyrGJRtbzTPqsWgy2nlx_aooyRxXntvHnjWDPDMs_tZ5VgUYxWbirZvipey4n8Ji-HDdiZHBXSL9L02OHYSPwOta9kBlsCRJqvIcKZREdfDFDYZ9wUr6aeb_1IYHHzEbTZD99gKaUg0l69BOlCPlu3BGFMIu2nQcEEsWTQNXQIei8W-nvXAaIvLCVe0BAO4up3ONg-YVYzerR0-QL9E5lIeG45kYOEA0Jzs1sRmnkRAIWfahY3EmXb",
      price: 3.50,
      quantity: 1,
    ),
    CartItemModel(
      id: "3",
      name: "Fresh Tomatoes",
      details: "1kg • \$2.99",
      imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuBwh1mdz1beJDLuTJV8XLzxTM-6ddr1fLF_wzlDp2EBefkCVGVXDi-O1G-Q-km1Z56MjRCC1UpchqrPQQQk8EWqYyfOBhYtbChMUyt_-MCrhKWb3WcnPD1lBMCh7DrEGW3eiLHGw3bvltmD5cXc9Vm_Usl_MkGt30XgTzW2CaaVIS2Z-0uRVF35_QZXzWDOWUV2kxj2QHJZ9JNAr_rDhZ5N0bHRZ2WXLdAzI0ge2WACcrYdKT4e7hVX70ke0gDZ7nLB9eBz_Qs-",
      price: 2.99,
      quantity: 2,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    
    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera initialization failed: \$e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cursorController.dispose();
    _ragController.dispose();
    super.dispose();
  }

  Future<void> _takePictureAndSearch() async {
    if (_isSearchingImage) {
      return;
    }

    setState(() => _isSearchingImage = true);

    try {
      XFile capturedPhoto = XFile('');
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        capturedPhoto = await _cameraController!.takePicture();
      } else {
        // Show a temporary snackbar explaining the camera fallback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera unavailable. Triggering search anyway!'),
            backgroundColor: Color(0xFF2A2A2A),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final CartItemModel? item = await _chromaClient.searchItemByPhoto(capturedPhoto);

      if (item != null && mounted) {
        setState(() {
          _cartItems.add(item);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\${item.name} added to cart!'),
            backgroundColor: const Color(0xFF00E0FF),
            action: SnackBarAction(
              label: 'OK',
              textColor: const Color(0xFF131313),
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error taking picture or searching: \$e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: \$e', style: const TextStyle(color: Color(0xFFFFB4AB))),
            backgroundColor: const Color(0xFF2A2A2A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingImage = false);
    }
  }

  Future<void> _askChefRag() async {
    if (_ragController.text.trim().isEmpty) return;
    
    setState(() => _isLoadingRag = true);
    final prompt = _ragController.text;
    _ragController.clear();
    
    final response = await _chromaClient.askChefRag(prompt);
    
    if (mounted) {
      setState(() => _isLoadingRag = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response, style: const TextStyle(color: Color(0xFF00E0FF))),
          backgroundColor: const Color(0xFF2A2A2A),
        ),
      );
    }
  }

  Future<void> _checkDbStatus() async {
    final status = await _chromaClient.checkConnectivity();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status, style: const TextStyle(color: Colors.white)),
          backgroundColor: status.startsWith("Connected") ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _incrementQuantity(int index) {
    setState(() {
      _cartItems[index].quantity++;
    });
  }

  void _decrementQuantity(int index) {
    setState(() {
      if (_cartItems[index].quantity > 1) {
        _cartItems[index].quantity--;
      } else {
        _cartItems.removeAt(index);
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _cartItems.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131313),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Scrollable Content
          SingleChildScrollView(
            child: Column(
              children: [
                _buildCameraViewport(),
                _buildShoppingZone(),
              ],
            ),
          ),
          
          // Floating Assistant Bar
          Positioned(
            bottom: 96,
            left: 20,
            right: 20,
            child: _buildAssistantBar(),
          ),
          
          // Bottom Navigation Bar
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: _buildBottomNavBar(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF131313),
      elevation: 0,
      scrolledUnderElevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: const Color(0xFF3B4B35).withOpacity(0.5),
          height: 1.0,
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3B4B35).withOpacity(0.5)),
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuD5kgloqF28sbeXcgXIox5_oyy81AA-sTPCmh4snzeCupftRWc_HIZQE5F_Cf_GiPa_KPC94tVUKN9tyTFZeCixqOx4-o0cLR9NMhZxawHQQk2gzGeztGgi5A8ID_-Oxuuuo8g7l8oHwdf1TQaawC5PRuG-y4RPR534sjtZpqN2YRR8tEBCR246KSvsrsUvz2KeUcjurNrlWpw_WNbPQ2bz6xwT_SL-Sdb_ZXTv-q-7lFAEe5HhID0111iWfukZnSFMbjHVKjr9",
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'CYBER-CHEF',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00E0FF),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checkDbStatus,
          child: const Text('DB STATUS', style: TextStyle(color: Color(0xFF00E0FF))),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Color(0xFF929090)),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildCameraViewport() {
    return SizedBox(
      height: 309,
      width: double.infinity,
      child: Stack(
        children: [
          // Background Camera Feed
          if (_isCameraInitialized && _cameraController != null)
            Positioned.fill(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 1,
                    height: _cameraController!.value.previewSize?.width ?? 1,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: const Color(0xFF1A1A1A),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E0FF)),
                ),
              ),
            ),
          
          // Scanning Reticle Overlay
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00E0FF).withOpacity(0.1), width: 1),
              ),
              child: Stack(
                children: [
                  _buildReticleCorner(top: 0, left: 0, borderRight: false, borderBottom: false),
                  _buildReticleCorner(top: 0, right: 0, borderLeft: false, borderBottom: false),
                  _buildReticleCorner(bottom: 0, left: 0, borderRight: false, borderTop: false),
                  _buildReticleCorner(bottom: 0, right: 0, borderLeft: false, borderTop: false),
                  if (_isSearchingImage)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF00E0FF).withOpacity(0.2),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Checkout Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E0FF),
                  foregroundColor: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  elevation: 8,
                  shadowColor: const Color(0xFF00E0FF).withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {},
                child: const Text(
                  'PROCEED TO CHECKOUT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReticleCorner({double? top, double? bottom, double? left, double? right, bool borderRight = true, bool borderBottom = true, bool borderLeft = true, bool borderTop = true}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            top: borderTop ? const BorderSide(color: Color(0xFF00E0FF), width: 3) : BorderSide.none,
            bottom: borderBottom ? const BorderSide(color: Color(0xFF00E0FF), width: 3) : BorderSide.none,
            left: borderLeft ? const BorderSide(color: Color(0xFF00E0FF), width: 3) : BorderSide.none,
            right: borderRight ? const BorderSide(color: Color(0xFF00E0FF), width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildShoppingZone() {
    return Container(
      transform: Matrix4.translationValues(0.0, -24.0, 0.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'My Shopping Cart (\${_cartItems.length} Items)',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00E0FF),
                ),
              ),
              const Text(
                '64% BUDGET',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Color(0xFF929090),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Progress Bar
          Container(
            height: 4,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF20201F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.64,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00E0FF),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E0FF).withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Items ListView
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _cartItems.length,
            itemBuilder: (context, index) {
              final item = _cartItems[index];
              return CartItem(
                imageUrl: item.imageUrl,
                name: item.name,
                details: item.details,
                quantity: item.quantity,
                onIncrement: () => _incrementQuantity(index),
                onDecrement: () => _decrementQuantity(index),
                onRemove: () => _removeItem(index),
              );
            },
          ),

          const SizedBox(height: 24),

          // AI Insight Chip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00E0FF).withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E0FF).withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF00E0FF), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Chef's Precision Tip",
                        style: TextStyle(
                          color: Color(0xFF00E0FF),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            color: Color(0xFF929090),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          children: [
                            TextSpan(text: "Buying Tomatoes? Add "),
                            TextSpan(text: "Basil", style: TextStyle(color: Color(0xFF9CEAFF))),
                            TextSpan(text: " and "),
                            TextSpan(text: "Mozzarella", style: TextStyle(color: Color(0xFF9CEAFF))),
                            TextSpan(text: " to unlock \"Neapolitan Precision\" recipes."),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFF004E5D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology, color: Color(0xFFB4EBFA), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ragController,
                  style: const TextStyle(color: Color(0xFFE5E2E1), fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Ask Chef RAG: How do I make Biryani?",
                    hintStyle: TextStyle(color: Color(0xFF929090), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _askChefRag(),
                ),
              ),
              if (_isLoadingRag)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E0FF)),
                )
              else
                FadeTransition(
                  opacity: _cursorController,
                  child: Container(
                    width: 2,
                    height: 16,
                    color: const Color(0xFF00E0FF),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF9CEAFF), size: 20),
                onPressed: _askChefRag,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF131313).withOpacity(0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFF3B4B35).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF929090)),
                onPressed: () {},
              ),
              GestureDetector(
                onTap: _takePictureAndSearch,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E0FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E0FF).withOpacity(0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: _isSearchingImage
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00363D),
                            ),
                          ),
                        )
                      : const Icon(Icons.shutter_speed, color: Color(0xFF00363D)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.mic_none, color: Color(0xFF929090)),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
