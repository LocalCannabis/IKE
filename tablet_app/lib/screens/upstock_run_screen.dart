import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme.dart';

class UpstockRunScreen extends StatefulWidget {
  final UpstockRun run;
  final UpstockRunStats initialStats;

  const UpstockRunScreen({
    super.key,
    required this.run,
    required this.initialStats,
  });

  @override
  State<UpstockRunScreen> createState() => _UpstockRunScreenState();
}

class _UpstockRunScreenState extends State<UpstockRunScreen> {
  late UpstockRun _run;
  late UpstockRunStats _stats;
  bool _isLoading = false;
  String? _error;
  String? _highlightedSku;

  // Scanner input
  final _scanController = TextEditingController();
  final _scanFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    _stats = widget.initialStats;

    // Auto-focus scanner input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  void _handleScan(String barcode) {
    if (barcode.isEmpty) return;

    // Find matching line
    final matchingLine = _run.lines.where((l) => l.sku == barcode).toList();

    if (matchingLine.isNotEmpty) {
      final line = matchingLine.first;
      setState(() {
        _highlightedSku = line.sku;
      });

      // Show quick confirm dialog
      _showQuickConfirmDialog(line);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product "$barcode" not in upstock list'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }

    _scanController.clear();
    _scanFocusNode.requestFocus();
  }

  Future<void> _showQuickConfirmDialog(UpstockRunLine line) async {
    final pulledQty = await showDialog<int>(
      context: context,
      builder: (context) => _QuickConfirmDialog(line: line),
    );

    if (pulledQty != null) {
      await _updateLine(line.sku, pulledQty, 'done');
    }
  }

  Future<void> _updateLine(String sku, int pulledQty, String status, {String? exceptionReason}) async {
    setState(() => _isLoading = true);

    try {
      final appState = context.read<AppState>();
      await appState.api.updateUpstockLine(
        runId: _run.id,
        sku: sku,
        pulledQty: pulledQty,
        status: status,
        exceptionReason: exceptionReason,
      );

      // Refresh run data
      final result = await appState.api.getUpstockRun(_run.id);
      setState(() {
        _run = result.run;
        _stats = result.stats;
        _isLoading = false;
        _highlightedSku = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showExceptionDialog(UpstockRunLine line) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ExceptionDialog(line: line),
    );

    if (reason != null) {
      await _updateLine(line.sku, 0, 'exception', exceptionReason: reason);
    }
  }

  Future<void> _skipLine(UpstockRunLine line) async {
    await _updateLine(line.sku, 0, 'skipped');
  }

  Future<void> _completeRun() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Upstock?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Done: ${_stats.done}'),
            Text('Skipped: ${_stats.skipped}'),
            Text('Exceptions: ${_stats.exceptions}'),
            if (_stats.pending > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${_stats.pending} items still pending',
                style: TextStyle(color: Colors.orange.shade700),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        final appState = context.read<AppState>();
        await appState.api.completeUpstockRun(_run.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upstock completed!'),
              backgroundColor: AppColors.emerald,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _abandonRun() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _AbandonDialog(),
    );

    if (reason != null) {
      setState(() => _isLoading = true);

      try {
        final appState = context.read<AppState>();
        await appState.api.abandonUpstockRun(_run.id, reason: reason);

        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedLines = _run.linesByCategory;

    return Scaffold(
      appBar: AppBar(
        title: Text(_run.locationId),
        actions: [
          IconButton(
            icon: const Icon(Icons.cancel),
            onPressed: _abandonRun,
            tooltip: 'Abandon',
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress header
          _buildProgressHeader(),

          // Scanner input (hidden but focused)
          _buildScannerInput(),

          // Error banner
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),

          // Lines list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: groupedLines.keys.length,
                    itemBuilder: (context, index) {
                      final cabinet = groupedLines.keys.elementAt(index);
                      final lines = groupedLines[cabinet]!;
                      return _buildCabinetSection(cabinet, lines);
                    },
                  ),
          ),

          // Bottom action bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    final progress = _stats.total > 0
        ? (_stats.done + _stats.skipped) / _stats.total
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.emeraldLight.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('Done', _stats.done, AppColors.emerald),
              _buildStatChip('Pending', _stats.pending, Colors.orange),
              _buildStatChip('Skipped', _stats.skipped, Colors.grey),
              _buildStatChip('Exceptions', _stats.exceptions, Colors.red),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade300,
            valueColor: const AlwaysStoppedAnimation(AppColors.emerald),
          ),
          const SizedBox(height: 4),
          Text(
            '${(_stats.completionRate).toStringAsFixed(0)}% complete',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildScannerInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _scanController,
        focusNode: _scanFocusNode,
        decoration: InputDecoration(
          hintText: 'Scan barcode...',
          prefixIcon: const Icon(Icons.qr_code_scanner),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
        onSubmitted: _handleScan,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'\s')),
        ],
      ),
    );
  }

  Widget _buildCabinetSection(String cabinet, List<UpstockRunLine> lines) {
    final pendingCount = lines.where((l) => l.isPending).length;
    final doneCount = lines.where((l) => l.isDone).length;

    return ExpansionTile(
      title: Text(
        cabinet,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('$doneCount/${lines.length} done'),
      initiallyExpanded: pendingCount > 0,
      children: lines.map((line) => _buildLineItem(line)).toList(),
    );
  }

  Widget _buildLineItem(UpstockRunLine line) {
    final isHighlighted = _highlightedSku == line.sku;
    final statusColor = _getStatusColor(line.status);

    return Container(
      color: isHighlighted ? Colors.yellow.shade100 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(
            _getStatusIcon(line.status),
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          line.displayName,
          style: TextStyle(
            decoration: line.isResolved ? TextDecoration.lineThrough : null,
            color: line.isResolved ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          'Pull: ${line.suggestedPullQty} • SKU: ${line.sku}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: line.isPending
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle),
                    color: AppColors.emerald,
                    onPressed: () => _showQuickConfirmDialog(line),
                    tooltip: 'Done',
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    color: Colors.grey.shade600,
                    onPressed: () => _skipLine(line),
                    tooltip: 'Skip',
                  ),
                  IconButton(
                    icon: const Icon(Icons.warning),
                    color: Colors.red.shade600,
                    onPressed: () => _showExceptionDialog(line),
                    tooltip: 'Exception',
                  ),
                ],
              )
            : Text(
                line.status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
        onTap: line.isPending ? () => _showQuickConfirmDialog(line) : null,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'done':
        return AppColors.emerald;
      case 'skipped':
        return Colors.grey;
      case 'exception':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'done':
        return Icons.check;
      case 'skipped':
        return Icons.skip_next;
      case 'exception':
        return Icons.warning;
      default:
        return Icons.pending;
    }
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _completeRun,
            icon: const Icon(Icons.check_circle),
            label: const Text('COMPLETE UPSTOCK'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ DIALOGS ============

class _QuickConfirmDialog extends StatefulWidget {
  final UpstockRunLine line;

  const _QuickConfirmDialog({required this.line});

  @override
  State<_QuickConfirmDialog> createState() => _QuickConfirmDialogState();
}

class _QuickConfirmDialogState extends State<_QuickConfirmDialog> {
  late int _qty;

  @override
  void initState() {
    super.initState();
    _qty = widget.line.suggestedPullQty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.line.displayName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Suggested: ${widget.line.suggestedPullQty}'),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle),
                iconSize: 40,
                onPressed: _qty > 0 ? () => setState(() => _qty--) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _qty.toString(),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                iconSize: 40,
                onPressed: () => setState(() => _qty++),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _qty),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _ExceptionDialog extends StatefulWidget {
  final UpstockRunLine line;

  const _ExceptionDialog({required this.line});

  @override
  State<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends State<_ExceptionDialog> {
  String? _selectedReason;
  final _customController = TextEditingController();

  final _reasons = [
    'BOH short',
    'Already stocked',
    'Product not found',
    'Damaged product',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Exception'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.line.displayName),
          const SizedBox(height: 16),
          ..._reasons.map(
            (reason) => RadioListTile<String>(
              title: Text(reason),
              value: reason,
              groupValue: _selectedReason,
              onChanged: (v) => setState(() => _selectedReason = v),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (_selectedReason == 'Other')
            TextField(
              controller: _customController,
              decoration: const InputDecoration(
                hintText: 'Enter reason...',
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedReason != null
              ? () {
                  final reason = _selectedReason == 'Other'
                      ? _customController.text
                      : _selectedReason!;
                  Navigator.pop(context, reason);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _AbandonDialog extends StatefulWidget {
  @override
  State<_AbandonDialog> createState() => _AbandonDialogState();
}

class _AbandonDialogState extends State<_AbandonDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abandon Upstock?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This will cancel the current upstock run.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
          ),
          child: const Text('Abandon'),
        ),
      ],
    );
  }
}
