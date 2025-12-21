import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import 'count_pass_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  @override
  void initState() {
    super.initState();
    // Load sessions when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadSessions();
    });
  }

  Future<void> _createSession() async {
    final appState = context.read<AppState>();
    final session = await appState.createSession(
      name: 'Count ${DateTime.now().toString().substring(0, 16)}',
    );

    if (session != null && mounted) {
      _openSession(session);
    }
  }

  void _openSession(CountSession session) {
    final appState = context.read<AppState>();
    appState.setActiveSession(session);
    _showSessionDetail(session);
  }

  void _showSessionDetail(CountSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SessionDetailSheet(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Count Sessions'),
                if (appState.selectedStore != null)
                  Text(
                    appState.selectedStore!.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                  ),
              ],
            ),
            actions: [
              // Store selector
              if (appState.stores.length > 1)
                PopupMenuButton<Store>(
                  icon: const Icon(Icons.store),
                  onSelected: (store) => appState.selectStore(store),
                  itemBuilder: (context) => appState.stores
                      .map((store) => PopupMenuItem(
                            value: store,
                            child: Row(
                              children: [
                                if (store.id == appState.selectedStore?.id)
                                  const Icon(Icons.check, size: 18),
                                const SizedBox(width: 8),
                                Text(store.name),
                              ],
                            ),
                          ))
                      .toList(),
                ),
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
          body: appState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : appState.sessions.isEmpty
                  ? _buildEmptyState()
                  : _buildSessionList(appState),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _createSession,
            icon: const Icon(Icons.add),
            label: const Text('New Count'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No count sessions yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "New Count" to start',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList(AppState appState) {
    return RefreshIndicator(
      onRefresh: () => appState.loadSessions(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: appState.sessions.length,
        itemBuilder: (context, index) {
          final session = appState.sessions[index];
          return _SessionCard(
            session: session,
            onTap: () => _openSession(session),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final CountSession session;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_statusIcon, color: _statusColor),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session ${session.id.substring(0, 8)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(session.createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(status: session.status),
                        const SizedBox(width: 8),
                        Text(
                          '${session.submittedPassCount}/${session.passCount} passes',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (session.status) {
      case 'draft':
        return Colors.grey;
      case 'in_progress':
        return Colors.blue;
      case 'submitted':
        return Colors.orange;
      case 'reconciled':
        return Colors.green;
      case 'closed':
        return Colors.green.shade800;
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (session.status) {
      case 'draft':
        return Icons.edit_note;
      case 'in_progress':
        return Icons.pending_actions;
      case 'submitted':
        return Icons.check_circle_outline;
      case 'reconciled':
        return Icons.verified;
      case 'closed':
        return Icons.lock;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color get _color {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'in_progress':
        return Colors.blue;
      case 'submitted':
        return Colors.orange;
      case 'reconciled':
        return Colors.green;
      case 'closed':
        return Colors.green.shade800;
      default:
        return Colors.grey;
    }
  }
}

/// Bottom sheet showing session details and pass management
class SessionDetailSheet extends StatefulWidget {
  final CountSession session;

  const SessionDetailSheet({super.key, required this.session});

  @override
  State<SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends State<SessionDetailSheet> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final session = appState.activeSession ?? widget.session;

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
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
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Session ${session.id.substring(0, 8)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _StatusChip(status: session.status),
                            ],
                          ),
                        ),
                        if (session.canAddPasses)
                          ElevatedButton.icon(
                            onPressed: () => _showLocationPicker(context, appState),
                            icon: const Icon(Icons.add),
                            label: const Text('New Pass'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Passes list
                  Expanded(
                    child: session.passes?.isEmpty ?? true
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.checklist,
                                    size: 60, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text('No passes yet'),
                                const SizedBox(height: 8),
                                const Text(
                                  'Start a pass to begin counting',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: session.passes!.length,
                            itemBuilder: (context, index) {
                              final pass = session.passes![index];
                              return _PassCard(
                                pass: pass,
                                onTap: () => _openPass(context, appState, pass),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLocationPicker(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Location'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: appState.locations.length,
            itemBuilder: (context, index) {
              final location = appState.locations[index];
              return ListTile(
                leading: const Icon(Icons.location_on),
                title: Text(location.name),
                subtitle: Text(location.code),
                onTap: () async {
                  Navigator.pop(context); // Close dialog
                  final pass = await appState.createPass(location.id);
                  if (pass != null && mounted) {
                    Navigator.pop(context); // Close bottom sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CountPassScreen(),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openPass(BuildContext context, AppState appState, CountPass pass) {
    appState.setActivePass(pass);
    Navigator.pop(context); // Close bottom sheet
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CountPassScreen()),
    );
  }
}

class _PassCard extends StatelessWidget {
  final CountPass pass;
  final VoidCallback onTap;

  const _PassCard({
    required this.pass,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            pass.isSubmitted ? Icons.check : Icons.pending,
            color: _statusColor,
          ),
        ),
        title: Text(pass.location.name),
        subtitle: Text(
          '${pass.totalCounted} items · ${pass.lineCount} SKUs',
        ),
        trailing: _StatusChip(status: pass.status),
      ),
    );
  }

  Color get _statusColor {
    return pass.isSubmitted ? Colors.green : Colors.blue;
  }
}
