# Phase 2: Audit, Bugfix & UX Polish Sprint Roadmap

**Sprint Lead:** Master Orchestrator Agent  
**Target Projects:** `playnite-exporter-plugin` (C# .NET) & `playnite-mobile-companion` (Flutter / Dart)  
**Status:** In Progress (Phase 1: Deep Audit & Live-Device Diagnostics)  
**Timestamp:** 2026-10-18T10:09:00+05:30  

---

## 1. Sprint Overview & Backlog Matrix

| Domain | Item ID | Feature / Issue Description | Priority | Assigned Agent / Role | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A: Data Pipeline** | A1 | Full Extension Path & Schema Audit (Hardware specs `0`/`[]`, missing plugin data) | P0 | `Data-Pipeline-Auditor-Agent` | In Progress |
| **A: Data Pipeline** | A2 | DuplicateHider separation & tagging (Hidden items + Related Games duplicate suppression) | P0 | `Data-Pipeline-Auditor-Agent` / `Playnite-Plugin-Fix-Agent` | Pending Phase 1 Audit |
| **A: Data Pipeline** | A3 | Unknown Store / Platform Hyperlinks (PSN, Xbox, etc. label and icon mapping) | P1 | `Data-Pipeline-Auditor-Agent` / `Playnite-Plugin-Fix-Agent` | Pending Phase 1 Audit |
| **A: Data Pipeline** | A4 | Rating Score Source Selection (Default to Public/Community score; options for Critic, User, Composite in Gallery Settings; fix SQLite NULL comparison) | P0 | `Data-Pipeline-Auditor-Agent` / `Data-Filter-SubAgent` | Approved / In Progress |
| **B: Detail View** | B5 | SuccessStory Achievements Overhaul (Default Unlocked tab, 4–5 compact view, rarity badges & sorting, icons, store deep links) | P0 | `Detail-View-SubAgent` | In Progress |
| **B: Detail View** | B6 | Micro-Trailer / Video Controls (Auto-fading scrub bar & mute toggle on tap/hover + Gallery Settings toggles) | P1 | `Detail-View-SubAgent` | In Progress |
| **B: Detail View** | B7 | GameActivity Play Session Visualizer (Interactive Histogram / Cumulative Line Chart + collapsible logs) | P1 | `Detail-View-SubAgent` | In Progress |
| **C: Library & UX** | C8 | Android Edge-Swipe Back Gesture Conflict (`drawerEnableOpenDragGesture: false`) | P0 | `UX-Branding-SubAgent` | In Progress |
| **C: Library & UX** | C9 | Expanded Sorting Options (Added, Playtime, Last Played, Times Played, Public/Critic Rating, Release, Name) | P1 | `Data-Filter-SubAgent` | In Progress |
| **C: Library & UX** | C10 | Persistent Sort & Filter State (Save/restore via SharedPreferences / Local SQLite) | P0 | `Data-Filter-SubAgent` | In Progress |
| **C: Library & UX** | C11 | Dedicated "Utility Filters" Category in Drawer (Hidden, Missing Covers, DuplicateHider copies, Missing Trailers, Unplayed) | P1 | `Data-Filter-SubAgent` | In Progress |
| **D: Identity** | D12 | App Identity & Launcher Icons ("Playnite Mobile Companion" naming across Android/iOS + custom gaming launcher icon) | P1 | `UX-Branding-SubAgent` | In Progress |
| **D: Identity** | D13 | Proactive QoL Polish (Alphabetical fast-scroll scrub thumb, "Surprise Me" backlog picker, HLTB slider, hero transitions) | P2 | `Architect-Agent` / `Mobile-Lead-Agent` | In Progress |
| **D: Settings** | D14 | Media Download Storage Mode in Gallery Settings (Default: Cache Only; suggest sync on upgrade; auto-clean space on downgrade) | P1 | `Mobile-Lead-Agent` | In Progress |

---

## 2. Sprint Phase Gates

- [x] **Phase 0: Orchestrator Sprint Kickoff & Roadmap Initialization**
- [x] **Phase 1: Deep Audit & Live-Device Diagnostics (Interactive Gate)**
  - [x] Task 1.1: `Data-Pipeline-Auditor-Agent` audit of Playnite `ExtensionsData` vs C# Exporter & Dart models ([Audit Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/AUDIT_REPORTS/DATA_PIPELINE_AUDIT.md))
  - [x] Task 1.2: `Media-Loading-Investigator-Agent` audit of thumbnail/background image lifecycle & caching ([Audit Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/AUDIT_REPORTS/MEDIA_LOADING_AUDIT.md))
  - [x] Task 1.3: Interactive Gate: Physical device detected (Google Pixel 8 • `38191FDJH00CWL`)
  - [x] Task 1.4: `Live-Debug-Agent` live session via `flutter run -d 38191FDJH00CWL` ([Diagnostics Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/AUDIT_REPORTS/LIVE_DEVICE_DIAGNOSTICS.md))
- [x] **Phase 2: Architecture Spec Updates & Proactive Feature Design**
  - [x] Task 2.1: `Architect-Agent` updates `.orchestrator/SPECS/` with revised C# export schema and UI blueprints ([Specification](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/SPECS/PHASE2_REVISED_SPEC.md))
  - [x] Task 2.2: `Spec-Verifier-Agent` delta-sync backwards-compatibility check ([QA Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/QA_REPORTS/PHASE2_SPEC_QA.md))
- [x] **Phase 3: C# Playnite Plugin Fixes & Independent Verification**
  - [x] Task 3.1: `Playnite-Plugin-Fix-Agent` code fixes for Hardware specs, DuplicateHider, Link labels, Achievement icons ([Implementation Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/playnite-exporter-plugin/))
  - [x] Task 3.2: `Plugin-Verification-Agent` build, export test, and QA report ([QA Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/QA_REPORTS/PHASE3_PLUGIN_QA.md))
- [x] **Phase 4: Flutter Mobile App Fixes & Feature Implementation**
  - [x] Task 4.1: `Mobile-Lead-Agent` coordinating full UI overhaul & UX polish sprint ([Implementation Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/playnite-mobile-companion/))
  - [x] Task 4.2: `Mobile-Verification-Agent` (`flutter analyze`, unit tests, release APK packaging) ([QA Report](file:///C:/Users/adith/Documents/Code/Playnite_Addon/.orchestrator/QA_REPORTS/PHASE4_MOBILE_QA.md))
- [/] **Phase 5: Live Device Verification Run & Final Release Build**
  - [/] Task 5.1: Live device verification on connected phone (Pixel 8)
  - [x] Task 5.2: Final binary artifact packaging (`.pext` and `.apk` in [`dist/`](file:///C:/Users/adith/Documents/Code/Playnite_Addon/dist/))

---

## 3. Logs & Artifacts Reference
- Audit Reports: `.orchestrator/AUDIT_REPORTS/`
- Architecture Specs: `.orchestrator/SPECS/`
- Verification Reports: `.orchestrator/QA_REPORTS/`
- Binary Distribution: `dist/`
