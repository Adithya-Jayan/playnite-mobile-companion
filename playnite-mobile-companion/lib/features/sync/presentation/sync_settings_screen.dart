import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/google_drive_api_service.dart';
import 'package:playnite_mobile_companion/core/services/background_sync_service.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/sync/data/demo_library_data.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/widgets/sync_dialog.dart';

class SyncSettingsScreen extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback? onSettingsChanged;

  const SyncSettingsScreen({
    super.key,
    required this.database,
    this.onSettingsChanged,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final SyncConfigRepository _configRepo;

  SyncConfiguration _config = const SyncConfiguration();
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResultText;
  bool? _testResultSuccess;
  String? _connectedAccountName;

  final TextEditingController _folderNameController = TextEditingController();
  final TextEditingController _folderIdController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  final TextEditingController _refreshTokenController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _localPathController = TextEditingController();

  bool _obscureToken = true;
  bool _obscureSecret = true;
  bool _obscureRefresh = true;

  bool _isIgnoringBatteryOptimizations = false;
  bool _isCheckingBattery = false;

  @override
  void initState() {
    super.initState();
    _configRepo = SyncConfigRepository(widget.database);
    _loadSettings();
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    _folderIdController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _refreshTokenController.dispose();
    _tokenController.dispose();
    _localPathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final cfg = await _configRepo.loadConfig();
    final isIgnoringBattery = await BackgroundSyncService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _config = cfg;
        _folderNameController.text = cfg.googleDriveFolderName;
        _folderIdController.text = cfg.googleDriveFolderId;
        _clientIdController.text = cfg.googleClientId;
        _clientSecretController.text = cfg.googleClientSecret;
        _refreshTokenController.text = cfg.googleRefreshToken;
        _tokenController.text = cfg.googleAccessToken;
        _localPathController.text = cfg.localFolderPath;
        _isIgnoringBatteryOptimizations = isIgnoringBattery;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkBatteryStatus() async {
    final status = await BackgroundSyncService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isIgnoringBatteryOptimizations = status;
      });
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    setState(() => _isCheckingBattery = true);
    await BackgroundSyncService.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(milliseconds: 1000));
    await _checkBatteryStatus();
    if (mounted) {
      setState(() => _isCheckingBattery = false);
    }
  }

  Future<void> _openBatterySettings() async {
    await BackgroundSyncService.openBatteryOptimizationSettings();
  }

  Future<void> _saveSettings({bool showToast = true}) async {
    final updated = _config.copyWith(
      googleDriveFolderName: _folderNameController.text.trim().isNotEmpty
          ? _folderNameController.text.trim()
          : 'PlayniteSync',
      googleDriveFolderId: _folderIdController.text.trim(),
      googleClientId: _clientIdController.text.trim(),
      googleClientSecret: _clientSecretController.text.trim(),
      googleRefreshToken: _refreshTokenController.text.trim(),
      googleAccessToken: _tokenController.text.trim(),
      localFolderPath: _localPathController.text.trim(),
    );

    await _configRepo.saveConfig(updated);
    if (mounted) {
      setState(() => _config = updated);
      widget.onSettingsChanged?.call();
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync settings saved successfully'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    }
  }

  Future<void> _testGoogleDriveConnection() async {
    await _saveSettings(showToast: false);

    setState(() {
      _isTesting = true;
      _testResultText = null;
      _testResultSuccess = null;
    });

    final service = GoogleDriveApiService(
      syncFolderName: _folderNameController.text.trim().isNotEmpty
          ? _folderNameController.text.trim()
          : 'PlayniteSync',
      explicitFolderId: _folderIdController.text.trim().isNotEmpty
          ? _folderIdController.text.trim()
          : null,
      clientId: _clientIdController.text.trim(),
      clientSecret: _clientSecretController.text.trim(),
      refreshToken: _refreshTokenController.text.trim(),
      onTokenRefreshed: (newToken) async {
        if (mounted) {
          setState(() {
            _tokenController.text = newToken;
            _config = _config.copyWith(googleAccessToken: newToken);
          });
        }
      },
    );

    final res = await service.testConnection();

    if (mounted) {
      setState(() {
        _isTesting = false;
        final success = res['success'] == true;
        _testResultSuccess = success;
        if (success) {
          final user = res['user'] ?? 'Google Account';
          _connectedAccountName = user;
          final count = res['fileCount'] ?? 0;
          final hasIdx = res['hasIndex'] == true ? 'with sync_index.json' : '(sync_index.json missing)';
          _testResultText = 'Connected to Drive as $user!\nFound folder "$_folderName" ($count items $hasIdx).';
        } else {
          _testResultText = res['error'] ?? 'Connection test failed.';
        }
      });
    }
  }

  String get _folderName =>
      _folderNameController.text.trim().isNotEmpty ? _folderNameController.text.trim() : 'PlayniteSync';

  Future<void> _pasteTokenFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _tokenController.text = data.text!.trim();
      });
      await _saveSettings(showToast: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access token pasted from clipboard!')),
        );
      }
    }
  }

  void _clearGoogleDriveCredentials() async {
    setState(() {
      _tokenController.clear();
      _clientIdController.clear();
      _clientSecretController.clear();
      _refreshTokenController.clear();
      _testResultText = null;
      _testResultSuccess = null;
      _connectedAccountName = null;
    });
    MediaUrlResolver.setAuthToken(null);
    await _saveSettings(showToast: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive credentials cleared')),
      );
    }
  }

  Future<void> _importDesktopPairingCode() async {
    final textController = TextEditingController();

    // Check clipboard first to see if it already contains playnite:// or a JSON object
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (clip?.text != null) {
        final txt = clip!.text!.trim();
        if (txt.startsWith('playnite://') || txt.contains('clientId') || txt.contains('client_id')) {
          textController.text = txt;
        }
      }
    } catch (_) {}

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.devices, color: AppTheme.primaryLight, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Link via Playnite Desktop',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the pairing code copied from the Playnite desktop extension (Settings > Mobile Pairing Code):',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 4,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'playnite://eyJobGllbnRJZCI6... or JSON',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Pair Now', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && textController.text.trim().isNotEmpty) {
      final raw = textController.text.trim();
      try {
        Map<String, dynamic> data;
        if (raw.startsWith('playnite://')) {
          final b64 = raw.substring('playnite://'.length);
          final decoded = utf8.decode(base64Decode(b64));
          data = jsonDecode(decoded) as Map<String, dynamic>;
        } else if (raw.startsWith('{')) {
          data = jsonDecode(raw) as Map<String, dynamic>;
        } else {
          final decoded = utf8.decode(base64Decode(raw));
          data = jsonDecode(decoded) as Map<String, dynamic>;
        }

        final cId = data['clientId'] as String? ?? data['client_id'] as String? ?? '';
        final cSecret = data['clientSecret'] as String? ?? data['client_secret'] as String? ?? '';
        final rToken = data['refreshToken'] as String? ?? data['refresh_token'] as String? ?? '';
        final aToken = data['accessToken'] as String? ?? data['access_token'] as String? ?? '';
        final fName = data['folderName'] as String? ?? data['folder_name'] as String? ?? 'PlayniteSync';

        if (cId.isEmpty || (rToken.isEmpty && aToken.isEmpty)) {
          throw const FormatException('Pairing code missing required credentials');
        }

        setState(() {
          _clientIdController.text = cId;
          _clientSecretController.text = cSecret;
          _refreshTokenController.text = rToken;
          if (aToken.isNotEmpty) {
            _tokenController.text = aToken;
          }
          if (fName.isNotEmpty) {
            _folderNameController.text = fName;
          }
        });

        await _saveSettings(showToast: false);
        await _testGoogleDriveConnection();

        if (mounted && _testResultSuccess == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully linked with Playnite Desktop! Google Drive connected.'),
              backgroundColor: AppTheme.accentGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid pairing code: $e'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _launchOAuthBrowser() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your Google Client ID below first (see Setup Guide).'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    // Standard OAuth2 authorization endpoint with drive.file scope
    const redirectUri = 'http://127.0.0.1:51734/callback';
    final url = Uri.parse(
      'https://accounts.google.com/o/oauth2/v2/auth'
      '?client_id=${Uri.encodeComponent(clientId)}'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&response_type=token'
      '&scope=${Uri.encodeComponent('https://www.googleapis.com/auth/drive.file')}',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open browser. Please paste your token directly.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching OAuth URL: $e');
    }
  }

  Future<void> _confirmResetDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Local Database?'),
        content: const Text(
          'This will purge all local games, play sessions, and achievements from this device. '
          'Your Google Drive files will NOT be touched.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset Everything', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.database.reset();
      if (!mounted) return;
      widget.onSettingsChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local database cleared.')),
      );
    }
  }

  Future<void> _seedDemoGames() async {
    setState(() => _isLoading = true);
    try {
      final gameDao = GameDao(widget.database);
      final syncMetaDao = SyncMetaDao(widget.database);

      final sampleGames = DemoLibraryData.getDemoGames();
      await gameDao.batchUpsertGames(sampleGames);

      final entries = sampleGames.map((g) => IndexEntry(
        relativePath: 'games/${g.id}.json',
        sha256: 'initial_hash_${g.id}',
        sizeBytes: 15000,
        modifiedUtc: DateTime.now().toUtc().toIso8601String(),
        driveFileId: 'mock_${g.id}',
        mimeType: 'application/json',
        category: 'game_metadata',
        gameId: g.id,
      )).toList();
      await syncMetaDao.batchUpsertEntries(entries);

      final updated = _config.copyWith(storageType: SyncStorageType.demo);
      await _configRepo.saveConfig(updated);
      if (mounted) {
        setState(() => _config = updated);
      }

      widget.onSettingsChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo library loaded successfully (4 sample games)!'),
            backgroundColor: AppTheme.accentGreen,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Error seeding demo games: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to seed demo games: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openSyncDialog() {
    final driveService = _configRepo.createDriveService(_config);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncDialog(
        database: widget.database,
        driveService: driveService,
        onSyncCompleted: () {
          widget.onSettingsChanged?.call();
          _loadSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('Sync Settings')),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Sync & Storage Settings'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save, color: AppTheme.primaryLight, size: 18),
            label: const Text('Save', style: TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
            onPressed: () => _saveSettings(showToast: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Active Backend Status
          _buildStatusCard(),
          const SizedBox(height: 20),

          // Section 2: Storage Backend Selector
          const Text(
            'Sync Source',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          _buildStorageTypeSelector(),
          const SizedBox(height: 20),

          // Section 3: Google Drive Config (if selected)
          if (_config.storageType == SyncStorageType.googleDrive) ...[
            _buildGoogleDriveConfig(),
            const SizedBox(height: 20),
          ],

          // Section 4: Local Folder Config (if selected)
          if (_config.storageType == SyncStorageType.localFolder) ...[
            _buildLocalFolderConfig(),
            const SizedBox(height: 20),
          ],

          // Section 5: Demo Mode Config (if selected)
          if (_config.storageType == SyncStorageType.demo) ...[
            _buildDemoModeConfig(),
            const SizedBox(height: 20),
          ],

          // Section 6: Background Sync & Battery Optimization
          _buildBackgroundSyncCard(),
          const SizedBox(height: 20),

          // Section: Media / Preferences
          _buildMediaPreferencesCard(),
          const SizedBox(height: 20),

          // Section 7: Sync Action & Maintenance
          _buildActionsSection(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    String statusTitle;
    String statusSubtitle;
    Color statusColor;
    IconData statusIcon;

    switch (_config.storageType) {
      case SyncStorageType.googleDrive:
        final hasToken = _tokenController.text.trim().isNotEmpty || _config.googleAccessToken.isNotEmpty;
        if (hasToken && _testResultSuccess != false) {
          statusTitle = 'Google Drive (Connected)';
          statusSubtitle = 'Target Folder: "$_folderName"${_connectedAccountName != null ? ' - $_connectedAccountName' : ''}';
          statusColor = AppTheme.accentGreen;
          statusIcon = Icons.cloud_done;
        } else if (_testResultSuccess == false) {
          statusTitle = 'Google Drive (Connection Error)';
          statusSubtitle = _testResultText ?? 'OAuth token or folder invalid';
          statusColor = AppTheme.accentRed;
          statusIcon = Icons.error_outline;
        } else {
          statusTitle = 'Google Drive (Sign In Required)';
          statusSubtitle = 'OAuth token not configured yet';
          statusColor = AppTheme.primary;
          statusIcon = Icons.cloud_queue;
        }
        break;
      case SyncStorageType.localFolder:
        statusTitle = 'Local Device Directory';
        statusSubtitle = _config.localFolderPath.isNotEmpty
            ? _config.localFolderPath
            : 'Path not configured (e.g. /sdcard/Download/PlayniteSync)';
        statusColor = AppTheme.primaryLight;
        statusIcon = Icons.folder;
        break;
      case SyncStorageType.demo:
        statusTitle = 'Demo / Offline Simulation';
        statusSubtitle = 'Using built-in sample data and mock network';
        statusColor = Colors.purpleAccent;
        statusIcon = Icons.science;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.15),
            child: Icon(statusIcon, color: statusColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor),
                ),
                const SizedBox(height: 4),
                Text(
                  statusSubtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStorageOptionTile(
            type: SyncStorageType.googleDrive,
            title: 'Google Drive Cloud Storage',
            subtitle: 'Syncs with Playnite desktop via your personal Google Drive folder.',
            icon: Icons.cloud_outlined,
          ),
          const Divider(height: 1),
          _buildStorageOptionTile(
            type: SyncStorageType.localFolder,
            title: 'Local Folder / Device Storage',
            subtitle: 'Read exported files directly from local storage (ADB / downloads / Syncthing).',
            icon: Icons.folder_outlined,
          ),
          const Divider(height: 1),
          _buildStorageOptionTile(
            type: SyncStorageType.demo,
            title: 'Demo & Sample Library',
            subtitle: 'Explore the app with rich offline demo data without any cloud setup.',
            icon: Icons.science_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStorageOptionTile({
    required SyncStorageType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _config.storageType == type;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.primaryLight : AppTheme.textMuted),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? AppTheme.primaryLight : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      trailing: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected ? AppTheme.primary : AppTheme.textMuted,
      ),
      onTap: () {
        setState(() => _config = _config.copyWith(storageType: type));
        _saveSettings(showToast: false);
      },
    );
  }

  Widget _buildGoogleDriveConfig() {
    final hasToken = _tokenController.text.trim().isNotEmpty;
    final isConnected = hasToken && (_testResultSuccess != false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_sync, color: AppTheme.primaryLight, size: 20),
              SizedBox(width: 8),
              Text(
                'Google Drive Configuration',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildOAuthSetupGuide(),
          const SizedBox(height: 14),

          if (isConnected) ...[
            // Prominent green CONNECTED status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentGreen, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.accentGreen,
                        child: Icon(Icons.check, color: Colors.black, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Google Drive',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentGreen,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'CONNECTED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target Folder: "$_folderName"',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.accentGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_connectedAccountName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Account: $_connectedAccountName',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_testResultText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_testResultSuccess == true ? AppTheme.accentGreen : AppTheme.accentRed).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (_testResultSuccess == true ? AppTheme.accentGreen : AppTheme.accentRed).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testResultSuccess == true ? Icons.check_circle_outline : Icons.error_outline,
                            size: 16,
                            color: _testResultSuccess == true ? AppTheme.accentGreen : AppTheme.accentRed,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResultText!,
                              style: TextStyle(
                                fontSize: 11,
                                color: _testResultSuccess == true ? AppTheme.accentGreen : AppTheme.accentRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentRed,
                            side: const BorderSide(color: AppTheme.accentRed),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.link_off, size: 16, color: AppTheme.accentRed),
                          label: const Text(
                            'Disconnect / Switch Account',
                            style: TextStyle(fontSize: 12, color: AppTheme.accentRed, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _clearGoogleDriveCredentials,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceLight,
                          foregroundColor: AppTheme.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        icon: _isTesting
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh, size: 16, color: AppTheme.textPrimary),
                        label: Text(
                          _isTesting ? 'Testing...' : 'Test Connection',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isTesting ? null : _testGoogleDriveConnection,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Not connected card with prominent "Connect to Google Drive" button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_off, color: AppTheme.textMuted, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Not Connected to Google Drive',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Link your Google Drive account to sync game metadata, library changes, and media art exported from Playnite on your PC.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  // Primary Pairing Action
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: AppTheme.primaryLight, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Fastest & Recommended Setup',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'In Playnite desktop on your PC, open Add-on Settings and click "Copy Mobile Pairing Code". Then tap below to connect instantly with automatic token refresh:',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.devices, size: 20, color: Colors.white),
                            label: const Text(
                              'Link via Playnite Desktop Pairing Code',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            onPressed: _importDesktopPairingCode,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'OR DIRECT MANUAL SETUP',
                          style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Google Client ID Field
                  TextField(
                    controller: _clientIdController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Google Client ID (from Google Cloud)',
                      hintText: '123456789-xxx.apps.googleusercontent.com',
                      prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.textMuted),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, color: AppTheme.primaryLight),
                        tooltip: 'Paste Client ID',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null && data!.text!.trim().isNotEmpty) {
                            setState(() => _clientIdController.text = data.text!.trim());
                            await _saveSettings(showToast: false);
                          }
                        },
                      ),
                    ),
                    onChanged: (_) => _saveSettings(showToast: false),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceLight,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.open_in_browser, size: 20, color: Colors.white),
                      label: const Text(
                        'Sign In via Browser',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: _launchOAuthBrowser,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.content_paste, size: 16, color: Colors.white),
                      label: const Text(
                        'Paste Token from Clipboard',
                        style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _pasteTokenFromClipboard,
                    ),
                  ),
                  if (_testResultText != null && _testResultSuccess == false) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: AppTheme.accentRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResultText!,
                              style: const TextStyle(fontSize: 11, color: AppTheme.accentRed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Advanced settings expansion
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: !isConnected,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'Folder & Advanced Settings',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
              ),
              subtitle: Text(
                'Target: "$_folderName" • ${hasToken ? 'Token configured' : 'No token'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              children: [
                const SizedBox(height: 10),

                // Google Client ID Field
                TextField(
                  controller: _clientIdController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Google Client ID',
                    hintText: '123456789-xxx.apps.googleusercontent.com',
                    prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.textMuted),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste, color: AppTheme.primaryLight),
                      tooltip: 'Paste Client ID',
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null && data!.text!.trim().isNotEmpty) {
                          setState(() => _clientIdController.text = data.text!.trim());
                          await _saveSettings(showToast: false);
                        }
                      },
                    ),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Google Client Secret Field
                TextField(
                  controller: _clientSecretController,
                  obscureText: _obscureSecret,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Google Client Secret',
                    hintText: 'GOCSPX-...',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscureSecret ? Icons.visibility : Icons.visibility_off, color: AppTheme.textMuted),
                          onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste, color: AppTheme.primaryLight),
                          tooltip: 'Paste Client Secret',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              setState(() => _clientSecretController.text = data.text!.trim());
                              await _saveSettings(showToast: false);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Google Refresh Token Field (Permanent Auth)
                TextField(
                  controller: _refreshTokenController,
                  obscureText: _obscureRefresh,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Google Refresh Token (Permanent Auto-Refresh)',
                    hintText: '1//0...',
                    prefixIcon: const Icon(Icons.autorenew, color: AppTheme.textMuted),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscureRefresh ? Icons.visibility : Icons.visibility_off, color: AppTheme.textMuted),
                          onPressed: () => setState(() => _obscureRefresh = !_obscureRefresh),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste, color: AppTheme.primaryLight),
                          tooltip: 'Paste Refresh Token',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              setState(() => _refreshTokenController.text = data.text!.trim());
                              await _saveSettings(showToast: false);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Folder Name Field
                TextField(
                  controller: _folderNameController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Target Google Drive Folder Name',
                    hintText: 'PlayniteSync',
                    prefixIcon: Icon(Icons.folder_outlined, color: AppTheme.textMuted),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Optional explicit Folder ID
                TextField(
                  controller: _folderIdController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Drive Folder ID (Optional)',
                    hintText: 'Leave empty to auto-detect by folder name',
                    prefixIcon: Icon(Icons.tag, color: AppTheme.textMuted),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Access Token Field
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Google OAuth Access Token (Bearer ya29...)',
                    hintText: 'ya29.a0...',
                    prefixIcon: const Icon(Icons.key, color: AppTheme.textMuted),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, color: AppTheme.textMuted),
                          onPressed: () => setState(() => _obscureToken = !_obscureToken),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste, color: AppTheme.primaryLight),
                          tooltip: 'Paste from Clipboard',
                          onPressed: _pasteTokenFromClipboard,
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) => _saveSettings(showToast: false),
                ),
                const SizedBox(height: 12),

                // Advanced Test Connection Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.network_check, size: 18, color: Colors.white),
                    label: Text(
                      _isTesting ? 'Testing Drive Connection...' : 'Test Connection / Refresh Token',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isTesting ? null : _testGoogleDriveConnection,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalFolderConfig() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_shared, color: AppTheme.primaryLight, size: 20),
              SizedBox(width: 8),
              Text('Local Directory Staging',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _localPathController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Directory Path',
              hintText: '/sdcard/Download/PlayniteSync',
              prefixIcon: Icon(Icons.folder_open, color: AppTheme.textMuted),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Copy the "PlayniteSync" export folder from your PC to your phone (e.g. via USB or Syncthing) and point this directory here.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoModeConfig() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science, color: Colors.purpleAccent, size: 20),
              SizedBox(width: 8),
              Text('Demo Library Mode',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Demo mode allows immediate inspection of all app capabilities without connecting to any cloud services. '
            'Features 4 rich games (Cyberpunk 2077, Witcher 3, Elden Ring, Encased) with Steam reviews, HowLongToBeat stats, achievements, DLCs, and playtime charts.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_to_photos, size: 18, color: Colors.white),
            label: const Text(
              'Load Demo Games Now',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            onPressed: _seedDemoGames,
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSyncCard() {
    final isUnrestricted = _isIgnoringBatteryOptimizations;
    final cardColor = isUnrestricted ? AppTheme.accentGreen : AppTheme.primaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Background Execution',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: cardColor.withValues(alpha: 0.15),
                    child: Icon(
                      isUnrestricted ? Icons.battery_charging_full : Icons.battery_alert,
                      size: 18,
                      color: cardColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Background Sync & Battery Optimization',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isUnrestricted
                              ? 'Unrestricted (Downloads continue in background)'
                              : 'Battery Optimized (Downloads may pause out of focus)',
                          style: TextStyle(
                            fontSize: 12,
                            color: cardColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
                    tooltip: 'Refresh Status',
                    onPressed: _checkBatteryStatus,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isUnrestricted
                    ? 'Your system allows Playnite Companion to maintain background sockets and CPU locks so large library syncs and media downloads continue smoothly when minimized or when the screen is locked.'
                    : 'Android battery saver may terminate active network downloads or drop sockets when the app is minimized. Request unrestricted background sync to ensure reliable downloads.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!isUnrestricted)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: _isCheckingBattery
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.bolt, size: 16, color: Colors.white),
                      label: const Text(
                        'Request Unrestricted Background Sync',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: _isCheckingBattery ? null : _requestIgnoreBatteryOptimizations,
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.dividerColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 15, color: AppTheme.textMuted),
                    label: const Text(
                      'Battery Settings',
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    ),
                    onPressed: _openBatterySettings,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaPreferencesCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Media / Preferences',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            secondary: const Icon(Icons.video_library_outlined, color: AppTheme.primaryLight),
            title: const Text(
              'Auto-stream full trailers in hero banner',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'When disabled, full trailers only play when you tap Watch Trailer to save mobile data',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            value: _config.autoStreamTrailersInHero,
            activeThumbColor: AppTheme.primaryLight,
            onChanged: (val) async {
              setState(() {
                _config = _config.copyWith(autoStreamTrailersInHero: val);
              });
              await _saveSettings(showToast: false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionsSection() {
    final isDemo = _config.storageType == SyncStorageType.demo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions & Library Management',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              if (!isDemo) ...[
                ListTile(
                  leading: const Icon(Icons.sync, color: AppTheme.primaryLight),
                  title: const Text('Run Delta Sync Now', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: const Text('Pull latest game changes and artwork from active sync provider',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                  onTap: _openSyncDialog,
                ),
                const Divider(height: 1),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.library_books, color: Colors.purpleAccent),
                  title: const Text('Explore Library', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: const Text('Return to Library to browse the 4 seeded demo games',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                  onTap: () {
                    widget.onSettingsChanged?.call();
                    Navigator.of(context).pop();
                  },
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: Icon(
                  Icons.restore,
                  color: isDemo ? Colors.purpleAccent : AppTheme.primaryLight,
                ),
                title: Text(
                  isDemo ? 'Re-seed Demo Library' : 'Load Demo Sample Games',
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Restore sample games (Cyberpunk 2077, Witcher 3, Elden Ring, Encased)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                onTap: _seedDemoGames,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: AppTheme.accentRed),
                title: const Text('Reset Local Database', style: TextStyle(color: AppTheme.accentRed)),
                subtitle: const Text('Wipes local games and clears cache for a clean state',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                onTap: _confirmResetDatabase,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOAuthSetupGuide() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.help_outline, color: AppTheme.primaryLight, size: 22),
          title: const Text(
            'Google Drive Setup & Troubleshooting Guide',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
          ),
          subtitle: const Text(
            'Why did I see 401 Unauthorized? How to connect easily?',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _buildGuideStep(
              step: '★',
              title: 'Fastest Method: Desktop Pairing Code (Recommended)',
              body: '1. In Playnite on your PC, open Settings > Playnite Exporter.\n'
                  '2. Click "Copy Mobile Pairing Code".\n'
                  '3. On this phone, tap "Link via Playnite Desktop Pairing Code" above and paste it.\n'
                  'Your phone will connect immediately and automatically refresh tokens forever!',
            ),
            const SizedBox(height: 8),
            _buildGuideStep(
              step: '!',
              title: 'Why did I see "401 Unauthorized" when entering Client ID?',
              body: 'A Google Client ID (e.g. 123...apps.googleusercontent.com) is only a public application identifier, not an access token. '
                  'Google Drive API requires a signed OAuth access token. Google access tokens expire after 60 minutes, so a Refresh Token or Desktop Pairing Code is required to keep mobile connected permanently.',
            ),
            const SizedBox(height: 8),
            _buildGuideStep(
              step: '2',
              title: 'Direct Manual Setup (Alternative)',
              body: 'If entering credentials manually:\n'
                  '• Enter your Google Client ID, Client Secret, and Refresh Token in "Folder & Advanced Settings" below.\n'
                  '• The app will automatically request fresh access tokens in the background on HTTP 401.',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.primaryLight),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zero Cloud Alternative: Switch Sync Source to "Local Folder / Device Storage". '
                      'You can copy the PlayniteSync folder via USB cable or Syncthing wireless LAN sync with 0 API setup!',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep({required String step, required String title, required String body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: AppTheme.primary,
          child: Text(step, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
