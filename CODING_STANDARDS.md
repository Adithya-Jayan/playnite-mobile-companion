# Coding Standards & Architectural Guardrails

This document establishes the repository-wide engineering standards, architectural invariants, code smell baselines, and static analysis guidelines for the **Playnite Mobile Companion & Delta Exporter** project. All contributions across desktop and mobile components must adhere to these standards.

---

## 1. Architectural Guardrails

### 1.1 Architecture Isolation (Presentation & Database Decoupling)
Presentation widgets (`lib/features/*/presentation/widgets/` and UI components) must **never** directly import or instantiate `AppDatabase.instance`.

- **Rule:** Direct access to `AppDatabase.instance` inside UI widgets is strictly prohibited.
- **Enforcement:** Configuration, repositories, DAOs, or domain entities must be explicitly injected into widgets via constructor parameters or state providers (such as Riverpod or inherited scopes).
- **Rationale:** Direct singleton database references bind the presentation layer tightly to SQLite IO, making widget testing cumbersome, preventing headless widget tests, and obstructing simulated preview environments.

```dart
// ❌ BAD: Direct database singleton access in presentation widget
class GameCardWidget extends StatelessWidget {
  final String gameId;
  const GameCardWidget({super.key, required this.gameId});

  @override
  Widget build(BuildContext context) {
    final game = AppDatabase.instance.getGame(gameId); // FORBIDDEN
    return Text(game.title);
  }
}

// ✅ GOOD: Dependencies injected via constructor or state provider
class GameCardWidget extends StatelessWidget {
  final GameSummary game;
  const GameCardWidget({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Text(game.title);
  }
}
```

---

### 1.2 Fail-Soft Addon Resilience
All third-party Playnite addon metadata (SuccessStory, HowLongToBeat, GameActivity, etc.) operates under the **Fail-Soft Addon Invariant** (see [GLOSSARY.md](GLOSSARY.md) and [docs/architecture-and-specs.md](docs/architecture-and-specs.md)):

- **Rule:** All addon fields, models, and payloads must be strictly optional (`Map<String, dynamic>?` or nullable types).
- **Resilience:** The omission, version drift, corruption, or unexpected nullability of an addon section payload must cleanly omit the corresponding UI card/section without throwing uncaught exceptions or crashing the mobile app.
- **Desktop Extractor Isolation:** Desktop addon extractors (`IAddonDataExtractor`) must execute within isolated error boundaries (`try/catch`). A failure in an external addon plugin must never abort or invalidate the primary library sync export.
- **Mobile Section Registry:** UI widgets rendering dynamic addon sections must register with `AddonSectionRegistry` or catch rendering exceptions gracefully, falling back to clean omission or non-blocking placeholder tiles.

```dart
// ❌ BAD: Assuming addon data presence or strict types
void renderAchievements(Map<String, dynamic> data) {
  final count = data['total'] as int; // May throw TypeError or NullCheckException
}

// ✅ GOOD: Defensive extraction with clean omission
Widget? buildAddonSection(Map<String, dynamic>? addonData) {
  if (addonData == null || addonData.isEmpty) {
    return null; // Gracefully omit UI section
  }
  final count = addonData['total'] as int? ?? 0;
  return AchievementCard(total: count);
}
```

---

### 1.3 Media Parameter Bundling
Avoid **Primitive Obsession** and **Data Clumps** when passing media identifiers and streaming metadata across layers.

- **Rule:** Group related media identifiers (such as cover SHA-256, background SHA-256, icon SHA-256, logo relative path, microtrailer relative path, and full trailer video path) into cohesive parameter objects (e.g., `GameMedia` or cohesive media bundles).
- **Prohibition:** Do not pass loose parameter lists of 4–6 raw nullable strings across widget trees, viewmodels, or service constructors.
- **Rationale:** Parameter bundling promotes deep modules, reduces constructor signature churn when new media tiers are added (e.g. trailer streaming), and eliminates error-prone argument swapping.

```dart
// ❌ BAD: Data clump of primitive strings
Widget buildHeroHeader({
  required String? coverSha256,
  required String? backgroundSha256,
  required String? iconSha256,
  required String? logoPath,
  required String? microtrailerPath,
  required String? trailerPath,
  required bool hasTrailer,
}) { ... }

// ✅ GOOD: Bundled into a cohesive parameter object
class GameMediaBundle {
  final String? coverSha256;
  final String? backgroundSha256;
  final String? iconSha256;
  final String? logoPath;
  final String? microtrailerPath;
  final String? trailerPath;

  const GameMediaBundle({
    this.coverSha256,
    this.backgroundSha256,
    this.iconSha256,
    this.logoPath,
    this.microtrailerPath,
    this.trailerPath,
  });

  bool get hasTrailer => trailerPath != null && trailerPath!.isNotEmpty;
  bool get hasMicrotrailer => microtrailerPath != null && microtrailerPath!.isNotEmpty;
}

Widget buildHeroHeader({required GameMediaBundle media}) { ... }
```

---

## 2. Baseline Code Smells (Fowler Refactoring Ch. 3)

The repository explicitly adopts the Martin Fowler *Refactoring* (Chapter 3) code smell baselines. When authoring code or participating in reviews, identify these smells and apply the recommended remedies:

| Code Smell | Description (What it is) | Remedy (How to fix) |
| :--- | :--- | :--- |
| **Mysterious Name** | A function, variable, parameter, or type whose name does not clearly communicate its intent, domain concept, or return value. | Rename to match the domain model ([GLOSSARY.md](GLOSSARY.md)); if a clear name cannot be found, reconsider and simplify the underlying design. |
| **Duplicated Code** | The exact same or structurally identical logic appears in more than one place across the codebase. | Extract shared method, helper, or domain utility and invoke it from all call sites. |
| **Feature Envy** | A function or method accesses data or invocations of another object more frequently than its own. | Move the method onto the data object it envies, or extract the envied behavior onto that object. |
| **Data Clumps** | The same cluster of 3+ fields or parameters consistently travel together across classes and function signatures. | Group them into a cohesive parameter object or value class (e.g. `GameMediaBundle`). |
| **Primitive Obsession** | Using primitives (`String`, `int`, `Map`) to represent domain entities that possess distinct invariants, validation, or behaviors. | Introduce dedicated lightweight types, value objects, or enums (e.g. `MediaStorageTier`, `ViewMode`). |
| **Repeated Switches** | Identical `switch` statements or conditional `if-else` ladders on the same enum/type scattered throughout the code. | Replace with polymorphism, strategy pattern, or a centralized mapper lookup. |
| **Shotgun Surgery** | A single conceptual requirement or feature change forces small, scattered edits across many disparate files. | Consolidate related responsibilities into a cohesive, deep module so changes localize to one place. |
| **Divergent Change** | A single module or class is frequently modified for multiple completely unrelated reasons. | Separate concerns into distinct modules so each class has a single axis of change (Single Responsibility Principle). |
| **Speculative Generality** | Premature abstractions, unused configuration parameters, or generic hooks created for hypothetical future needs. | Remove unused parameters and speculative layers; inline until a verified need emerges. |
| **Message Chains** | Long chained method calls (`a.b().c().d()`) coupling the caller to the internal structural topology of target objects. | Hide the traversal by exposing a single high-level query method on the top-level object. |
| **Middle Man** | A class or wrapper whose methods do little more than pass through calls directly to an inner collaborator. | Remove the middle man and let clients communicate directly with the underlying service. |
| **Refused Bequest** | A subclass that inherits methods or properties from a base class but ignores, throws on, or overrides most of them. | Replace inheritance with composition or extract a leaner shared interface. |

---

## 3. Static Analysis & Linter Standards

The Flutter companion app (`playnite-mobile-companion`) enforces static analysis through `analysis_options.yaml` layered on `package:flutter_lints/flutter.yaml`.

### 3.1 Mandatory Linter Rules
The following rules are actively enforced and must report **zero errors and warnings**:

- **`avoid_print`**: Prohibits raw `print()` statements. Use `debugPrint()` or structured logging instead.
- **`unawaited_futures`**: Ensures any spawned `Future` is either explicitly `await`ed or wrapped in `unawaited(...)` from `dart:async` to prevent silent unhandled asynchronous errors.
- **`prefer_const_constructors`**: Enforces `const` constructors on immutable widgets to optimize widget subtree rebuilding in Flutter.
- **`prefer_final_locals`**: Promotes immutability by requiring `final` for local variables whose references never change.
- **`use_super_parameters`**: Requires concise Dart 3 super parameter syntax (`MyWidget({super.key})`).

### 3.2 Verification
Run the Flutter static analyzer locally prior to committing:
```bash
cd playnite-mobile-companion
flutter analyze
```
Any static analysis issues (errors, warnings, or lints) will fail automated review.
