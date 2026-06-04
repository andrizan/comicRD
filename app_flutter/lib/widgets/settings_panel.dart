import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/api_state.dart';
import '../state/library_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  final _librarySource = TextEditingController();
  final _defaultZoom = TextEditingController(text: '1');
  final _pageGap = TextEditingController(text: '10');
  bool _initialized = false;
  String _profile = 'balanced';
  ThemeMode _themeMode = ThemeMode.light;
  String _locale = 'en';
  String? _message;

  @override
  void dispose() {
    _librarySource.dispose();
    _defaultZoom.dispose();
    _pageGap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsMapProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final text = stringsFor(appSettings.localeCode);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: settings.when(
          data: (values) {
            _initialize(values, appSettings);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        text.settings,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      _SectionTitle(label: text.librarySection),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _librarySource,
                              decoration: InputDecoration(
                                labelText: text.librarySource,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: text.browseDirectory,
                            onPressed: _pickLibrarySource,
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: text.refreshSourceStatus,
                            onPressed: () =>
                                ref.invalidate(librarySourceStatusProvider),
                            icon: const Icon(Icons.refresh_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      sourceStatus.when(
                        data: (status) => Text(
                          status.configured
                              ? status.error ?? status.path
                              : text.noLibrarySource,
                          style: TextStyle(
                            color: status.error == null
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        error: (error, _) => Text(
                          error.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        loading: () => const LinearProgressIndicator(),
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: text.readerSection),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _defaultZoom,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: text.defaultZoom,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pageGap,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: text.pageGap,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _profile,
                        decoration: InputDecoration(
                          labelText: text.imagePipelineProfile,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'performance',
                            child: Text(text.performance),
                          ),
                          DropdownMenuItem(
                            value: 'balanced',
                            child: Text(text.balanced),
                          ),
                          DropdownMenuItem(
                            value: 'quality',
                            child: Text(text.quality),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _profile = value);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: text.applicationSection),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<ThemeMode>(
                              initialValue: _themeMode,
                              decoration: InputDecoration(
                                labelText: text.theme,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: ThemeMode.light,
                                  child: Text(text.themeLight),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.dark,
                                  child: Text(text.themeDark),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.system,
                                  child: Text(text.themeSystem),
                                ),
                              ],
                              onChanged: (value) async {
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _locale,
                              decoration: InputDecoration(
                                labelText: text.locale,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text(text.english),
                                ),
                                DropdownMenuItem(
                                  value: 'id',
                                  child: Text(text.indonesian),
                                ),
                              ],
                              onChanged: (value) async {
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
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: text.backupSection),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _exportBackup,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(text.exportBackup),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _importBackup,
                            icon: const Icon(Icons.upload_outlined),
                            label: Text(text.importBackup),
                          ),
                        ],
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Text(_message!),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(text.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(text.save),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString()),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }

  void _initialize(Map<String, String> values, AppSettings appSettings) {
    if (_initialized) {
      return;
    }
    _librarySource.text = _decodeString(values['library_source_input'], '');
    _defaultZoom.text = _decodeNumber(values['default_zoom'], '1');
    _pageGap.text = _decodeNumber(values['page_gap'], '10');
    _profile = _decodeString(values['image_pipeline_profile'], 'balanced');
    _themeMode = appSettings.themeMode;
    _locale = appSettings.localeCode;
    _initialized = true;
  }

  String _decodeString(String? raw, String fallback) {
    if (raw == null) {
      return fallback;
    }
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : fallback;
  }

  String _decodeNumber(String? raw, String fallback) {
    if (raw == null) {
      return fallback;
    }
    final decoded = jsonDecode(raw);
    return decoded?.toString() ?? fallback;
  }

  Future<void> _pickLibrarySource() async {
    final path = await getDirectoryPath();
    if (path == null) {
      return;
    }
    setState(() => _librarySource.text = path);
  }

  Future<void> _save() async {
    final api = ref.read(comicRdApiProvider);
    await api.setSetting(
      'library_source_input',
      jsonEncode(_librarySource.text.trim()),
    );
    await api.setSetting('default_zoom', _defaultZoom.text.trim());
    await api.setSetting('page_gap', _pageGap.text.trim());
    await api.setSetting('image_pipeline_profile', jsonEncode(_profile));
    await api.setSetting(
      'app_theme',
      jsonEncode(themeModeToSetting(_themeMode)),
    );
    await api.setSetting('app_locale', jsonEncode(_locale));
    ref.read(appSettingsProvider.notifier).setThemeMode(_themeMode);
    ref.read(appSettingsProvider.notifier).setLocale(_locale);
    ref.invalidate(settingsEntriesProvider);
    ref.invalidate(librarySourceStatusProvider);
    ref.invalidate(libraryComicsProvider);
    if (mounted) {
      setState(() => _message = stringsFor(_locale).settingsSaved);
    }
  }

  Future<void> _exportBackup() async {
    final text = stringsFor(_locale);
    final location = await getSaveLocation(
      suggestedName: 'comicrd-backup.db',
      acceptedTypeGroups: [
        XTypeGroup(label: text.sqliteDatabase, extensions: ['db']),
      ],
    );
    if (location == null) {
      return;
    }
    await ref.read(comicRdApiProvider).exportDatabaseBackup(location.path);
    if (mounted) {
      setState(() => _message = text.backupExported);
    }
  }

  Future<void> _importBackup() async {
    final text = stringsFor(_locale);
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: text.sqliteDatabase, extensions: ['db']),
      ],
    );
    if (file == null) {
      return;
    }
    await ref.read(comicRdApiProvider).importDatabaseBackup(file.path);
    ref.invalidate(settingsEntriesProvider);
    ref.invalidate(librarySourceStatusProvider);
    ref.invalidate(libraryComicsProvider);
    if (mounted) {
      setState(() => _message = text.backupImported);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
