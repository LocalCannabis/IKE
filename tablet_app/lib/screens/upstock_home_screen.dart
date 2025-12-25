import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'upstock_run_screen.dart';

class UpstockHomeScreen extends StatefulWidget {
  const UpstockHomeScreen({super.key});

  @override
  State<UpstockHomeScreen> createState() => _UpstockHomeScreenState();
}

class _UpstockHomeScreenState extends State<UpstockHomeScreen> {
  bool _isLoading = false;
  bool _isStarting = false;
  bool _isSyncing = false;
  List<UpstockRun> _recentRuns = [];
  UpstockRun? _activeRun;
  Map<String, dynamic>? _syncStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRuns();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    try {
      final appState = context.read<AppState>();
      final storeId = appState.selectedStore?.id ?? 1;
      final status = await appState.api.getSalesSyncStatus(storeId: storeId);
      if (mounted) {
        setState(() {
          _syncStatus = status;
        });
      }
    } catch (e) {
      // Silently fail - sync status is informational
    }
  }

  Future<void> _syncSales() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final appState = context.read<AppState>();
      final storeId = appState.selectedStore?.id ?? 1;
      await appState.api.syncSales(storeId: storeId);
      await _loadSyncStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sales synced successfully'),
            backgroundColor: AppColors.emerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _loadRuns() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final storeId = appState.selectedStore?.id ?? 1;

      // Get all recent runs
      final runs = await appState.api.getUpstockRuns(
        storeId: storeId,
        limit: 20,
      );

      // Find active run (in_progress)
      final active = runs.where((r) => r.isInProgress).toList();

      setState(() {
        _recentRuns = runs;
        _activeRun = active.isNotEmpty ? active.first : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startUpstock() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final storeId = appState.selectedStore?.id ?? 1;

      final result = await appState.api.startUpstockRun(
        storeId: storeId,
        locationId: 'FOH_DISPLAY',
        notes: 'End of day upstock',
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UpstockRunScreen(
              run: result.run,
              initialStats: result.stats,
            ),
          ),
        ).then((_) => _loadRuns());
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _resumeRun(UpstockRun run) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appState = context.read<AppState>();
      final result = await appState.api.getUpstockRun(run.id);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UpstockRunScreen(
              run: result.run,
              initialStats: result.stats,
            ),
          ),
        ).then((_) => _loadRuns());
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upstock'),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _syncSales,
              tooltip: 'Sync sales data',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRuns,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRuns,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sync status card
                    _buildSyncStatusCard(),
                    const SizedBox(height: 16),
                    
                    // Error banner
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Active run card
                    if (_activeRun != null) ...[
                      _buildActiveRunCard(_activeRun!),
                      const SizedBox(height: 24),
                    ],

                    // Start button (only if no active run)
                    if (_activeRun == null) ...[
                      _buildStartButton(),
                      const SizedBox(height: 24),
                    ],

                    // Recent runs
                    _buildRecentRunsSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSyncStatusCard() {
    final synced = _syncStatus?['synced'] == true;
    final todayCount = _syncStatus?['today_movement_count'] ?? 0;
    final latestAt = _syncStatus?['latest_movement_at'];
    
    return SectionCard(
      title: 'Sales Data',
      trailing: StatusBadge(
        label: synced ? 'Synced' : 'Not synced',
        color: synced ? AppColors.emerald : Colors.orange,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$todayCount sales today',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (latestAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last sync: ${_formatSyncTime(latestAt)}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _isSyncing ? null : _syncSales,
            icon: _isSyncing 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: const Text('Sync Now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emeraldLight,
              foregroundColor: AppColors.emeraldDark,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return 'unknown';
    }
  }

  Widget _buildActiveRunCard(UpstockRun run) {
    return SectionCard(
      backgroundColor: AppColors.emeraldLight.withValues(alpha: 0.3),
      child: InkWell(
        onTap: () => _resumeRun(run),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const StatusBadge(
                    label: 'IN PROGRESS',
                    color: AppColors.emerald,
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios, color: AppColors.emeraldDark),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                run.locationId,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Started ${_formatTime(run.createdAt)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              Text(
                '${run.lines.length} items to pull',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _resumeRun(run),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('RESUME'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return SectionCard(
      child: Column(
        children: [
          Icon(
            Icons.inventory_2,
            size: 64,
            color: AppColors.emeraldLight,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ready to Upstock',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull products from BOH to restock FOH display',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isStarting ? null : _startUpstock,
              icon: _isStarting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_box),
              label: Text(_isStarting ? 'STARTING...' : 'START UPSTOCK'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRunsSection() {
    final completedRuns = _recentRuns.where((r) => !r.isInProgress).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Runs',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (completedRuns.isEmpty)
          const EmptyState(
            icon: Icons.history,
            title: 'No previous runs',
            subtitle: 'Start an upstock run to see history here',
          )
        else
          ...completedRuns.map((run) => _buildRunListItem(run)),
      ],
    );
  }

  Widget _buildRunListItem(UpstockRun run) {
    final isCompleted = run.isCompleted;
    final statusColor = isCompleted ? AppColors.emerald : Colors.grey;
    final statusText = isCompleted ? 'Completed' : 'Abandoned';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(
            isCompleted ? Icons.check : Icons.close,
            color: statusColor,
          ),
        ),
        title: Text(run.locationId),
        subtitle: Text(
          '$statusText • ${_formatDateTime(run.completedAt ?? run.createdAt)}',
        ),
        trailing: Text(
          '${run.lines.length} items',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
