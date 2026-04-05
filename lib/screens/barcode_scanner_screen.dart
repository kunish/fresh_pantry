import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/open_food_facts_service.dart';
import '../theme/app_theme.dart';

/// Full-screen barcode scanner page.
///
/// Returns a [BarcodeResult] via `Navigator.pop` on success, or `null` when the
/// user taps the back button / close icon.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _isProcessing = true);

    // Look up the barcode via Open Food Facts API.
    final result = await OpenFoodFactsService.lookup(rawValue);

    if (!mounted) return;

    if (result != null) {
      // Product found — return result.
      Navigator.of(context).pop(result);
    } else {
      // Not found — return a minimal result with just the barcode.
      Navigator.of(
        context,
      ).pop(BarcodeResult(productName: rawValue, barcode: rawValue));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Viewfinder overlay
          _buildOverlay(),

          // Top bar
          _buildTopBar(),

          // Bottom instruction
          _buildBottomHint(),

          // Loading overlay
          if (_isProcessing) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ─── Overlay with cut-out viewfinder ─────────────────────────────────

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final top = (constraints.maxHeight - scanAreaSize) / 2;
        final left = (constraints.maxWidth - scanAreaSize) / 2;

        return Stack(
          children: [
            // Semi-transparent background around viewfinder
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.red, // any opaque color for cut-out
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Corner brackets
            Positioned(
              top: top,
              left: left,
              child: _buildCornerBrackets(scanAreaSize),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCornerBrackets(double size) {
    const bracketLength = 32.0;
    const bracketWidth = 3.0;
    const color = AppColors.primaryContainer;
    const radius = Radius.circular(24);

    Widget corner({bool top = false, bool left = false}) {
      return SizedBox(
        width: bracketLength,
        height: bracketLength,
        child: CustomPaint(
          painter: _CornerPainter(
            color: color,
            strokeWidth: bracketWidth,
            topLeft: top && left,
            topRight: top && !left,
            bottomLeft: !top && left,
            bottomRight: !top && !left,
            radius: radius,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: corner(top: true, left: true)),
          Positioned(top: 0, right: 0, child: corner(top: true, left: false)),
          Positioned(bottom: 0, left: 0, child: corner(top: false, left: true)),
          Positioned(
            bottom: 0,
            right: 0,
            child: corner(top: false, left: false),
          ),
        ],
      ),
    );
  }

  // ─── Top bar ─────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
            const Spacer(),
            Text(
              '扫描条码',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            // Torch toggle
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (_, state, _) {
                return IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: Icon(
                    state.torchState == TorchState.on
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: Colors.white,
                    size: 28,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom hint ─────────────────────────────────────────────────────

  Widget _buildBottomHint() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '将条码置于取景框内',
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Loading overlay ─────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.primaryContainer,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              '正在查询商品信息…',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Corner bracket painter ───────────────────────────────────────────────

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;
  final Radius radius;

  const _CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
    this.radius = Radius.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = radius.x;

    final path = Path();

    if (topLeft) {
      path.moveTo(0, h);
      path.lineTo(0, r);
      path.quadraticBezierTo(0, 0, r, 0);
      path.lineTo(w, 0);
    } else if (topRight) {
      path.moveTo(0, 0);
      path.lineTo(w - r, 0);
      path.quadraticBezierTo(w, 0, w, r);
      path.lineTo(w, h);
    } else if (bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, h - r);
      path.quadraticBezierTo(0, h, r, h);
      path.lineTo(w, h);
    } else if (bottomRight) {
      path.moveTo(w, 0);
      path.lineTo(w, h - r);
      path.quadraticBezierTo(w, h, w - r, h);
      path.lineTo(0, h);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}
