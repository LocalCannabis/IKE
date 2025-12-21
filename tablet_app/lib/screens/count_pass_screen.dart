import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
