# 1. Use sqflite and Raw SQL over Drift ORM

Date: 2026-10-20
Status: Accepted

## Context
The initial mobile architecture blueprint specified Drift (formerly Moor) as an offline reactive ORM with normalized relational tables for addons and taxonomies. During Android implementation and testing with large game libraries (1,500+ titles and dynamic addon metadata), Drift introduced significant schema migration rigidity when handling polymorphic, third-party addon payloads (SuccessStory, HowLongToBeat, GameActivity). Furthermore, Drift's FFI dependencies required platform-specific compilation hurdles compared to Android's built-in SQLite engine.

## Decision
We decided to use `sqflite` with raw SQL queries and denormalized JSON columns (`addons_json`, `platforms_json`, `links_json`) backed by indexed text/FTS search instead of Drift ORM.

## Consequences
- **Positive**: Third-party addon schema changes never require database table migrations or risk deserialization crashes on app update.
- **Positive**: Bulk sync ingestion utilizes raw high-throughput SQLite transaction batches with minimal serialization overhead.
- **Negative**: Compile-time query type verification is traded for runtime DAO unit tests and manual SQL string maintenance.

## Amendment: 2026-11-22 - Addon Ingestion Consolidation & Dual Storage Resolution
### Context
Denormalizing large polymorphic addon payloads (such as thousands of achievement items, HLTB completion times, DLC manifests, and play session logs) directly inside `games.addons_json` while simultaneously inserting them into dedicated relational tables (`achievements`, `play_sessions`, `game_how_long_to_beat`, `game_dlc`) caused severe database bloat and triggered Android SQLite 2MB `CursorWindow` crashes during library queries. An ad-hoc emergency truncation (`UPDATE games SET addons_json = '{}' WHERE length > 500000`) caused UI state desynchronization between library views and detail screens.

### Decision
1. **Relational Addon Stripping**: `UnifiedGamePayload.toDatabaseRow` strips bulk relational addon payloads (`achievements`, `playnite_achievements`, `success_story`, `game_activity`, `player_activities`, `how_long_to_beat`, `check_dlc`) before saving `games.addons_json`. The `games.addons_json` column is strictly reserved for lightweight non-relational metadata (<10KB).
2. **Unified Addon Descriptors (`IAddonDbHandler`)**: Each relational addon domain implements `IAddonDbHandler` with `unpack`, `delete`, and `loadData(gameId, database)`. `AddonDbRegistry` registers canonical descriptors (`AchievementsDbHandler`, `SessionsDbHandler`, `HltbDbHandler`, `DlcDbHandler`).
3. **On-Demand Composition**: `GameDao.getGameAddons(gameId)` reconstructs the unified addon map on demand by querying relational tables via the registered descriptors and merging the results with the lightweight `games.addons_json`.
4. **Lifecycle Locality**: Game batch deletions (`GameDao.batchDeleteGames`) automatically delegate cascading deletions to all registered descriptors, eliminating hardcoded ad-hoc SQL deletions spread across DAOs.
