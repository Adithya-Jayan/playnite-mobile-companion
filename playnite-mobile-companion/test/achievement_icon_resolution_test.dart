import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Achievement Icon Resolution & Index Alias Mapping Tests', () {
    setUp(() async {
      await PlayniteImageLoader.instance.init();
    });

    test('1. MediaUrlResolver rejects un-resolved Windows cache paths', () {
      expect(
        MediaUrlResolver.getDriveMediaStreamUrl(
            r'icon_cache\76a5e082-74f7-47a4-88d5-bf3addadeef1\original\FIRST_TOOL.jpg'),
        isEmpty,
      );
      expect(
        MediaUrlResolver.getDriveMediaStreamUrl('media/achievements/game-1/ach1.jpg'),
        isEmpty,
      );
      expect(
        MediaUrlResolver.getDriveMediaStreamUrl('1wbxQaNmnCvAcfal58XxtKAOcmJR81doZ'),
        'https://www.googleapis.com/drive/v3/files/1wbxQaNmnCvAcfal58XxtKAOcmJR81doZ?alt=media',
      );
      expect(
        MediaUrlResolver.getDriveMediaStreamUrl('https://example.com/ach.jpg'),
        'https://example.com/ach.jpg',
      );
    });

    test('2. registerRemoteIndex maps relativePath, sha256, and legacy icon_cache to driveFileId', () {
      const testGameId = '76a5e082-74f7-47a4-88d5-bf3addadeef1';
      const testDriveId = '1TEST_DRIVE_ACHIEVEMENT_ID_123';
      const testRelPath = 'media/$testGameId/achievements/FIRST_TOOL.jpg';
      const testSha = 'abcdef1234567890abcdef1234567890';

      final mockIndex = SyncIndex(
        version: '1.0.0',
        generator: 'test',
        generatedAtUtc: DateTime.now().toUtc().toIso8601String(),
        libraryId: 'test-lib',
        totalGames: 1,
        totalEntries: 1,
        totalSizeBytes: 1024,
        entries: {
          testRelPath: const IndexEntry(
            relativePath: testRelPath,
            driveFileId: testDriveId,
            sizeBytes: 1024,
            sha256: testSha,
            modifiedUtc: '2026-11-17T12:00:00Z',
            mimeType: 'image/jpeg',
            category: 'achievement_icon',
            gameId: testGameId,
          ),
        },
      );

      PlayniteImageLoader.instance.registerRemoteIndex(mockIndex);

      // Verify relative path resolves to driveFileId
      final keyRel = PlayniteImageLoader.instance.sanitizeKey(testRelPath);
      expect(PlayniteImageLoader.instance.aliasToPrimaryKey[keyRel], testDriveId);

      // Verify SHA256 resolves to driveFileId
      final keySha = PlayniteImageLoader.instance.sanitizeKey(testSha);
      expect(PlayniteImageLoader.instance.aliasToPrimaryKey[keySha], testDriveId);

      // Verify legacy Windows path resolves to driveFileId
      final legacyPath = 'icon_cache\\$testGameId\\original\\FIRST_TOOL.jpg';
      final keyLegacy = PlayniteImageLoader.instance.sanitizeKey(legacyPath);
      expect(PlayniteImageLoader.instance.aliasToPrimaryKey[keyLegacy], testDriveId);
    });
  });
}
