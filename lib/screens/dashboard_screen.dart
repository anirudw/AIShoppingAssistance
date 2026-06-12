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

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  final ChromaDbClient _chromaClient = ChromaDbClient();
  final TextEditingController _ragController = TextEditingController();
  late AnimationController _cursorController;
  late AnimationController _pulseController;
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isSearchingImage = false;
  bool _isLoadingRag = false;
  double _shutterScale = 1.0;
  bool _showZoomSlider = false;
  double _reticleSize = 200.0;
  bool _isSliderPersistent = false;
  Offset _dragStartPos = Offset.zero;
  double _reticleSizeAtStart = 200.0;
  double _zoomButtonScale = 1.0;

  // Shopping Cart State
  final List<CartItemModel> _cartItems = [];

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
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
      debugPrint("Camera initialization failed: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cursorController.dispose();
    _pulseController.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera unavailable. Triggering search anyway!'),
            backgroundColor: Color(0xFF111827),
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
            content: Text('${item.name} added to cart!'),
            backgroundColor: const Color(0xFF111827),
            action: SnackBarAction(
              label: 'OK',
              textColor: const Color(0xFF23C8D9),
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error taking picture or searching: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error searching item', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFFEF4444),
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
          content: Text(response, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF111827),
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
          backgroundColor: status.startsWith("Connected") ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
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

  double get _totalPrice {
    double total = 0;
    for (var item in _cartItems) {
      total += item.price * item.quantity;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Main Layout Column
          Column(
            children: [
              _buildCameraViewport(),
              Expanded(
                child: _buildShoppingZone(),
              ),
            ],
          ),
          
          // Floating Bottom Navigation Bar
          Positioned(
            bottom: 20,
            left: MediaQuery.of(context).size.width * 0.05,
            right: MediaQuery.of(context).size.width * 0.05,
            child: _buildBottomNavBar(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: SafeArea(
        child: Container(
          height: 72,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.black.withOpacity(0.04)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Profile
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuD5kgloqF28sbeXcgXIox5_oyy81AA-sTPCmh4snzeCupftRWc_HIZQE5F_Cf_GiPa_KPC94tVUKN9tyTFZeCixqOx4-o0cLR9NMhZxawHQQk2gzGeztGgi5A8ID_-Oxuuuo8g7l8oHwdf1TQaawC5PRuG-y4RPR534sjtZpqN2YRR8tEBCR246KSvsrsUvz2KeUcjurNrlWpw_WNbPQ2bz6xwT_SL-Sdb_ZXTv-q-7lFAEe5HhID0111iWfukZnSFMbjHVKjr9",
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              
              // Status Pill
              GestureDetector(
                onTap: _checkDbStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black.withOpacity(0.04)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF22C55E).withOpacity(0.3 + 0.7 * _pulseController.value),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'DB Status',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(width: 1, height: 12, color: Colors.black.withOpacity(0.08)),
                      const SizedBox(width: 6),
                      const Text(
                        'Live',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Notification Bell
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.black.withOpacity(0.04)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_outlined,
                      color: Color(0xFF111827),
                      size: 22,
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF23C8D9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewport() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.33,
          color: const Color(0xFF1A1A1A),
          child: Stack(
            children: [
              // Background Camera Feed
              if (_isCameraInitialized && _cameraController != null)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize?.width ?? 1,
                      height: _cameraController!.value.previewSize?.height ?? 1,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF1A1A1A),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF23C8D9)),
                    ),
                  ),
                ),
              
              // Scanning Reticle Overlay (Rounded Cutout Corners)
              Center(
                child: SizedBox(
                  width: _reticleSize,
                  height: _reticleSize,
                  child: CustomPaint(
                    painter: ReticlePainter(
                      color: const Color(0xFF23C8D9),
                      strokeWidth: 3.5,
                      borderRadius: 16,
                      arcLength: 20,
                    ),
                    child: _isSearchingImage
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFF23C8D9).withOpacity(0.2),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              // Zoom Level HUD Overlay (Glassmorphic center badge)
              Center(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showZoomSlider ? 1.0 : 0.0,
                    curve: Curves.easeInOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${(240.0 / _reticleSize).toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Zoom Button & Slider
              Positioned(
                bottom: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _showZoomSlider ? 1.0 : 0.0,
                      curve: Curves.easeInOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: _showZoomSlider ? 140 : 0,
                        height: 32,
                        margin: EdgeInsets.only(right: _showZoomSlider ? 8 : 0),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: OverflowBox(
                          minWidth: 0,
                          maxWidth: 140,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 140,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF23C8D9),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: _reticleSize,
                                min: 100.0,
                                max: 240.0,
                                onChanged: (val) {
                                  setState(() {
                                    _reticleSize = val;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSliderPersistent = !_isSliderPersistent;
                          _showZoomSlider = _isSliderPersistent;
                          _zoomButtonScale = 1.15;
                        });
                        Future.delayed(const Duration(milliseconds: 150), () {
                          if (mounted) {
                            setState(() {
                              _zoomButtonScale = 1.0;
                            });
                          }
                        });
                      },
                      onLongPressStart: (details) {
                        setState(() {
                          _showZoomSlider = true;
                          _zoomButtonScale = 1.25;
                          _dragStartPos = details.globalPosition;
                          _reticleSizeAtStart = _reticleSize;
                        });
                      },
                      onLongPressMoveUpdate: (details) {
                        final double dx = details.globalPosition.dx - _dragStartPos.dx;
                        setState(() {
                          _reticleSize = (_reticleSizeAtStart + dx).clamp(100.0, 240.0);
                        });
                      },
                      onLongPressEnd: (details) {
                        setState(() {
                          _zoomButtonScale = 1.0;
                          if (!_isSliderPersistent) {
                            _showZoomSlider = false;
                          }
                        });
                      },
                      child: AnimatedScale(
                        scale: _zoomButtonScale,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutBack,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _showZoomSlider 
                                ? const Color(0xFF23C8D9) 
                                : Colors.black.withOpacity(0.6),
                            boxShadow: _showZoomSlider 
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF23C8D9).withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _showZoomSlider ? Icons.zoom_out : Icons.zoom_in,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildShoppingZone() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Fixed)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Cart',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_cartItems.isNotEmpty) ...[
                    Text(
                      'Total ₹${_totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF23C8D9),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23C8D9).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_cartItems.length} Items',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF23C8D9),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable Cart Contents
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_cartItems.isEmpty) ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF23C8D9).withOpacity(0.05),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: Color(0xFF23C8D9),
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Scan an item to add it to your cart',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ] else ...[
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cartItems.length,
                      itemBuilder: (context, index) {
                        final item = _cartItems[index];
                        return Dismissible(
                          key: Key(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          onDismissed: (direction) {
                            _removeItem(index);
                          },
                          child: CartItem(
                            imageUrl: item.imageUrl,
                            name: item.name,
                            details: item.details,
                            quantity: item.quantity,
                            onIncrement: () => _incrementQuantity(index),
                            onDecrement: () => _decrementQuantity(index),
                            onRemove: () => _removeItem(index),
                          ),
                        );
                      },
                    ),
                  ],

                  _buildAssistantSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantSection() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF23C8D9).withOpacity(0.08),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF23C8D9),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask Chef AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Get instant answers about recipes, ingredients and more.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAssistantBar(),
        ],
      ),
    );
  }

  Widget _buildAssistantBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF23C8D9), Color(0xFF0EAFC4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ragController,
              style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
              decoration: const InputDecoration(
                hintText: "Ask Chef AI...",
                hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _askChefRag(),
            ),
          ),
          if (_isLoadingRag)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF23C8D9)),
            )
          else
            GestureDetector(
              onTap: _askChefRag,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF23C8D9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 82,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Chat Tab
              Expanded(
                child: InkWell(
                  onTap: () {},
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, color: Color(0xFF9CA3AF), size: 22),
                      SizedBox(height: 4),
                      Text(
                        'Chat',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Center Shutter Button (74x74, white ring, slight elevation, scale animation on press)
              _buildShutterButton(),
              
              // Voice Tab
              Expanded(
                child: InkWell(
                  onTap: () {},
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_none, color: Color(0xFF9CA3AF), size: 22),
                      SizedBox(height: 4),
                      Text(
                        'Voice',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _shutterScale = 0.92;
        });
      },
      onTapUp: (_) {
        setState(() {
          _shutterScale = 1.0;
        });
        _takePictureAndSearch();
      },
      onTapCancel: () {
        setState(() {
          _shutterScale = 1.0;
        });
      },
      child: AnimatedScale(
        scale: _shutterScale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF23C8D9),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF23C8D9).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isSearchingImage
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }
}

class ReticlePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double borderRadius;
  final double arcLength;

  ReticlePainter({
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
    required this.arcLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double w = size.width;
    final double h = size.height;
    final double r = borderRadius;
    final double len = arcLength;

    // Top-Left
    final pathTL = Path()
      ..moveTo(0, r + len)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(r + len, 0);
    canvas.drawPath(pathTL, paint);

    // Top-Right
    final pathTR = Path()
      ..moveTo(w - (r + len), 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, r + len);
    canvas.drawPath(pathTR, paint);

    // Bottom-Right
    final pathBR = Path()
      ..moveTo(w, h - (r + len))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(w - (r + len), h);
    canvas.drawPath(pathBR, paint);

    // Bottom-Left
    final pathBL = Path()
      ..moveTo(r + len, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, h - (r + len));
    canvas.drawPath(pathBL, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
