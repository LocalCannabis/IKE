import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class CountPassScreen extends StatefulWidget {
  const CountPassScreen({super.key});

  @override
  State<CountPassScreen> createState() => _CountPassScreenState();
}

class _CountPassScreenState extends State<CountPassScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  final _quantityController = TextEditingController(text: '1');

  bool _isScanning = false;
  String? _lastScanResult;
  AddLineResult? _lastAddResult;

  @override
  void initState() {
    super.initState();
    // Auto-focus barcode input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _handleScan() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;

    setState(() {
      _isScanning = true;
      _lastScanResult = null;
      _lastAddResult = null;
    });

    final appState = context.read<AppState>();
    final quantity = int.tryParse(_quantityController.text) ?? 1;

    final result = await appState.addScan(barcode, quantity: quantity);

    setState(() {
      _isScanning = false;
      if (result != null) {
        _lastAddResult = result;
        _lastScanResult = result.incremented
            ? '${result.product?.name ?? barcode}: ${result.line.countedQty} (was ${result.previousQty})'
            : '${result.product?.name ?? barcode}: ${result.line.countedQty}';
        _barcodeController.clear();
        _quantityController.text = '1';
      } else {
        _lastScanResult = 'Error: ${appState.error}';
      }
    });

    // Re-focus for next scan
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _submitPass() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Pass?'),
        content: const Text(
          'Once submitted, you cannot add more items to this pass. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final appState = context.read<AppState>();
      final success = await appState.submitActivePass();
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pass submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  /// Open camera scanner in a bottom sheet
  Future<void> _openCameraScanner() async {
    final barcode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CameraScannerSheet(),
    );

    if (barcode != null && barcode.isNotEmpty && mounted) {
      _barcodeController.text = barcode;
      await _handleScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final pass = appState.activePass;

        if (pass == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Count Pass')),
            body: const Center(child: Text('No active pass')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pass.location.name),
                Text(
                  '${pass.totalCounted} items · ${pass.lineCount} SKUs',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            actions: [
              if (pass.isInProgress)
                TextButton.icon(
                  onPressed: _submitPass,
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text(
                    'Submit',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              // Scan input area
              if (pass.isInProgress) _buildScanInput(pass),

              // Last scan result
              if (_lastScanResult != null) _buildLastScanResult(),

              // Lines list
              Expanded(child: _buildLinesList(pass)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScanInput(CountPass pass) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.green.shade200),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Barcode input
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Scan or enter barcode/SKU',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: _barcodeController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _barcodeController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleScan(),
                  onChanged: (_) => setState(() {}),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Quantity input
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Qty',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Add button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isScanning ? null : _handleScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: _isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                ),
              ),
              const SizedBox(width: 8),
              // Camera scan button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isScanning ? null : _openCameraScanner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Icon(Icons.camera_alt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLastScanResult() {
    final isError = _lastScanResult?.startsWith('Error') ?? false;
    final wasIncremented = _lastAddResult?.incremented ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isError
          ? Colors.red.shade50
          : wasIncremented
              ? Colors.blue.shade50
              : Colors.green.shade100,
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : wasIncremented
                    ? Icons.add_circle_outline
                    : Icons.check_circle_outline,
            color: isError
                ? Colors.red
                : wasIncremented
                    ? Colors.blue
                    : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastScanResult!,
              style: TextStyle(
                color: isError ? Colors.red.shade800 : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _lastScanResult = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesList(CountPass pass) {
    final lines = pass.lines ?? [];

    if (lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No items scanned yet'),
            const SizedBox(height: 8),
            Text(
              pass.isInProgress
                  ? 'Scan a barcode to start counting'
                  : 'This pass has no items',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return _LineCard(
          line: line,
          onEdit: pass.isInProgress ? () => _editLine(line) : null,
        );
      },
    );
  }

  void _editLine(CountLine line) {
    final controller = TextEditingController(text: line.countedQty.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.product?.name ?? line.sku),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final appState = context.read<AppState>();
              await appState.api.deleteLine(line.id);
              await appState.refreshActivePass();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQty = int.tryParse(controller.text);
              if (newQty != null && newQty > 0) {
                Navigator.pop(context);
                final appState = context.read<AppState>();
                await appState.api.updateLine(line.id, newQty);
                await appState.refreshActivePass();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final CountLine line;
  final VoidCallback? onEdit;

  const _LineCard({
    required this.line,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onEdit,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            line.countedQty.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ),
        title: Text(
          line.product?.name ?? line.sku,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (line.product?.brand != null)
              Text(
                line.product!.brand!,
                style: const TextStyle(fontSize: 12),
              ),
            Text(
              'SKU: ${line.sku}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        trailing: onEdit != null
            ? const Icon(Icons.edit, size: 18, color: Colors.grey)
            : null,
      ),
    );
  }
}

/// Camera scanner bottom sheet
class _CameraScannerSheet extends StatefulWidget {
  const _CameraScannerSheet();

  @override
  State<_CameraScannerSheet> createState() => _CameraScannerSheetState();
}

class _CameraScannerSheetState extends State<_CameraScannerSheet> {
  late MobileScannerController _controller;
  bool _hasScanned = false;
  String? _lastBarcodeType;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,  // Give more time to analyze
      facing: CameraFacing.back,
      torchEnabled: false,
      // Use 'all' to capture any barcode format - important for GS1 DataBar variants
      formats: [BarcodeFormat.all],
      // Request higher resolution for better barcode detection
      cameraResolution: const Size(1920, 1080),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final barcode = barcodes.first;
      final value = barcode.rawValue;
      final format = barcode.format;
      
      if (value != null && value.isNotEmpty) {
        setState(() {
          _hasScanned = true;
          _lastBarcodeType = _formatName(format);
        });
        
        // Vibrate/haptic feedback
        HapticFeedback.mediumImpact();
        
        // For 2D barcodes (Data Matrix, PDF417), extract the relevant part
        // Cannabis compliance codes often have format: SKU|LOT|EXPIRY or similar
        final extractedValue = _extractBarcodeValue(value, format);
        
        // Return the barcode value with metadata
        Navigator.pop(context, extractedValue);
      }
    }
  }

  /// Extract relevant value from barcode (handles 2D cannabis compliance codes)
  String _extractBarcodeValue(String value, BarcodeFormat format) {
    // For Data Matrix / PDF417 compliance codes, the value might be delimited
    // Common formats:
    // - Pipe delimited: SKU|LOT|DATE
    // - GS1 format: (01)GTIN(10)LOT(17)EXPIRY
    // - Simple: just the SKU or lot number
    
    // For now, return the full value - backend will parse it
    // In future, we could parse GS1 Application Identifiers here
    return value;
  }

  /// Get human-readable format name
  String _formatName(BarcodeFormat format) {
    switch (format) {
      case BarcodeFormat.qrCode:
        return 'QR Code';
      case BarcodeFormat.dataMatrix:
        return 'Data Matrix';
      case BarcodeFormat.pdf417:
        return 'PDF417';
      case BarcodeFormat.aztec:
        return 'Aztec';
      case BarcodeFormat.upcA:
        return 'UPC-A';
      case BarcodeFormat.upcE:
        return 'UPC-E';
      case BarcodeFormat.ean8:
        return 'EAN-8';
      case BarcodeFormat.ean13:
        return 'EAN-13';
      case BarcodeFormat.code128:
        return 'Code 128';
      case BarcodeFormat.code39:
        return 'Code 39';
      case BarcodeFormat.code93:
        return 'Code 93';
      case BarcodeFormat.itf:
        return 'ITF';
      case BarcodeFormat.codabar:
        return 'Codabar';
      default:
        return 'Barcode';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan Barcode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'UPC • QR • Data Matrix • PDF417',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // Scanner view
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  // Scan area overlay - wide for stacked GS1 barcodes
                  Center(
                    child: Container(
                      width: 320,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _hasScanned ? Colors.green : Colors.white,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _hasScanned
                          ? Center(
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 60,
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Instructions / Status
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _hasScanned && _lastBarcodeType != null
                  ? '$_lastBarcodeType detected!'
                  : 'Hold steady • Use flash for GS1 barcodes • Tap screen to focus',
              style: TextStyle(
                color: _hasScanned ? Colors.green : Colors.grey.shade400,
                fontSize: 14,
                fontWeight: _hasScanned ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Flash toggle
                IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (context, state, child) {
                      return Icon(
                        state.torchState == TorchState.on
                            ? Icons.flash_on
                            : Icons.flash_off,
                        color: Colors.white,
                        size: 28,
                      );
                    },
                  ),
                ),
                // Camera flip
                IconButton(
                  onPressed: () => _controller.switchCamera(),
                  icon: const Icon(
                    Icons.cameraswitch,
                    color: Colors.white,
                    size: 28,
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