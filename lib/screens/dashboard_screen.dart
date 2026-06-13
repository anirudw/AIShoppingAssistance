
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import '../widgets/cart_item.dart';
import '../models/cart_item_model.dart';
import '../services/chromadb_client.dart';
import '../services/cart_service.dart';
import '../services/inventory_service.dart';

class DashboardScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DashboardScreen({super.key, required this.cameras});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _DbStatus { unknown, ok, error }

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  final ChromaDbClient _chromaClient = ChromaDbClient();
  final TextEditingController _ragController = TextEditingController();
  late AnimationController _cursorController;
  late AnimationController _pulseController;
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isSearchingImage = false;
  double _shutterScale = 1.0;
  bool _showZoomSlider = false;
  double _zoomLevel = 1.0;
  double _zoomLevelAtStart = 1.0;
  bool _isSliderPersistent = false;
  Offset _dragStartPos = Offset.zero;
  double _zoomButtonScale = 1.0;
  bool _isHardwareZoomSupported = false;
  double _minHardwareZoom = 1.0;
  double _maxHardwareZoom = 1.0;

  // Cart database service (session-scoped, resets on checkout)
  final CartService _cartService = CartService();
  bool _isCheckingOut = false;

  // DB connectivity state — drives the status pill in the app bar
  _DbStatus _dbStatus = _DbStatus.unknown;

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
    // Listen to cart changes so the widget rebuilds reactively.
    _cartService.addListener(_onCartChanged);
    // Silently check DB status on startup so indicator reflects real state.
    _refreshDbStatus();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    
    // Use low resolution on mobile: CLIP only needs 224x224px, and high-res
    // captures cause a multi-megabyte JPEG write to disk, adding 2-3s of latency.
    // Web uses in-memory Blobs so resolution has no disk-write overhead there.
    const resolution = kIsWeb ? ResolutionPreset.medium : ResolutionPreset.low;
    _cameraController = CameraController(
      widget.cameras[0],
      resolution,
      enableAudio: false,
      imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
    );
    
    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _checkHardwareZoomSupport();
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  Future<void> _checkHardwareZoomSupport() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final minZoom = await _cameraController!.getMinZoomLevel();
        final maxZoom = await _cameraController!.getMaxZoomLevel();
        if (maxZoom > minZoom) {
          if (mounted) {
            setState(() {
              _minHardwareZoom = minZoom;
              _maxHardwareZoom = maxZoom;
              _isHardwareZoomSupported = true;
            });
          }
        }
      } catch (e) {
        debugPrint("Hardware zoom not supported: $e");
      }
    }
  }

  Future<void> _updateHardwareZoom(double level) async {
    if (_isHardwareZoomSupported && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final targetZoom = _minHardwareZoom + (level - 1.0) * ((_maxHardwareZoom - _minHardwareZoom) / 2.0);
        await _cameraController!.setZoomLevel(targetZoom.clamp(_minHardwareZoom, _maxHardwareZoom));
      } catch (e) {
        _isHardwareZoomSupported = false;
        debugPrint("Hardware zoom failed, disabling: $e");
      }
    }
  }

  @override
  void dispose() {
    _cartService.removeListener(_onCartChanged);
    _cameraController?.dispose();
    _cursorController.dispose();
    _pulseController.dispose();
    _ragController.dispose();
    super.dispose();
  }

  Future<void> _checkoutCart() async {
    if (_cartService.isEmpty || _isCheckingOut) return;

    final double total = _cartService.totalPrice;

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF23C8D9).withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFF23C8D9),
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Confirm Checkout',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You are about to checkout ${_cartService.itemCount} item${_cartService.itemCount == 1 ? '' : 's'} for a total of',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF23C8D9),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF23C8D9),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCheckingOut = true);

    // Simulate brief payment processing
    await Future.delayed(const Duration(milliseconds: 800));

    await _cartService.checkout();

    if (!mounted) return;
    setState(() => _isCheckingOut = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              'Order placed! ₹${total.toStringAsFixed(2)} charged.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _takePictureAndSearch() async {
    if (_isSearchingImage) return;

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
        // Show confirmation sheet — CLIP can confuse similar-looking products
        // (e.g. different Lays flavours). User verifies before cart is updated.
        final confirmed = await _showItemConfirmSheet(item);
        if (confirmed == true && mounted) {
          _cartService.addItem(item);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.name} added to cart!'),
              backgroundColor: const Color(0xFF111827),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else if (mounted) {
        // Distance exceeded threshold — no confident match found
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Item not recognized. Try a closer scan.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF111827),
            duration: Duration(seconds: 2),
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

  /// Shows a confirmation bottom sheet for the detected item.
  /// Returns true if user confirmed, false/null if dismissed.
  Future<bool?> _showItemConfirmSheet(CartItemModel item) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFFF3F4F6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(imageUrl: item.imageUrl, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Item detected',
                          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${item.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF23C8D9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF23C8D9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Add to Cart', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Not this item',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRagSheet() {
    _ragController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ask Chef RAG',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ragController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Ask anything about the products...',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: (_) {
                    Navigator.pop(ctx);
                    _askChefRag();
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _askChefRag();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF23C8D9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Ask', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _askChefRag() async {
    if (_ragController.text.trim().isEmpty) return;
    
    final prompt = _ragController.text;
    _ragController.clear();
    
    final response = await _chromaClient.askChefRag(prompt);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF111827),
        ),
      );
    }
  }

  /// Silent background check — updates the indicator, no snackbar.
  Future<void> _refreshDbStatus() async {
    final chromaStatus = await _chromaClient.checkConnectivity();
    final supabaseStatus = await InventoryService().checkConnectivity();
    if (!mounted) return;
    final allOk = chromaStatus.startsWith('Connected') && supabaseStatus.startsWith('Connected');
    setState(() => _dbStatus = allOk ? _DbStatus.ok : _DbStatus.error);
  }

  Future<void> _checkDbStatus() async {
    // Show a loading snackbar while checking
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking database connections...', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueGrey,
        duration: Duration(milliseconds: 800),
      ),
    );

    final chromaStatus = await _chromaClient.checkConnectivity();
    final supabaseStatus = await InventoryService().checkConnectivity();

    if (mounted) {
      final isChromaOk = chromaStatus.startsWith("Connected");
      final isSupabaseOk = supabaseStatus.startsWith("Connected");

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ChromaDB: $chromaStatus', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Supabase: $supabaseStatus', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: (isChromaOk && isSupabaseOk)
              ? const Color(0xFF22C55E)
              : const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
        ),
      );
      // Also update the indicator
      setState(() => _dbStatus = (isChromaOk && isSupabaseOk) ? _DbStatus.ok : _DbStatus.error);
    }
  }

  void _incrementQuantity(int index) => _cartService.incrementQuantity(index);

  void _decrementQuantity(int index) => _cartService.decrementQuantity(index);

  void _removeItem(int index) => _cartService.removeItem(index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: _buildAppBar(),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              _buildCameraViewport(),
              Expanded(
                child: _buildShoppingZone(),
              ),
            ],
          ),
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
                color: const Color(0xFF1A1A1A).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFF1A1A1A).withValues(alpha: 0.04)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.06),
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
              GestureDetector(
                onTap: _checkDbStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1A1A1A).withValues(alpha: 0.04)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final dotColor = switch (_dbStatus) {
                            _DbStatus.ok      => const Color(0xFF22C55E),
                            _DbStatus.error   => const Color(0xFFEF4444),
                            _DbStatus.unknown => const Color(0xFF9CA3AF),
                          };
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor.withValues(
                                alpha: _dbStatus == _DbStatus.unknown
                                    ? 0.6
                                    : 0.3 + 0.7 * _pulseController.value,
                              ),
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
                      Container(width: 1, height: 12, color: const Color(0xFF1A1A1A).withValues(alpha: 0.08)),
                      const SizedBox(width: 6),
                      Text(
                        switch (_dbStatus) {
                          _DbStatus.ok      => 'Live',
                          _DbStatus.error   => 'Error',
                          _DbStatus.unknown => 'Checking…',
                        },
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: switch (_dbStatus) {
                            _DbStatus.ok      => const Color(0xFF22C55E),
                            _DbStatus.error   => const Color(0xFFEF4444),
                            _DbStatus.unknown => const Color(0xFF9CA3AF),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF1A1A1A).withValues(alpha: 0.04)),
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
              // FIXED: Correct portrait aspect ratio cropping using FittedBox + AspectRatio
              if (_isCameraInitialized && _cameraController != null)
                Positioned.fill(
                  child: AnimatedScale(
                    scale: _zoomLevel,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width,
                        child: AspectRatio(
                          // Invert landscape aspect ratio constraints for seamless portrait preview paths
                          aspectRatio: 1 / _cameraController!.value.aspectRatio,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
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
              
              // Scanning Reticle Overlay
              Center(
                child: SizedBox(
                  width: 180.0,
                  height: 180.0,
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
                                  const Color(0xFF23C8D9).withValues(alpha: 0.2),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              // Zoom Level HUD Overlay
              Center(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showZoomSlider ? 1.0 : 0.0,
                    curve: Curves.easeInOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${_zoomLevel.toStringAsFixed(1)}x',
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
                          color: const Color(0xFF1A1A1A).withValues(alpha: 0.6),
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
                                value: _zoomLevel,
                                min: 1.0,
                                max: 3.0,
                                onChanged: (val) {
                                  setState(() {
                                    _zoomLevel = val;
                                  });
                                  _updateHardwareZoom(val);
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
                          _zoomLevelAtStart = _zoomLevel;
                        });
                      },
                      onLongPressMoveUpdate: (details) {
                        final double dx = details.globalPosition.dx - _dragStartPos.dx;
                        final double newZoom = (_zoomLevelAtStart - (dx / 70.0)).clamp(1.0, 3.0);
                        setState(() {
                          _zoomLevel = newZoom;
                        });
                        _updateHardwareZoom(newZoom);
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
                                : const Color(0xFF1A1A1A).withValues(alpha: 0.6),
                            boxShadow: _showZoomSlider 
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF23C8D9).withValues(alpha: 0.4),
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
                  if (!_cartService.isEmpty) ...[
                    Text(
                      '₹${_cartService.totalPrice.toStringAsFixed(2)}',
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
                      color: const Color(0xFF23C8D9).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_cartService.itemCount} Items',
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
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_cartService.isEmpty) ...[
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
                                    color: const Color(0xFF23C8D9).withValues(alpha: 0.05),
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
                            itemCount: _cartService.items.length,
                            itemBuilder: (context, index) {
                              final item = _cartService.items[index];
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
                                onDismissed: (_) => _removeItem(index),
                                child: CartItem(
                                  imageUrl: item.imageUrl,
                                  name: item.name,
                                  details: "${item.quantity} ${item.quantity == 1 ? 'Item' : 'Items'} • ₹${(item.price * item.quantity).toStringAsFixed(2)}",
                                  quantity: item.quantity,
                                  onIncrement: () => _incrementQuantity(index),
                                  onDecrement: () => _decrementQuantity(index),
                                  onRemove: () => _removeItem(index),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // ── Checkout Bar ──────────────────────────────────────
                if (!_cartService.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                    child: _buildCheckoutBar(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF23C8D9), Color(0xFF0EA5B5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23C8D9).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isCheckingOut ? null : _checkoutCart,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_cartService.itemCount} item${_cartService.itemCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${_cartService.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                _isCheckingOut
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        children: [
                          const Text(
                            'Checkout',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 14,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showRagSheet,
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
                  const SizedBox(width: 74),
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
        ),
        _buildShutterButton(),
      ],
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
                color: const Color(0xFF23C8D9).withValues(alpha: 0.3),
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

    final pathTL = Path()
      ..moveTo(0, r + len)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(r + len, 0);
    canvas.drawPath(pathTL, paint);

    final pathTR = Path()
      ..moveTo(w - (r + len), 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, r + len);
    canvas.drawPath(pathTR, paint);

    final pathBR = Path()
      ..moveTo(w, h - (r + len))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(w - (r + len), h);
    canvas.drawPath(pathBR, paint);

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