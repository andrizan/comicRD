import 'package:comicrd_flutter/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stringsFor', () {
    test('returns the Indonesian table for "id"', () {
      expect(stringsFor('id'), same(AppStrings.id));
      expect(stringsFor('id').library, 'Pustaka');
    });

    test('falls back to English for unknown locales', () {
      expect(stringsFor('en'), same(AppStrings.en));
      expect(stringsFor('xx'), same(AppStrings.en));
      expect(stringsFor('en').library, 'Library');
    });
  });

  group('templates', () {
    const placeholders = <String, List<String>>{
      'chaptersCountTemplate': ['{count}'],
      'chaptersReadTemplate': ['{read}', '{total}'],
      'chaptersDoneTemplate': ['{read}', '{total}'],
      'pageOfTemplate': ['{page}', '{total}'],
      'chapterPageTemplate': ['{chapter}', '{page}', '{total}'],
      'pagesCountTemplate': ['{count}'],
      'titlesCountTemplate': ['{count}'],
      'librarySubtitleTemplate': ['{count}'],
      'favoritesSubtitleTemplate': ['{count}'],
      'readingProgressTemplate': ['{percent}', '{read}', '{total}'],
      'scanProgressTemplate': ['{processed}', '{total}'],
      'scanCompleted': ['{comics}', '{chapters}'],
      'pageBookmarkedTemplate': ['{page}'],
      'pageNotBookmarkedTemplate': ['{page}'],
      'chapterBookmarkedTemplate': ['{chapter}'],
      'chapterNotBookmarkedTemplate': ['{chapter}'],
      'inFavoritesTemplate': ['{comic}'],
      'notInFavoritesTemplate': ['{comic}'],
      'optimizeFreedSpace': ['{size}'],
    };

    Map<String, String> templates(AppStrings t) => {
      'chaptersCountTemplate': t.chaptersCountTemplate,
      'chaptersReadTemplate': t.chaptersReadTemplate,
      'chaptersDoneTemplate': t.chaptersDoneTemplate,
      'pageOfTemplate': t.pageOfTemplate,
      'chapterPageTemplate': t.chapterPageTemplate,
      'pagesCountTemplate': t.pagesCountTemplate,
      'titlesCountTemplate': t.titlesCountTemplate,
      'librarySubtitleTemplate': t.librarySubtitleTemplate,
      'favoritesSubtitleTemplate': t.favoritesSubtitleTemplate,
      'readingProgressTemplate': t.readingProgressTemplate,
      'scanProgressTemplate': t.scanProgressTemplate,
      'scanCompleted': t.scanCompleted,
      'pageBookmarkedTemplate': t.pageBookmarkedTemplate,
      'pageNotBookmarkedTemplate': t.pageNotBookmarkedTemplate,
      'chapterBookmarkedTemplate': t.chapterBookmarkedTemplate,
      'chapterNotBookmarkedTemplate': t.chapterNotBookmarkedTemplate,
      'inFavoritesTemplate': t.inFavoritesTemplate,
      'notInFavoritesTemplate': t.notInFavoritesTemplate,
      'optimizeFreedSpace': t.optimizeFreedSpace,
    };

    for (final locale in ['en', 'id']) {
      test('$locale templates keep every placeholder', () {
        final values = templates(stringsFor(locale));
        for (final entry in placeholders.entries) {
          final template = values[entry.key]!;
          for (final placeholder in entry.value) {
            expect(
              template,
              contains(placeholder),
              reason: '$locale.${entry.key} must contain $placeholder',
            );
          }
        }
      });
    }
  });

  group('locale tables', () {
    // The copy both tests and the reader chrome match on; a translation
    // drift here would silently change what users (and finders) see.
    test('keeps the labels the UI tests look up', () {
      final en = AppStrings.en;
      expect(en.addFavorite, 'Add Favorite');
      expect(en.removeFavorite, 'Remove Favorite');
      expect(en.librarySubtitleTemplate, '{count} Titles Saved');
      expect(en.nextPage, 'Next Page');
      expect(en.markPanel, 'Mark');
      expect(en.displayPanel, 'Display');
      expect(en.welcomeTitle, 'Read comics from a folder on your computer.');
      expect(en.keyFirstPage, isNotEmpty);
    });

    test('Indonesian labels differ from English for the main navigation', () {
      final en = AppStrings.en;
      final id = AppStrings.id;
      expect(id.library, isNot(en.library));
      expect(id.history, isNot(en.history));
      expect(id.favorites, isNot(en.favorites));
      expect(id.settings, isNot(en.settings));
      expect(id.markPanel, isNot(en.markPanel));
      expect(id.displayPanel, isNot(en.displayPanel));
    });
  });
}
