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
