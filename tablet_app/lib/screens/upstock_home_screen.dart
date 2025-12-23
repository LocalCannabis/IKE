import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'upstock_run_screen.dart';

class UpstockHomeScreen extends StatefulWidget {
  const UpstockHomeScreen({super.key});

  @override
  State<UpstockHomeScreen> createState() => _UpstockHomeScreenState();
}

class _UpstockHomeScreenState extends State<UpstockHomeScreen> {
  bool _isLoading = false;
  bool _isStarting = false;
  List<UpstockRun> _recentRuns = [];
  UpstockRun? _activeRun;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final storeId = appState.currentStore?.id ?? 1;

      // Get all recent runs
      final runs = await appState.apiService.getUpstockRuns(
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
      final storeId = appState.currentStore?.id ?? 1;

      final result = await appState.apiService.startUpstockRun(
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
      final result = await appState.apiService.getUpstockRun(run.id);

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
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRuns,
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

  Widget _buildActiveRunCard(UpstockRun run) {
    return Card(
      color: Colors.orange.shade50,
      child: InkWell(
        onTap: () => _resumeRun(run),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'IN PROGRESS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios, color: Colors.orange.shade700),
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
                child: ElevatedButton.icon(
                  onPressed: () => _resumeRun(run),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('RESUME'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2,
              size: 64,
              color: Colors.orange.shade300,
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
              child: ElevatedButton.icon(
                onPressed: _isStarting ? null : _startUpstock,
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_box),
                label: Text(_isStarting ? 'STARTING...' : 'START UPSTOCK'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No previous runs',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          )
        else
          ...completedRuns.map((run) => _buildRunListItem(run)),
      ],
    );
  }

  Widget _buildRunListItem(UpstockRun run) {
    final isCompleted = run.isCompleted;
    final statusColor = isCompleted ? Colors.green : Colors.grey;
    final statusText = isCompleted ? 'Completed' : 'Abandoned';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.shade100,
          child: Icon(
            isCompleted ? Icons.check : Icons.close,
            color: statusColor.shade700,
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
