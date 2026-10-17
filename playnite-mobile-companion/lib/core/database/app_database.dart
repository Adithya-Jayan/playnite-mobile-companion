import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;
import '../config/app_constants.dart';

/// Database provider and connection manager for SQLite.
/// Supports desktop, iOS, Android, and headless unit tests.
class AppDatabase {
  static AppDatabase? _instance;
  Database? _db;

  AppDatabase._();

  static AppDatabase get instance => _instance ??= AppDatabase._();

  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call AppDatabase.instance.init() first.');
    }
    return _db!;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  /// Initializes the SQLite database. Supports in-memory database for testing.
  Future<void> init({bool inMemory = false, String? customPath}) async {
    if (_db != null && _db!.isOpen) return;

    // Initialize FFI for Windows/Linux/macOS desktop and unit test environments
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS || inMemory)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (inMemory) {
      path = inMemoryDatabasePath;
    } else if (customPath != null) {
      path = customPath;
    } else {
      String basePath;
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          basePath = await getDatabasesPath();
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          basePath = docDir.path;
        }
      } catch (e) {
        debugPrint('Failed to get database directory: $e');
        final docDir = await getApplicationDocumentsDirectory();
        basePath = docDir.path;
      }
      path = p.join(basePath, AppConstants.databaseFileName);
    }

    _db = await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Reserved for future version migrations
      },
    );
  }

  /// Closes database connection
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  /// Drops and recreates all tables (used for clean resets)
  Future<void> reset() async {
    final database = db;
    await database.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS games_fts;');
      await txn.execute('DROP TABLE IF EXISTS dlc_items;');
      await txn.execute('DROP TABLE IF EXISTS hltb_data;');
      await txn.execute('DROP TABLE IF EXISTS play_sessions;');
      await txn.execute('DROP TABLE IF EXISTS achievements;');
      await txn.execute('DROP TABLE IF EXISTS manifest_meta;');
      await txn.execute('DROP TABLE IF EXISTS sync_entries;');
      await txn.execute('DROP TABLE IF EXISTS games;');
    });
    await _createSchema(database);
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    // 1. Core Games Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS games (
        id TEXT PRIMARY KEY,
        game_id TEXT NOT NULL,
        plugin_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sorting_name TEXT NOT NULL,
        description TEXT,
        notes TEXT,
        playtime_seconds INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        added_utc TEXT,
        modified_utc TEXT,
        last_activity_utc TEXT,
        recent_activity_utc TEXT,
        release_date TEXT,
        is_installed INTEGER NOT NULL DEFAULT 0,
        install_directory TEXT,
        install_size_bytes INTEGER,
        hidden INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        user_score INTEGER,
        critic_score INTEGER,
        community_score INTEGER,
        version TEXT,
        source_id TEXT,
        source_name TEXT,
        completion_status_id TEXT,
        completion_status_name TEXT,
        cover_drive_file_id TEXT,
        cover_sha256 TEXT,
        background_drive_file_id TEXT,
        background_sha256 TEXT,
        logo_drive_file_id TEXT,
        microtrailer_drive_file_id TEXT,
        trailer_drive_file_id TEXT,
        platforms_json TEXT NOT NULL DEFAULT '[]',
        genres_json TEXT NOT NULL DEFAULT '[]',
        categories_json TEXT NOT NULL DEFAULT '[]',
        tags_json TEXT NOT NULL DEFAULT '[]',
        developers_json TEXT NOT NULL DEFAULT '[]',
        publishers_json TEXT NOT NULL DEFAULT '[]',
        features_json TEXT NOT NULL DEFAULT '[]',
        links_json TEXT NOT NULL DEFAULT '[]',
        addons_json TEXT NOT NULL DEFAULT '{}'
      );
    ''');

    // Indexes for high-performance library filtering & sorting
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_sorting_name ON games(sorting_name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_playtime ON games(playtime_seconds DESC);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_last_activity ON games(last_activity_utc DESC);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_source ON games(source_name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_completion ON games(completion_status_name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_is_installed ON games(is_installed);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_games_favorite ON games(favorite);');

    // 2. Full-Text Search (FTS5) Virtual Table
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS games_fts USING fts5(
          id UNINDEXED,
          name,
          sorting_name,
          description,
          developers,
          publishers,
          genres,
          tags
        );
      ''');
    } catch (e) {
      debugPrint('FTS5 table initialization warning: $e');
    }

    // 3. Sync Entries Table (authoritative local representation of sync_index.json)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_entries (
        relative_path TEXT PRIMARY KEY,
        sha256 TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        modified_utc TEXT NOT NULL,
        drive_file_id TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        category TEXT NOT NULL,
        game_id TEXT,
        last_synced_utc TEXT NOT NULL
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_category ON sync_entries(category);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_game_id ON sync_entries(game_id);');

    // 4. Manifest Meta Table (Library dictionaries & summary metrics)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS manifest_meta (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_utc TEXT NOT NULL
      );
    ''');

    // 5. Normalized Addon Tables for rapid relational queries
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id TEXT NOT NULL,
        api_name TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        url_unlocked TEXT,
        url_locked TEXT,
        date_unlocked_utc TEXT,
        percent REAL,
        gamer_score REAL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_achievements_game_id ON achievements(game_id);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS play_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id TEXT NOT NULL,
        date_session_utc TEXT NOT NULL,
        elapsed_seconds INTEGER NOT NULL,
        action_name TEXT,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_play_sessions_game_id ON play_sessions(game_id);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hltb_data (
        game_id TEXT PRIMARY KEY,
        main_story_seconds INTEGER,
        main_extra_seconds INTEGER,
        completionist_seconds INTEGER,
        all_styles_seconds INTEGER,
        hltb_id TEXT,
        url TEXT,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dlc_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id TEXT NOT NULL,
        dlc_id TEXT NOT NULL,
        name TEXT NOT NULL,
        is_owned INTEGER NOT NULL DEFAULT 0,
        price REAL,
        currency TEXT,
        url TEXT,
        image_url TEXT,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dlc_items_game_id ON dlc_items(game_id);');
  }
}
