# Playnite Mobile Companion & Delta Exporter

A two-part system consisting of a Playnite desktop extension and a Flutter Android companion app providing high-speed offline access, dynamic addon support, and bandwidth-efficient cloud delta synchronization.

## Language

### Sync & Storage

**Sync Index**:
A central remote manifest (`sync_index.json`) declaring all games, metadata files, media assets, their SHA-256 hashes, file sizes, and categories.
_Avoid_: Catalog, manifest file, remote index

**Delta Sync**:
An incremental synchronization protocol transferring only dirty, added, or deleted JSON payloads and content-addressed media without touching unchanged games.
_Avoid_: Partial sync, differential update

**Content-Addressable Storage (CAS)**:
A storage layout where media assets (covers, backgrounds, icons) are named and indexed by their SHA-256 hash to guarantee deduplication across the library.
_Avoid_: Hash storage, dedup store

### Media

**Microtrailer**:
A lightweight, looping, muted short video preview (typically ~2MB SD MP4) displayed automatically in the hero header.
_Avoid_: Teaser, preview clip, short video

**Full Trailer**:
A high-definition video with full audio meant strictly for on-demand playback upon explicit user interaction.
_Avoid_: Long trailer, trailer video

### Taxonomy & Addons

**Addon Data Extractor**:
An isolated desktop plugin pipeline component extracting external plugin data (e.g. SuccessStory, HowLongToBeat, GameActivity) with error boundary protection.
_Avoid_: Plugin scraper, addon parser

**Addon Section**:
A polymorphic Flutter UI component that renders external addon metadata or gracefully disappears when the metadata is absent.
_Avoid_: Plugin card, addon widget

**Duplicate Group**:
A collection of identical game titles owned across multiple platforms or storefronts linked together by DuplicateHider.
_Avoid_: Clones, copies, game group
