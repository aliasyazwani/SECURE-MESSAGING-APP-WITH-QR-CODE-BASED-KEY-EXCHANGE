import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/session_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [BarcodeFormat.qrCode],
  );
  final SessionService _sessionService = SessionService();

  bool _hasScanned = false;
  bool _torchOn = false;
  String _statusText = 'Scanning for SecureLink QR...';
  Color _statusColor = Colors.white;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Lock immediately so only the first valid detection is processed
    setState(() {
      _hasScanned = true;
      _statusText = 'QR detected, validating...';
      _statusColor = const Color(0xFF00D4AA);
    });

    // Safe debug log — no keys or plaintext printed
    debugPrint('Safe Debug: QR detected, length ${code.length}');

    try {
      final payload = _sessionService.parseQrPayload(code);

      // UTC-safe expiry check — prevents false expired errors on timezone difference
      final expiresAt = DateTime.parse(payload['expiresAt'] as String).toUtc();
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        _showError('Secure session QR has expired');
        return;
      }

      // Valid — return to caller
      if (!mounted) return;
      Navigator.of(context).pop(code);
    } catch (_) {
      _showError('Invalid SecureLink QR code');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _statusText = message;
      _statusColor = Colors.redAccent;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _statusText = 'Scanning for SecureLink QR...';
        _statusColor = Colors.white;
        _hasScanned = false; // allow retry
      });
    });
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Dark overlay with transparent cut-out square
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: _statusColor,
                borderRadius: 12,
                borderLength: 30,
                borderWidth: 8,
                cutOutSize: 280,
                overlayColor: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Top control bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Cancel
                    _CircleIconButton(
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),

                    // Flashlight + Camera swap
                    Row(
                      children: [
                        _CircleIconButton(
                          icon: _torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          iconColor: _torchOn ? Colors.yellow : Colors.grey,
                          onPressed: _toggleTorch,
                        ),
                        const SizedBox(width: 12),
                        _CircleIconButton(
                          icon: Icons.flip_camera_ios_rounded,
                          onPressed: () => _controller.switchCamera(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Status text pill at the bottom
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141824).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _statusColor.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small reusable icon button on a dark circle ──────────────────────────────

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withValues(alpha: 0.8),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }
}

// ── Custom overlay: dark vignette with a transparent square ──────────────────

class QrScannerOverlayShape extends ShapeBorder {
  const QrScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = const Color(0x88000000),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final Path path = Path()..addRect(rect);
    final cutRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );
    path.addRRect(RRect.fromRectAndRadius(cutRect, Radius.circular(borderRadius)));
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final cutoutRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    // Dark background with cut-out
    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()
      ..addRect(rect)
      ..addRRect(RRect.fromRectAndRadius(
          cutoutRect, Radius.circular(borderRadius)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, backgroundPaint);

    // Corner brackets
    final bracketPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final path = Path();

    // Top-left
    path.moveTo(cutoutRect.left, cutoutRect.top + borderLength);
    path.lineTo(cutoutRect.left, cutoutRect.top + borderRadius);
    path.quadraticBezierTo(cutoutRect.left, cutoutRect.top,
        cutoutRect.left + borderRadius, cutoutRect.top);
    path.lineTo(cutoutRect.left + borderLength, cutoutRect.top);

    // Top-right
    path.moveTo(cutoutRect.right - borderLength, cutoutRect.top);
    path.lineTo(cutoutRect.right - borderRadius, cutoutRect.top);
    path.quadraticBezierTo(cutoutRect.right, cutoutRect.top,
        cutoutRect.right, cutoutRect.top + borderRadius);
    path.lineTo(cutoutRect.right, cutoutRect.top + borderLength);

    // Bottom-right
    path.moveTo(cutoutRect.right, cutoutRect.bottom - borderLength);
    path.lineTo(cutoutRect.right, cutoutRect.bottom - borderRadius);
    path.quadraticBezierTo(cutoutRect.right, cutoutRect.bottom,
        cutoutRect.right - borderRadius, cutoutRect.bottom);
    path.lineTo(cutoutRect.right - borderLength, cutoutRect.bottom);

    // Bottom-left
    path.moveTo(cutoutRect.left + borderLength, cutoutRect.bottom);
    path.lineTo(cutoutRect.left + borderRadius, cutoutRect.bottom);
    path.quadraticBezierTo(cutoutRect.left, cutoutRect.bottom,
        cutoutRect.left, cutoutRect.bottom - borderRadius);
    path.lineTo(cutoutRect.left, cutoutRect.bottom - borderLength);

    canvas.drawPath(path, bracketPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
