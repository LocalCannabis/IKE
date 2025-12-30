import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Simplified Count Screen
/// 
/// WORKFLOW:
/// 1. User sees "Join" if active session exists, or "Start" to create one
/// 2. When starting, choose scope: Location OR Category OR Full Inventory
/// 3. Once in session, just scan! Each scan = 1 item
/// 4. Submit when done
class CountScreen extends StatefulWidget {
  const CountScreen({super.key});

  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().checkForActiveSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Loading state
        if (appState.isLoading) {
          return Scaffold(
            appBar: AppBar(title: const Text('Inventory Count')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // If we have an active session, show the counting screen
        if (appState.activeSession != null) {
          return _CountingScreen(session: appState.activeSession!);
        }

        // Otherwise show Join/Start screen
        return _JoinOrStartScreen();
      },
    );
  }
}

/// Screen shown when no active session - allows joining or starting
class _JoinOrStartScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inventory Count'),
            if (appState.selectedStore != null)
              Text(
                appState.selectedStore!.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          // User menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                appState.logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appState.currentUser?.name ?? 'User',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      appState.currentUser?.email ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 80,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              const Text(
                'No Active Count',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new count session or wait for someone else to start one',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 280,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _showScopeSelector(context),
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: const Text('Start Count', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => appState.checkForActiveSession(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScopeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ScopeSelectorSheet(),
    );
  }
}

/// Bottom sheet for selecting count scope
class _ScopeSelectorSheet extends StatefulWidget {
  const _ScopeSelectorSheet();

  @override
  State<_ScopeSelectorSheet> createState() => _ScopeSelectorSheetState();
}

class _ScopeSelectorSheetState extends State<_ScopeSelectorSheet> {
  String _selectedScope = 'full';
  int? _selectedLocationId;
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'What are you counting?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              // Options
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Full inventory
                    _ScopeOption(
                      title: 'Full Inventory',
                      subtitle: 'Count everything',
                      icon: Icons.inventory,
                      isSelected: _selectedScope == 'full',
                      onTap: () => setState(() {
                        _selectedScope = 'full';
                        _selectedLocationId = null;
                        _selectedCategory = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    
                    // By location
                    _ScopeOption(
                      title: 'By Location',
                      subtitle: 'Count a specific area',
                      icon: Icons.location_on,
                      isSelected: _selectedScope == 'location',
                      onTap: () => setState(() {
                        _selectedScope = 'location';
                        _selectedCategory = null;
                      }),
                    ),
                    if (_selectedScope == 'location') ...[
                      const SizedBox(height: 8),
                      ...appState.locations.map((loc) => Padding(
                        padding: const EdgeInsets.only(left: 48, bottom: 4),
                        child: ChoiceChip(
                          label: Text(loc.name),
                          selected: _selectedLocationId == loc.id,
                          onSelected: (selected) => setState(() {
                            _selectedLocationId = selected ? loc.id : null;
                          }),
                        ),
                      )),
                    ],
                    const SizedBox(height: 12),
                    
                    // By category
                    _ScopeOption(
                      title: 'By Category',
                      subtitle: 'Count one product type',
                      icon: Icons.category,
                      isSelected: _selectedScope == 'category',
                      onTap: () => setState(() {
                        _selectedScope = 'category';
                        _selectedLocationId = null;
                      }),
                    ),
                    if (_selectedScope == 'category') ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: appState.categories.map((cat) => ChoiceChip(
                          label: Text(cat),
                          selected: _selectedCategory == cat,
                          onSelected: (selected) => setState(() {
                            _selectedCategory = selected ? cat : null;
                          }),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // Start button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canStart() ? () => _startSession(context, appState) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Start Counting', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canStart() {
    if (_selectedScope == 'location') return _selectedLocationId != null;
    if (_selectedScope == 'category') return _selectedCategory != null;
    return true;
  }

  Future<void> _startSession(BuildContext context, AppState appState) async {
    Navigator.pop(context); // Close sheet

    final session = await appState.startSession(
      scopeType: _selectedScope,
      scopeLocationId: _selectedLocationId,
      scopeCategory: _selectedCategory,
    );

    if (session == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.error ?? 'Failed to start session'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _ScopeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.green.shade700 : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: isSelected ? Colors.green.shade700 : Colors.grey.shade600,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: Colors.green.shade700)
            : null,
      ),
    );
  }
}

/// Main counting screen - shown when session is active
class _CountingScreen extends StatefulWidget {
  final CountSession session;

  const _CountingScreen({required this.session});

  @override
  State<_CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends State<_CountingScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.all],
  );
  
  bool _isProcessing = false;
  String? _lastBarcode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    // Debounce - don't process same barcode within 1 second
    final now = DateTime.now();
    if (_lastBarcode == barcode && 
        _lastScanTime != null && 
        now.difference(_lastScanTime!).inMilliseconds < 1000) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastBarcode = barcode;
      _lastScanTime = now;
    });

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Process scan
    final appState = context.read<AppState>();
    final result = await appState.scan(barcode);

    setState(() => _isProcessing = false);

    if (result != null && mounted) {
      // Success feedback
      HapticFeedback.lightImpact();
    } else if (mounted) {
      // Error feedback
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.error ?? 'Scan failed'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final session = appState.activeSession ?? widget.session;
        final lastScan = appState.lastScan;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.scopeDescription),
                Text(
                  '${session.totalCounted} items · ${session.uniqueSkus} SKUs',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
            actions: [
              // Submit button
              TextButton.icon(
                onPressed: session.totalCounted > 0
                    ? () => _showSubmitDialog(context, appState)
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Submit'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Scanner view
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onBarcodeDetected,
                    ),
                    // Scanning indicator
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    // Scan overlay/guide
                    Center(
                      child: Container(
                        width: 280,
                        height: 180,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // Flash toggle
                    Positioned(
                      top: 16,
                      right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                        onPressed: () => _scannerController.toggleTorch(),
                      ),
                    ),
                  ],
                ),
              ),
              // Last scan result
              Expanded(
                flex: 1,
                child: Container(
                  color: lastScan != null ? Colors.green.shade50 : Colors.grey.shade100,
                  padding: const EdgeInsets.all(16),
                  child: lastScan != null
                      ? _LastScanDisplay(scan: lastScan, onUndo: () => appState.undoLastScan())
                      : const Center(
                          child: Text(
                            'Scan a product barcode',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubmitDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Count?'),
        content: Text(
          'You\'ve counted ${appState.activeSession?.totalCounted} items '
          '(${appState.activeSession?.uniqueSkus} unique SKUs).\n\n'
          'Once submitted, this count session will be closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Counting'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await appState.submitSession();
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(appState.error ?? 'Failed to submit'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _LastScanDisplay extends StatelessWidget {
  final ScanResult scan;
  final VoidCallback onUndo;

  const _LastScanDisplay({required this.scan, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Product info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Scanned!',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                scan.product.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${scan.product.brand ?? ''} · ${scan.product.category ?? ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              if (scan.lotNo != null)
                Text(
                  'Lot: ${scan.lotNo}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
        ),
        // Stats and undo
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${scan.totalItems}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text('items'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Undo'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
