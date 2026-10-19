# Playnite Community Showcase Post

> **Where to post:**
> * **Reddit (Official Community):** [r/playnite](https://www.reddit.com/r/playnite/) (flair: *Add-on / Extension*)
> * **Official Playnite Discord:** [discord.gg/BrtABqe](https://discord.gg/BrtABqe) (`#extensions-and-themes` / `#showcase`)
> * **Official Add-ons Directory:** [playnite.link/addons.html](https://playnite.link/addons.html) (via our open [PR #705](https://github.com/JosefNemec/PlayniteAddonDatabase/pull/705))
> 
> **Post Title:** `[Extension] Mobile Delta Sync & Android Companion App (Offline-First, Micro-Trailers & Stats)`

---

## Post Body (Copy and Paste into Forum Topic)

![Playnite Mobile Companion Banner](https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/banner.png)

Hey everyone! 👋

I'm excited to share **Playnite Mobile Companion & Delta Sync** — an offline-first companion system designed to bring your full Playnite PC game library, rich metadata, achievements, session history, and video trailers to your Android phone with fast incremental cloud synchronization.

---

### 💡 Why Build This?
Most mobile game collection apps either require manual cataloging, rely on proprietary third-party servers, or force you to enter Steam/GOG credentials on your phone.

Playnite Mobile Companion works completely differently:
1. **$O(\Delta)$ Incremental Delta Sync:** After the initial export, when you stop playing a game, Playnite exports *only* the single modified game JSON and new media assets in seconds.
2. **Zero Third-Party Relays:** Syncs directly via your own personal **Google Drive** (using least-privilege `drive.file` scope — it cannot read any other files) or **Local Folder / Google Drive for Desktop**.
3. **100% Offline Capability:** The mobile app stores everything in a local SQLite database with sub-millisecond FTS5 search. You can browse, filter, and inspect your full collection on an airplane, subway, or with Wi-Fi off.

---

### ✨ Key Features

#### 📱 Android Companion App
* **High-FPS Virtualized Browsing:** High-performance Grid, List, and Details views with smooth alphabet scrubber and card scaling.
* **Rich Addon Integration:**
  * **SuccessStory:** Unlocked and locked achievements, gamer scores, and icons.
  * **HowLongToBeat:** Main Story, Main + Extra, and Completionist target times.
  * **GameActivity:** Detailed play session history timeline and interactive playtime charts.
  * **ExtraMetadataLoader:** High-resolution transparent game logos and looping video micro-trailers.
  * **CheckDlc:** Owned and unowned DLC listings.
  * **SteamReviews & SystemChecker:** Hardware requirements and community review scores.
* **Looping Video Trailers:** Auto-plays lightweight micro-trailers and web trailers with auto-fading controls.
* **Global Statistics Dashboard:** Total playtime, completion rate donut charts, and platform breakdown graphs.
* **Multi-Criteria Filtering & Search:** Search across platforms, genres, sources, completion statuses, tags, and review scores.
* **Built-in Demo Library:** Test and explore the app immediately without configuring cloud credentials.

#### 🖥️ Desktop Exporter Addon
* **SDK Lifecycle Hooks:** Automatically triggers a background delta sync the moment you exit a game (`OnGameStopped`).
* **Content-Addressable Deduplication:** Deduplicates cover art and wallpapers via SHA-256 hashes so you never upload duplicate media.
* **Native Progress Bar with ETA:** Full visibility during initial export and delta updates.

---

### 📸 Screenshots

| Library Grid | Filter Drawer | Game Detail Hero | Achievements & HLTB |
|:---:|:---:|:---:|:---:|
| <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/Min_Library_Grid_View.png" width="220" /> | <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/FilterDraw.png" width="220" /> | <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/GameHeroSection.png" width="220" /> | <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/GameDetails_Achievements_howlongtobeat_Playsessions.png" width="220" /> |

| Global Stats & Donut | Playtime Breakdown | Cloud & Storage Settings |
|:---:|:---:|:---:|
| <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/LibraryStats1_TotPlaytime_Completion_PlaytimeByStorefront.png" width="230" /> | <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/LibraryStats2_PlaytimebyPlatform_MostPlayedGames.png" width="230" /> | <img src="https://raw.githubusercontent.com/Adithya-Jayan/playnite-mobile-companion/master/docs/screenshots/SyncAndStorageSettings.png" width="230" /> |

---

### 🚀 Downloads & Getting Started

* **📦 Download Desktop Addon:** [`MobileDeltaSyncExporter.pext`](https://github.com/Adithya-Jayan/playnite-mobile-companion/releases/latest/download/MobileDeltaSyncExporter.pext) *(Double-click to install into Playnite)*
* **📱 Download Android App:** [`playnite-mobile-companion.apk`](https://github.com/Adithya-Jayan/playnite-mobile-companion/releases/latest/download/playnite-mobile-companion.apk) *(Sideload onto any Android 8.0+ device)*
* **⭐ GitHub Repository & Documentation:** [github.com/Adithya-Jayan/playnite-mobile-companion](https://github.com/Adithya-Jayan/playnite-mobile-companion)

Feedback, feature requests, and bug reports are welcome! Let me know what you think!
