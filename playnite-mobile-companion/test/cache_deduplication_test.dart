import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayniteImageLoader Single-File Caching & Deduplication Tests', () {
    late PlayniteImageLoader loader;

    setUp(() async {
      loader = PlayniteImageLoader.instance;
      await loader.init();
      await loader.clearCache();
    });

    test('1. saveToCache writes exactly one physical file on disk and aliases resolve to it', () async {
      const primaryKey = '1AbcDriveFileId123';
      const aliasRelPath = 'media/covers/game_cover.jpg';
      const aliasSha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final payloadBytes = List<int>.generate(1024, (i) => i % 256); // 1 KB payload

      await loader.saveToCache(
        keyOrMediaId: primaryKey,
        bytes: payloadBytes,
        aliases: [aliasRelPath, aliasSha256],
      );

      // Verify that primary key resolves synchronously
      final primaryFile = loader.getCachedFileSync(primaryKey);
      expect(primaryFile, isNotNull);
      expect(primaryFile!.existsSync(), isTrue);
      expect(primaryFile.lengthSync(), equals(1024));

      // Verify that aliases resolve synchronously to the EXACT SAME physical file
      final relPathFile = loader.getCachedFileSync(aliasRelPath);
      expect(relPathFile, isNotNull);
      expect(relPathFile!.path, equals(primaryFile.path));

      final shaFile = loader.getCachedFileSync(aliasSha256);
      expect(shaFile, isNotNull);
      expect(shaFile!.path, equals(primaryFile.path));

      // Disk usage must be 1024 bytes (1 file), NOT 3072 bytes (3 files)
      final totalDiskBytes = await loader.getCacheSizeBytes();
      expect(totalDiskBytes, equals(1024));
    });

    test('2. deduplicateCache removes legacy duplicate physical files and registers alias', () async {
      const primaryKey = 'drive_file_id_hero';
      const legacyAliasKey = 'media_covers_hero_jpg';
      final payloadBytes = List<int>.generate(2048, (i) => i % 256); // 2 KB payload

      // Simulate a legacy build that created two physical duplicate files on disk
      await loader.saveToCache(keyOrMediaId: primaryKey, bytes: payloadBytes);
      final primaryFile = loader.getCachedFileSync(primaryKey)!;
      final dupFile = File('${primaryFile.parent.path}/$legacyAliasKey.bin');
      await dupFile.writeAsBytes(payloadBytes);

      expect(dupFile.existsSync(), isTrue);
      final beforeDedupSize = await loader.getCacheSizeBytes();
      expect(beforeDedupSize, equals(4096)); // 2 files on disk = 4 KB

      // Run deduplication pass
      final reclaimed = await loader.deduplicateCache();
      expect(reclaimed, equals(2048));
      expect(dupFile.existsSync(), isFalse); // duplicate deleted

      // Both keys must still resolve to the primary file
      final resolvedPrimary = loader.getCachedFileSync(primaryKey);
      final resolvedAlias = loader.getCachedFileSync('media/covers/hero.jpg');
      expect(resolvedPrimary, isNotNull);
      expect(resolvedAlias, isNotNull);
      expect(resolvedAlias!.path, equals(resolvedPrimary!.path));

      // Cache size is now exactly single-copy
      final afterDedupSize = await loader.getCacheSizeBytes();
      expect(afterDedupSize, equals(2048));
    });
  });
}
