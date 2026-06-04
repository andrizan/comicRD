import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.localeCode = 'en',
  });

  final ThemeMode themeMode;
  final String localeCode;

  AppSettings copyWith({ThemeMode? themeMode, String? localeCode}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        localeCode: localeCode ?? this.localeCode,
      );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark,
    );
  }

  void toggleLocale() {
    state = state.copyWith(localeCode: state.localeCode == 'en' ? 'id' : 'en');
  }
}

AppStrings stringsFor(String localeCode) =>
    localeCode == 'id' ? AppStrings.id : AppStrings.en;

class AppStrings {
  const AppStrings({
    required this.home,
    required this.theme,
    required this.locale,
    required this.settings,
    required this.history,
    required this.library,
    required this.bookmarks,
    required this.search,
    required this.emptyLibrary,
    required this.comic,
    required this.reader,
  });

  final String home;
  final String theme;
  final String locale;
  final String settings;
  final String history;
  final String library;
  final String bookmarks;
  final String search;
  final String emptyLibrary;
  final String comic;
  final String reader;

  static const en = AppStrings(
    home: 'Home',
    theme: 'Theme',
    locale: 'Language',
    settings: 'Settings',
    history: 'History',
    library: 'Library',
    bookmarks: 'Bookmarks',
    search: 'Search',
    emptyLibrary: 'No comics found',
    comic: 'Comic',
    reader: 'Reader',
  );

  static const id = AppStrings(
    home: 'Beranda',
    theme: 'Tema',
    locale: 'Bahasa',
    settings: 'Pengaturan',
    history: 'Riwayat',
    library: 'Pustaka',
    bookmarks: 'Bookmark',
    search: 'Cari',
    emptyLibrary: 'Komik tidak ditemukan',
    comic: 'Komik',
    reader: 'Reader',
  );
}
