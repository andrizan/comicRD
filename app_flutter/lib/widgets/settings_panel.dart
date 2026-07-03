import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/api_state.dart';
import '../state/library_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../utils/forui_theme.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  final _librarySource = TextEditingController();
  bool _initialized = false;
  ThemeMode _themeMode = ThemeMode.light;
  String _locale = 'en';
  String? _message;

  @override
  void dispose() {
    _librarySource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsMapProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final text = stringsFor(appSettings.localeCode);
    return FDialog(
      direction: .vertical,
      title: Row(
        children: [
          Text(text.settings),
          const SizedBox(width: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final info = snapshot.data!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'v${info.version}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: settings.when(
          data: (values) {
            _initialize(values, appSettings);
            return ListView(
              shrinkWrap: true,
              children: [
                _sectionHeader(text.librarySection),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: FTextField(
                          control: .managed(controller: _librarySource),
                          hint: text.librarySource,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FTooltip(
                      tipBuilder: (context, _) => Text(text.browseDirectory),
                      child: FButton.icon(
                        variant: .outline,
                        onPress: _pickLibrarySource,
                        child: const Icon(AppIcons.folderOpen),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FTooltip(
                      tipBuilder: (context, _) =>
                          Text(text.refreshSourceStatus),
                      child: FButton.icon(
                        variant: .outline,
                        onPress: () =>
                            ref.invalidate(librarySourceStatusProvider),
                        child: const Icon(AppIcons.refresh),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                sourceStatus.when(
                  data: (status) => Text(
                    status.configured
                        ? status.error ?? status.path
                        : text.noLibrarySource,
                    style: TextStyle(
                      fontSize: 12,
                      color: status.error == null
                          ? context.appMutedText
                          : context.appColors.destructive,
                    ),
                  ),
                  error: (error, _) => Text(
                    error.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.destructive,
                    ),
                  ),
                  loading: () => const FCircularProgress.loader(),
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.readerSection),
                _labeledField(
                  '${text.defaultZoom} (${(readerSettings.zoom * 100).round()}%)',
                  FSlider(
                    control: .managedContinuous(
                      initial: FSliderValue(max: readerSettings.zoom),
                      onChange: (value) => ref
                          .read(readerSettingsProvider.notifier)
                          .setZoom(value.max),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _labeledField(
                  '${text.pageGap} (${readerSettings.pageGap.round()}px)',
                  FSlider(
                    control: .managedContinuous(
                      initial: FSliderValue(max: readerSettings.pageGap / 80),
                      onChange: (value) => ref
                          .read(readerSettingsProvider.notifier)
                          .setPageGap((value.max * 80).clamp(0, 80).toDouble()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FSwitch(
                  label: Text(text.unlimitedScroll),
                  value: readerSettings.unlimitedScroll,
                  onChange: (value) => ref
                      .read(readerSettingsProvider.notifier)
                      .setUnlimitedScroll(value),
                ),
                const SizedBox(height: 8),
                FSwitch(
                  label: Text(text.unlimitedScrollUp),
                  value: readerSettings.unlimitedScrollUp,
                  onChange: readerSettings.unlimitedScroll
                      ? (value) => ref
                            .read(readerSettingsProvider.notifier)
                            .setUnlimitedScrollUp(value)
                      : null,
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.applicationSection),
                Row(
                  children: [
                    Expanded(
                      child: _labeledField(
                        text.theme,
                        FSelect<ThemeMode>(
                          hint: text.theme,
                          items: {
                            text.themeLight: ThemeMode.light,
                            text.themeDark: ThemeMode.dark,
                            text.themeSystem: ThemeMode.system,
                          },
                          control: .managed(
                            initial: _themeMode,
                            onChange: (value) async {
                              if (value != null) {
                                setState(() => _themeMode = value);
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setThemeMode(value);
                                await ref
                                    .read(comicRdApiProvider)
                                    .setSetting(
                                      'app_theme',
                                      jsonEncode(themeModeToSetting(value)),
                                    );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _labeledField(
                        text.locale,
                        FSelect<String>(
                          hint: text.locale,
                          items: {text.english: 'en', text.indonesian: 'id'},
                          control: .managed(
                            initial: _locale,
                            onChange: (value) async {
                              if (value != null) {
                                setState(() => _locale = value);
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setLocale(value);
                                await ref
                                    .read(comicRdApiProvider)
                                    .setSetting(
                                      'app_locale',
                                      jsonEncode(value),
                                    );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.backupSection),
                Row(
                  children: [
                    Expanded(
                      child: FButton(
                        onPress: _exportBackup,
                        prefix: const Icon(AppIcons.download, size: 16),
                        child: Text(text.exportBackup),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FButton(
                        variant: .outline,
                        onPress: _importBackup,
                        prefix: const Icon(AppIcons.upload, size: 16),
                        child: Text(text.importBackup),
                      ),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  FAlert(
                    icon: const Icon(FLucideIcons.check),
                    title: Text(_message!),
                  ),
                ],
              ],
            );
          },
          error: (error, _) => Text(error.toString()),
          loading: () => const Center(child: FCircularProgress.loader()),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: FButton(
                variant: .outline,
                onPress: () => Navigator.of(context).pop(),
                child: Text(text.cancel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FButton(
                onPress: _save,
                prefix: const Icon(AppIcons.save, size: 16),
                child: Text(text.save),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: context.appSubtitleStyle),
    );
  }

  Widget _labeledField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.appCaptionStyle),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  void _initialize(Map<String, String> values, AppSettings appSettings) {
    if (_initialized) return;
    _librarySource.text = _decodeString(values['library_source_input'], '');
    _themeMode = appSettings.themeMode;
    _locale = appSettings.localeCode;
    _initialized = true;
  }

  String _decodeString(String? raw, String fallback) {
    if (raw == null) return fallback;
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : fallback;
  }

  Future<void> _pickLibrarySource() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    setState(() => _librarySource.text = path);
  }

  Future<void> _save() async {
    final api = ref.read(comicRdApiProvider);
    final libraryPath = _librarySource.text.trim();
    await api.setSetting('library_source_input', jsonEncode(libraryPath));
    if (libraryPath.isNotEmpty) {
      await api.addLibrary(libraryPath);
    }
    await api.setSetting(
      'app_theme',
      jsonEncode(themeModeToSetting(_themeMode)),
    );
    await api.setSetting('app_locale', jsonEncode(_locale));
    ref.read(appSettingsProvider.notifier).setThemeMode(_themeMode);
    ref.read(appSettingsProvider.notifier).setLocale(_locale);
    _invalidateDataProviders();
    if (mounted) {
      setState(() => _message = stringsFor(_locale).settingsSaved);
    }
  }

  Future<void> _exportBackup() async {
    final text = stringsFor(_locale);
    final now = DateTime.now();
    final timestamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final location = await getSaveLocation(
      suggestedName: 'comicrd-backup-$timestamp.zip',
      acceptedTypeGroups: [
        XTypeGroup(label: 'ComicRD Backup', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    await ref.read(comicRdApiProvider).exportDatabaseBackup(location.path);
    if (mounted) {
      setState(() => _message = text.backupExported);
    }
  }

  Future<void> _importBackup() async {
    final text = stringsFor(_locale);
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'ComicRD Backup', extensions: ['zip', 'db']),
      ],
    );
    if (file == null) return;
    await ref.read(comicRdApiProvider).importDatabaseBackup(file.path);
    _invalidateDataProviders();
    if (mounted) {
      setState(() => _message = text.backupImported);
    }
  }

  void _invalidateDataProviders() {
    ref.invalidate(settingsEntriesProvider);
    ref.invalidate(settingsMapProvider);
    ref.invalidate(librarySourceStatusProvider);
    ref.invalidate(rawLibraryComicsProvider);
    ref.invalidate(libraryComicsProvider);
    ref.invalidate(comicsWithProgressProvider);
    ref.invalidate(readingHistoryProvider);
    ref.invalidate(allBookmarksProvider);
  }
}
