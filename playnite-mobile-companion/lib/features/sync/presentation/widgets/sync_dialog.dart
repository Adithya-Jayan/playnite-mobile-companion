import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/network/drive_api_service.dart';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class SyncDialog extends StatefulWidget {
  final AppDatabase database;
  final DriveApiService? driveService;
  final VoidCallback? onSyncCompleted;

  const SyncDialog({
    super.key,
    required this.database,
    this.driveService,
    this.onSyncCompleted,
  });

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  SyncProgress _progress = const SyncProgress(phase: SyncPhase.idle);
  SyncReport? _report;
  bool _isSyncing = false;
  bool _isCancelling = false;
  DeltaPullManager? _pullManager;

  bool _notified = false;

  void _notifySyncCompleted() {
    if (!_notified) {
      _notified = true;
      widget.onSyncCompleted?.call();
    }
  }

  void _cancelSync() {
    if (_isSyncing && !_isCancelling) {
      setState(() => _isCancelling = true);
      _pullManager?.cancel();
    }
  }

  @override
  void dispose() {
    _notifySyncCompleted();
    super.dispose();
  }

  void _onClose() {
    _notifySyncCompleted();
    Navigator.of(context).pop();
  }

  DriveApiService _createDefaultMockService() {
    return MockDriveService(
      mockIndex: const SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T21:00:00.000Z',
        libraryId: 'mock-library-id',
        totalGames: 2,
        totalEntries: 2,
        totalSizeBytes: 12000,
        entries: {},
      ),
    );
  }

  Future<void> _startSync() async {
    setState(() {
      _isSyncing = true;
      _isCancelling = false;
      _report = null;
    });

    DriveApiService service = widget.driveService ?? _createDefaultMockService();
    try {
      if (widget.driveService == null) {
        final repo = SyncConfigRepository(widget.database);
        final cfg = await repo.loadConfig();
        service = repo.createDriveService(cfg);
      }
    } catch (e) {
      debugPrint('Failed to load active drive service: $e');
    }

    final pullManager = DeltaPullManager(
      driveService: service,
      database: widget.database,
    );
    _pullManager = pullManager;

    final report = await pullManager.executeDeltaPull(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _isCancelling = false;
        _report = report;
      });
      if (report.isSuccess) {
        try {
          final repo = SyncConfigRepository(widget.database);
          final cfg = await repo.loadConfig();
          await repo.saveConfig(cfg.copyWith(lastSyncUtc: DateTime.now().toUtc().toIso8601String()));
        } catch (_) {}
      }
      // Always trigger library reload if games were committed, downloaded, or sync finished
      widget.onSyncCompleted?.call();
    }
  }

  String _getPhaseStepLabel(SyncPhase phase) {
    switch (phase) {
      case SyncPhase.fetchingIndex:
        return 'Step 1/3: Checking Cloud Index';
      case SyncPhase.computingDiff:
        return 'Step 1/3: Analyzing Library Changes';
      case SyncPhase.downloadingPayloads:
        return 'Step 2/3: Downloading Payloads';
      case SyncPhase.committingDatabase:
        return 'Step 3/3: Saving to Local Database';
      case SyncPhase.completed:
        return 'Sync Complete';
      case SyncPhase.error:
        return 'Sync Interrupted';
      case SyncPhase.idle:
        return 'Initializing...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSyncing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _notifySyncCompleted();
        }
      },
      child: AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sync, color: AppTheme.primaryLight),
          SizedBox(width: 8),
          Text('Delta Library Sync', style: TextStyle(fontSize: 18, color: AppTheme.textPrimary)),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pulls only modified game payloads and new media assets since your last sync.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),

            if (_isSyncing) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _progress.stepText ?? _getPhaseStepLabel(_progress.phase),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Text(
                _progress.message.isNotEmpty ? _progress.message : 'Syncing...',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),

              if (_progress.currentItem != null && _progress.currentItem!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Item: ${_progress.currentItem}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              if (_progress.etaText != null && _progress.etaText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 13, color: AppTheme.accentGreen),
                    const SizedBox(width: 4),
                    Text(
                      _progress.etaText!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress.total > 0 ? (_progress.current / _progress.total).clamp(0.0, 1.0) : null,
                  minHeight: 8,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress.total > 0
                        ? '${_progress.current} of ${_progress.total} (${((_progress.current / _progress.total) * 100).toInt()}%)'
                        : 'Working...',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  if (_progress.totalBytes > 0)
                    Text(
                      '${DurationFormatter.formatBytes(_progress.bytesDownloaded)} / ${DurationFormatter.formatBytes(_progress.totalBytes)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryLight),
                    ),
                ],
              ),
            ] else if (_report != null) ...[
              if (_report!.isSuccess)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Sync Completed Successfully',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _report!.downloadedCount == 0 && _report!.deletedCount == 0
                            ? 'Library is up to date (0 delta changes).'
                            : 'Updated ${_report!.downloadedCount} games, deleted ${_report!.deletedCount} games (${DurationFormatter.formatBytes(_report!.bytesTransferred)} downloaded in ${_report!.durationMs} ms).',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                )
              else if (_report!.isCancelled)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sync paused by user. ${_report!.downloadedCount} items were saved to your library.',
                          style: const TextStyle(fontSize: 12, color: Colors.amber),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _report!.errorMessage ?? 'Unknown sync failure',
                          style: const TextStyle(fontSize: 12, color: AppTheme.accentRed),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isSyncing)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            onPressed: _isCancelling ? null : _cancelSync,
            child: Text(
              _isCancelling ? 'Cancelling...' : 'Cancel Sync',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        else if (_report != null && _report!.isSuccess)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: _onClose,
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        else ...[
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            onPressed: _onClose,
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: _startSync,
            child: Text(
              _report == null
                  ? 'Start Sync'
                  : (_report!.isCancelled ? 'Resume Sync' : 'Try Again'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    ),
  );
  }
}
