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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: settings.when(
          data: (values) {
            _initialize(values);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        stringsFor(_locale).settings,
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
                      _SectionTitle(label: 'Library'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _librarySource,
                              decoration: const InputDecoration(
                                labelText: 'Library source',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Browse directory',
                            onPressed: _pickLibrarySource,
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Refresh source status',
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
                              : 'No library source configured',
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
                      _SectionTitle(label: 'Reader'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _defaultZoom,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Default zoom',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pageGap,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Page gap',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _profile,
                        decoration: const InputDecoration(
                          labelText: 'Image pipeline profile',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'performance',
                            child: Text('Performance'),
                          ),
                          DropdownMenuItem(
                            value: 'balanced',
                            child: Text('Balanced'),
                          ),
                          DropdownMenuItem(
                            value: 'quality',
                            child: Text('Quality'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _profile = value);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: 'Application'),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<ThemeMode>(
                              initialValue: _themeMode,
                              decoration: const InputDecoration(
                                labelText: 'Theme',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: ThemeMode.light,
                                  child: Text('Light'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.dark,
                                  child: Text('Dark'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.system,
                                  child: Text('System'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _themeMode = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _locale,
                              decoration: const InputDecoration(
                                labelText: 'Language',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                                DropdownMenuItem(
                                  value: 'id',
                                  child: Text('Indonesian'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _locale = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: 'Backup'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _exportBackup,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Export backup'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _importBackup,
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('Import backup'),
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
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
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

  void _initialize(Map<String, String> values) {
    if (_initialized) {
      return;
    }
    _librarySource.text = _decodeString(values['library_source_input'], '');
    _defaultZoom.text = _decodeNumber(values['default_zoom'], '1');
    _pageGap.text = _decodeNumber(values['page_gap'], '10');
    _profile = _decodeString(values['image_pipeline_profile'], 'balanced');
    _themeMode = themeModeFromSetting(
      _decodeString(values['app_theme'], 'light'),
    );
    _locale = _decodeString(values['app_locale'], 'en');
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
      setState(() => _message = 'Settings saved');
    }
  }

  Future<void> _exportBackup() async {
    final location = await getSaveLocation(
      suggestedName: 'comicrd-backup.db',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'SQLite database', extensions: ['db']),
      ],
    );
    if (location == null) {
      return;
    }
    await ref.read(comicRdApiProvider).exportDatabaseBackup(location.path);
    if (mounted) {
      setState(() => _message = 'Backup exported');
    }
  }

  Future<void> _importBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'SQLite database', extensions: ['db']),
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
      setState(() => _message = 'Backup imported');
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
