import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
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
    return ContentDialog(
      title: Text(text.settings),
      content: settings.when(
        data: (values) {
          _initialize(values, appSettings);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              children: [
                _sectionHeader(text.librarySection),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _librarySource,
                        placeholder: text.librarySource,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: text.browseDirectory,
                      child: IconButton(
                        onPressed: _pickLibrarySource,
                        icon: const Icon(FluentIcons.folder_open),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: text.refreshSourceStatus,
                      child: IconButton(
                        onPressed: () =>
                            ref.invalidate(librarySourceStatusProvider),
                        icon: const Icon(FluentIcons.refresh),
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
                          ? FluentTheme.of(context)
                              .resources
                              .textFillColorSecondary
                          : Colors.red,
                    ),
                  ),
                  error: (error, _) => Text(
                    error.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  loading: () => const ProgressRing(),
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.readerSection),
                Row(
                  children: [
                    Expanded(
                      child: _labeledField(
                        text.defaultZoom,
                        TextBox(
                          controller: _defaultZoom,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          placeholder: text.defaultZoom,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _labeledField(
                        text.pageGap,
                        TextBox(
                          controller: _pageGap,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          placeholder: text.pageGap,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _labeledField(
                  text.imagePipelineProfile,
                  ComboBox<String>(
                    value: _profile,
                    isExpanded: true,
                    items: [
                      ComboBoxItem(
                        value: 'performance',
                        child: Text(text.performance),
                      ),
                      ComboBoxItem(
                        value: 'balanced',
                        child: Text(text.balanced),
                      ),
                      ComboBoxItem(
                        value: 'quality',
                        child: Text(text.quality),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _profile = value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.applicationSection),
                Row(
                  children: [
                    Expanded(
                      child: _labeledField(
                        text.theme,
                        ComboBox<ThemeMode>(
                          value: _themeMode,
                          isExpanded: true,
                          items: [
                            ComboBoxItem(
                              value: ThemeMode.light,
                              child: Row(children: [
                                const Icon(FluentIcons.sunny, size: 16),
                                const SizedBox(width: 8),
                                Text(text.themeLight),
                              ]),
                            ),
                            ComboBoxItem(
                              value: ThemeMode.dark,
                              child: Row(children: [
                                const Icon(FluentIcons.clear_night, size: 16),
                                const SizedBox(width: 8),
                                Text(text.themeDark),
                              ]),
                            ),
                            ComboBoxItem(
                              value: ThemeMode.system,
                              child: Row(children: [
                                const Icon(FluentIcons.screen, size: 16),
                                const SizedBox(width: 8),
                                Text(text.themeSystem),
                              ]),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() => _themeMode = value);
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setThemeMode(value);
                              await ref.read(comicRdApiProvider).setSetting(
                                    'app_theme',
                                    jsonEncode(themeModeToSetting(value)),
                                  );
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _labeledField(
                        text.locale,
                        ComboBox<String>(
                          value: _locale,
                          isExpanded: true,
                          items: [
                            ComboBoxItem(
                              value: 'en',
                              child: Row(children: [
                                const Text('🇺🇸'),
                                const SizedBox(width: 8),
                                Text(text.english),
                              ]),
                            ),
                            ComboBoxItem(
                              value: 'id',
                              child: Row(children: [
                                const Text('🇮🇩'),
                                const SizedBox(width: 8),
                                Text(text.indonesian),
                              ]),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() => _locale = value);
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setLocale(value);
                              await ref.read(comicRdApiProvider).setSetting(
                                    'app_locale',
                                    jsonEncode(value),
                                  );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionHeader(text.backupSection),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _exportBackup,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.download, size: 16),
                          const SizedBox(width: 6),
                          Text(text.exportBackup),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: _importBackup,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.upload, size: 16),
                          const SizedBox(width: 6),
                          Text(text.importBackup),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  InfoBar(
                    title: Text(_message!),
                    severity: InfoBarSeverity.success,
                    isLong: true,
                  ),
                ],
              ],
            ),
          );
        },
        error: (error, _) => Text(error.toString()),
        loading: () => const Center(child: ProgressRing()),
      ),
      actions: [
        Button(
          child: Text(text.cancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          onPressed: _save,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.save, size: 16),
              const SizedBox(width: 6),
              Text(text.save),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: FluentTheme.of(context).typography.subtitle,
      ),
    );
  }

  Widget _labeledField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FluentTheme.of(context).typography.caption),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  void _initialize(Map<String, String> values, AppSettings appSettings) {
    if (_initialized) return;
    _librarySource.text = _decodeString(values['library_source_input'], '');
    _defaultZoom.text = _decodeNumber(values['default_zoom'], '1');
    _pageGap.text = _decodeNumber(values['page_gap'], '10');
    _profile = _decodeString(values['image_pipeline_profile'], 'balanced');
    _themeMode = appSettings.themeMode;
    _locale = appSettings.localeCode;
    _initialized = true;
  }

  String _decodeString(String? raw, String fallback) {
    if (raw == null) return fallback;
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : fallback;
  }

  String _decodeNumber(String? raw, String fallback) {
    if (raw == null) return fallback;
    final decoded = jsonDecode(raw);
    return decoded?.toString() ?? fallback;
  }

  Future<void> _pickLibrarySource() async {
    final path = await getDirectoryPath();
    if (path == null) return;
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
        XTypeGroup(label: text.sqliteDatabase, extensions: ['db']),
      ],
    );
    if (file == null) return;
    await ref.read(comicRdApiProvider).importDatabaseBackup(file.path);
    ref.invalidate(settingsEntriesProvider);
    ref.invalidate(librarySourceStatusProvider);
    ref.invalidate(libraryComicsProvider);
    if (mounted) {
      setState(() => _message = text.backupImported);
    }
  }
}
