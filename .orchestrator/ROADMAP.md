# Master Orchestrator Roadmap: Playnite Delta-Sync & Mobile Companion Ecosystem

## Project Overview
Build an end-to-end, high-performance, offline-first ecosystem consisting of:
1. **Playnite Desktop Extension (`playnite-exporter-plugin`)**: Exports library, addons, media, and statistics, executing strict incremental hash-based delta-sync to Google Drive.
2. **Flutter Mobile Companion App (`playnite-mobile-companion`)**: Pulls incremental deltas from Google Drive into a high-performance local database for instant, read-only library exploration, media streaming/caching, statistics dashboards, and addon details.

---

## Architectural Constraints & Guarantees
- **Strict Incremental Delta-Sync Protocol**: Only transfer changed, new, or deleted files. Zero re-uploading/re-downloading of unchanged data or media.
- **Content-Addressable Index (`sync_index.json`)**: Root index containing file hash (SHA-256/MD5), size, `last_modified`, and Drive metadata.
- **Granular Partitioning**: Per-game JSON metadata (`games/<game_id>.json`) and content-addressed media assets (`media/covers/<hash>.webp`, `media/videos/<game_id>.mp4`).
- **Dynamic Addon Extensibility & Fault-Tolerant Schema**: Adding, removing, or disabling Playnite addons in the future must NEVER break either the Playnite exporter or the Flutter mobile companion. Addon parsers must use an extensible registry (`IAddonDataExtractor`), the mobile app must dynamically adapt UI cards/tabs based on available payload fields, and unknown or removed addon data must degrade gracefully without parse or runtime crashes.
- **Read-Only Mobile Scope**: Strictly browsing, filtering, search, statistics, and media viewing. No remote launch, no direct store credentials.
- **Verification Gates**: Every phase requires automated verification and formal QA reports before signoff.

---

## Phases & Execution Status

| Phase | Description | Status | Verification Gate |
|---|---|---|---|
| **Phase 1: Discovery & Reverse-Engineering** | Catalog Playnite environment (`AppData/Roaming/Playnite`), core DB, extensions, addon schemas, extra media. | 🟢 COMPLETE (PASSED) | Discovery-Verifier audited 100% of extensions (48/48 folders, 36/36 plugins). Report in `QA_REPORTS/PHASE1_DISCOVERY_QA.md`. |
| **Phase 2: Delta-Sync Architecture & Contract Definition** | Design `DELTA_SYNC_SPEC.md`, `GAME_PAYLOAD_SCHEMA.json`, and technical blueprints for C# extension and Flutter app. | 🟢 COMPLETE (PASSED) | Spec-Verifier validation in `QA_REPORTS/PHASE2_SPEC_QA.md` (Zero data loss, strict delta O(1), addon resilience). |
| **Phase 3: Playnite Export & Delta-Push Extension** | Implement C# Playnite plugin (`playnite-exporter-plugin`), SDK hooks, addon parsers, hasher, Drive delta-sync engine, settings UI. | 🟢 COMPLETE (PASSED) | Automated delta tests (100% initial, 0 on no-op, 1 on single game update) and addon fault tolerance verified in `QA_REPORTS/PHASE3_PLUGIN_QA.md`. |
| **Phase 4: Mobile Companion App (Flutter)** | Scaffold Flutter app (`playnite-mobile-companion`), SQLite/Isar DB, delta-pull sync engine, library views, game detail, addon tabs, stats dashboard. | 🟢 COMPLETE (PASSED) | `flutter analyze` (0 errors), 12/12 unit tests passing, delta pull network invariant verified in `QA_REPORTS/PHASE4_MOBILE_QA.md`. |
| **Phase 5: End-to-End Integration & Polish** | Full pipeline end-to-end test, edge case validation (deletions, media changes, interrupted syncs), deployment guide. | 🟢 COMPLETE (PASSED) | Integration-QA signoff report in `QA_REPORTS/PHASE5_INTEGRATION_QA.md` + `DEPLOYMENT_GUIDE.md`. |

---

## Agent Hierarchy & Roles
- **Master Orchestrator Agent** (Active)
  - **Recon-Agent** (Phase 1 Lead - Complete)
  - **Discovery-Verifier-Agent** (Phase 1 QA - Complete)
  - **Architect-Agent** (Phase 2 Lead - Complete)
  - **Spec-Verifier-Agent** (Phase 2 QA - Complete)
  - **Playnite-Plugin-Lead-Agent** (Phase 3 Lead - Complete)
  - **Plugin-Verification-Agent** (Phase 3 QA - Complete)
  - **Mobile-Lead-Agent** (Phase 4 Lead - Complete)
  - **Mobile-Verification-Agent** (Phase 4 QA - Complete)
  - **Integration-QA-Agent** (Phase 5 Lead - Complete)

---

## Current Active Tasks
- [x] Orchestrator directory setup (`.orchestrator/ROADMAP.md`, `.orchestrator/SPECS/`, `.orchestrator/QA_REPORTS/`)
- [x] Phase 1: Launch `Recon-Agent` to scan Playnite (strictly read-only)
- [x] Phase 1: Catalog installed addons, data storage formats, and media caches in `.orchestrator/SPECS/DATA_SCHEMA.md`
- [x] Phase 1: Run `Discovery-Verifier-Agent` to generate `QA_REPORTS/PHASE1_DISCOVERY_QA.md` (PASSED)
- [x] Phase 2: Launch `Architect-Agent` to design `DELTA_SYNC_SPEC.md`, `GAME_PAYLOAD_SCHEMA.json`, and technical blueprints
- [x] Phase 2: Launch `Spec-Verifier-Agent` to verify contract and delta properties (`QA_REPORTS/PHASE2_SPEC_QA.md` - PASSED)
- [x] Phase 3: Launch `Playnite-Plugin-Lead-Agent` to build `playnite-exporter-plugin`
- [x] Phase 3: Launch `Plugin-Verification-Agent` to verify build, tests, and delta invariants (`QA_REPORTS/PHASE3_PLUGIN_QA.md` - PASSED)
- [x] Phase 4: Launch `Mobile-Lead-Agent` to build `playnite-mobile-companion` (Flutter)
- [x] Phase 4: Launch `Mobile-Verification-Agent` to audit analyze, tests, and network delta efficiency (`QA_REPORTS/PHASE4_MOBILE_QA.md` - PASSED)
- [x] Phase 5: Launch `Integration-QA-Agent` for end-to-end integration and polish
- [x] Phase 5: Verify edge cases (deletions, media changes, interrupted syncs, offline mode)
- [x] Phase 5: Generate `DEPLOYMENT_GUIDE.md` and `QA_REPORTS/PHASE5_INTEGRATION_QA.md`
