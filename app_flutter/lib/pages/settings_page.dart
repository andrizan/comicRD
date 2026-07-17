import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/api_state.dart';
import '../state/library_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../utils/forui_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _librarySource = TextEditingController();
  final _librarySourceFocus = FocusNode();
  bool _initialized = false;
  bool _listenersAttached = false;
  String? _message;
  bool _scanning = false;
  String? _scanStatus;
  Timer? _scanPollTimer;
  ProviderSubscription<AsyncValue<Map<String, String>>>? _settingsMapSub;

  @override
  void dispose() {
    _settingsMapSub?.close();
    _librarySource.dispose();
    _librarySourceFocus.dispose();
    _scanPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listenersAttached) return;
    _listenersAttached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachSettingsListeners();
    });
  }

  void _attachSettingsListeners() {
    _settingsMapSub = ref.listenManual<AsyncValue<Map<String, String>>>(
      settingsMapProvider,
      (prev, next) {
        next.whenData((values) {
          if (!_initialized) {
            _librarySource.text = _decodeString(
              values['library_source_input'],
              '',
            );
            _initialized = true;
          }
        });
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsMapProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final text = stringsFor(appSettings.localeCode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 540 ? 16.0 : 48.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            32,
            horizontalPadding,
            48,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pageHeader(text),
              const SizedBox(height: 24),
              Expanded(
                child: settings.when(
                  data: (_) => ListView(
                    children: [
                      _librarySection(text, sourceStatus),
                      const SizedBox(height: 24),
                      _readerSection(text, readerSettings),
                      const SizedBox(height: 24),
                      _applicationSection(text, appSettings),
                      const SizedBox(height: 24),
                      _backupSection(text),
                      const SizedBox(height: 32),
                    ],
                  ),
                  error: (error, _) => _buildError(error),
                  loading: () =>
                      const Center(child: FCircularProgress.loader()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pageHeader(AppStrings text) {
    return Row(
      children: [
        Text(
          text.settings,
          style: const TextStyle(
            fontFamily: appFontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
        const SizedBox(width: 12),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final info = snapshot.data!;
            return Semantics(
              label: 'Version ${info.version}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
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
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _librarySection(
    AppStrings text,
    AsyncValue<dynamic> sourceStatus,
  ) {
    return _settingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: AppIcons.library, title: text.librarySection),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final textField = KeyboardListener(
                    focusNode: _librarySourceFocus,
                    autofocus: false,
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _save();
                      }
                    },
                    child: FTextField(
                      control: .managed(controller: _librarySource),
                      label: Text(text.librarySource),
                    ),
                  );
                  final buttons = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconButton(
                        tooltip: text.browseDirectory,
                        icon: AppIcons.folderOpen,
                        onPress: _pickLibrarySource,
                      ),
                      const SizedBox(width: 8),
                      _iconButton(
                        tooltip: text.save,
                        icon: AppIcons.save,
                        onPress: _save,
                      ),
                      const SizedBox(width: 8),
                      _iconButton(
                        tooltip: text.refreshSourceStatus,
                        icon: AppIcons.refresh,
                        onPress: () =>
                            ref.invalidate(librarySourceStatusProvider),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        textField,
                        const SizedBox(height: 8),
                        buttons,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: textField),
                      const SizedBox(width: 8),
                      buttons,
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                text.librarySourceDescription,
                style: context.appCaptionStyle.copyWith(
                  color: context.appMutedText,
                ),
              ),
              const SizedBox(height: 16),
              _sourceStatus(sourceStatus, text),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  FButton(
                    variant: .outline,
                    onPress: _scanning ? null : _startScan,
                    prefix: _scanning
                        ? const FCircularProgress.loader()
                        : const Icon(AppIcons.refresh, size: 16),
                    child: Text(_scanning ? text.scanning : text.scanLibrary),
                  ),
                  if (_scanStatus != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _scanStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appMutedText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceStatus(AsyncValue<dynamic> sourceStatus, AppStrings text) {
    return sourceStatus.when(
      data: (status) {
        final message = status.configured
            ? (status.error ?? status.path)
            : text.noLibrarySource;
        return Semantics(
          label: message,
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: status.error == null
                  ? context.appMutedText
                  : context.appColors.destructive,
            ),
          ),
        );
      },
      error: (error, _) => Text(
        error.toString(),
        style: TextStyle(
          fontSize: 12,
          color: context.appColors.destructive,
        ),
      ),
      loading: () => const FCircularProgress.loader(),
    );
  }

  Widget _readerSection(AppStrings text, ReaderSettings readerSettings) {
    return _settingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: AppIcons.scroll, title: text.readerSection),
          _settingsField(
            label: '${text.defaultZoom} (${(readerSettings.zoom * 100).round()}%)',
            child: FSlider(
              control: .managedContinuous(
                initial: FSliderValue(max: readerSettings.zoom),
                onChange: (value) => Future(() {
                  ref
                      .read(readerSettingsProvider.notifier)
                      .setZoom(value.max);
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _settingsField(
            label: '${text.pageGap} (${readerSettings.pageGap.round()}px)',
            child: FSlider(
              control: .managedContinuous(
                initial: FSliderValue(max: readerSettings.pageGap / 80),
                onChange: (value) => Future(() {
                  ref
                      .read(readerSettingsProvider.notifier)
                      .setPageGap(
                        (value.max * 80).clamp(0, 80).toDouble(),
                      );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FSwitch(
            label: Text(text.unlimitedScroll),
            value: readerSettings.unlimitedScroll,
            onChange: (value) => ref
                .read(readerSettingsProvider.notifier)
                .setUnlimitedScroll(value),
          ),
          const SizedBox(height: 12),
          FSwitch(
            label: Text(text.unlimitedScrollUp),
            value: readerSettings.unlimitedScrollUp,
            onChange: readerSettings.unlimitedScroll
                ? (value) => ref
                    .read(readerSettingsProvider.notifier)
                    .setUnlimitedScrollUp(value)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _applicationSection(AppStrings text, AppSettings appSettings) {
    return _settingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: AppIcons.settings,
            title: text.applicationSection,
          ),
          _responsiveRow(
            breakpoint: 480,
            children: [
              _settingsField(
                label: text.theme,
                child: FSelect<ThemeMode>.rich(
                  format: (value) => switch (value) {
                    ThemeMode.light => text.themeLight,
                    ThemeMode.dark => text.themeDark,
                    ThemeMode.system => text.themeSystem,
                  },
                  control: .managed(
                    initial: appSettings.themeMode,
                    onChange: (value) async {
                      if (value != null) {
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
                  children: [
                    FSelectItem.item(
                      title: Text(text.themeLight),
                      value: ThemeMode.light,
                      prefix: const Icon(AppIcons.sun, size: 16),
                      suffixBuilder: _activeIndicator,
                    ),
                    FSelectItem.item(
                      title: Text(text.themeDark),
                      value: ThemeMode.dark,
                      prefix: const Icon(AppIcons.moon, size: 16),
                      suffixBuilder: _activeIndicator,
                    ),
                    FSelectItem.item(
                      title: Text(text.themeSystem),
                      value: ThemeMode.system,
                      prefix: const Icon(AppIcons.monitor, size: 16),
                      suffixBuilder: _activeIndicator,
                    ),
                  ],
                ),
              ),
              _settingsField(
                label: text.locale,
                child: FSelect<String>.rich(
                  format: (value) => switch (value) {
                    'en' => text.english,
                    'id' => text.indonesian,
                    _ => value,
                  },
                  control: .managed(
                    initial: appSettings.localeCode,
                    onChange: (value) async {
                      if (value != null) {
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
                  children: [
                    FSelectItem.item(
                      title: Text(text.english),
                      value: 'en',
                      prefix: const Icon(AppIcons.languages, size: 16),
                      suffixBuilder: _activeIndicator,
                    ),
                    FSelectItem.item(
                      title: Text(text.indonesian),
                      value: 'id',
                      prefix: const Icon(AppIcons.languages, size: 16),
                      suffixBuilder: _activeIndicator,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backupSection(AppStrings text) {
    return _settingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: AppIcons.download, title: text.backupSection),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                FButton(
                  onPress: _exportBackup,
                  prefix: const Icon(AppIcons.download, size: 16),
                  child: Text(text.exportBackup),
                ),
                FButton(
                  variant: .outline,
                  onPress: _importBackup,
                  prefix: const Icon(AppIcons.upload, size: 16),
                  child: Text(text.importBackup),
                ),
              ];
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _intersperse(buttons, const SizedBox(height: 8)),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: buttons,
              );
            },
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            FAlert(
              icon: const Icon(FLucideIcons.check),
              title: Text(_message!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _settingsCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.appAccent),
            const SizedBox(width: 8),
            Text(
              title,
              style: context.appBodyStrongStyle.copyWith(
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsField({
    required String label,
    required Widget child,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.appCaptionStyle.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 2),
          Text(
            helper,
            style: context.appCaptionStyle.copyWith(
              color: context.appMutedText,
            ),
          ),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _responsiveRow({
    required double breakpoint,
    required List<Widget> children,
    double spacing = 16,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _intersperse(children, SizedBox(height: spacing)),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _intersperse(
            children.map((child) => Expanded(child: child)).toList(),
            SizedBox(width: spacing),
          ),
        );
      },
    );
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    if (items.isEmpty) return const [];
    final result = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      result.add(separator);
      result.add(items[i]);
    }
    return result;
  }

  Widget? _activeIndicator(BuildContext context, bool selected) {
    return selected
        ? Icon(
            AppIcons.check,
            size: 16,
            color: context.appAccent,
          )
        : null;
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPress,
  }) {
    return FTooltip(
      tipBuilder: (context, _) => Text(tooltip),
      child: FButton.icon(
        variant: .outline,
        onPress: onPress,
        child: Icon(icon),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Text(
        error.toString(),
        style: TextStyle(color: context.appColors.destructive),
      ),
    );
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
    await _save();
  }

  Future<void> _save() async {
    final api = ref.read(comicRdApiProvider);
    final appSettings = ref.read(appSettingsProvider);
    final libraryPath = _librarySource.text.trim();
    await api.setSetting('library_source_input', jsonEncode(libraryPath));
    if (libraryPath.isNotEmpty) {
      await api.addLibrary(libraryPath);
    }
    await api.setSetting(
      'app_theme',
      jsonEncode(themeModeToSetting(appSettings.themeMode)),
    );
    await api.setSetting('app_locale', jsonEncode(appSettings.localeCode));
    _invalidateDataProviders();
    if (mounted) {
      setState(() => _message = stringsFor(appSettings.localeCode).settingsSaved);
    }
  }

  Future<void> _exportBackup() async {
    final text = stringsFor(ref.read(appSettingsProvider).localeCode);
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
    final text = stringsFor(ref.read(appSettingsProvider).localeCode);
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

  Future<void> _startScan() async {
    final api = ref.read(comicRdApiProvider);
    final t = stringsFor(ref.read(appSettingsProvider).localeCode);
    setState(() {
      _scanning = true;
      _scanStatus = null;
    });
    try {
      final started = await api.startScanLibraries();
      if (started) {
        _pollScanStatus();
      } else {
        setState(() {
          _scanning = false;
          _scanStatus = t.scanNoChange;
        });
      }
    } catch (e) {
      setState(() {
        _scanning = false;
        _scanStatus = e.toString();
      });
    }
  }

  void _pollScanStatus() {
    _scanPollTimer?.cancel();
    _scanPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      try {
        final api = ref.read(comicRdApiProvider);
        final t = stringsFor(ref.read(appSettingsProvider).localeCode);
        final status = await api.getLibraryScanStatus();
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (!status.running) {
          timer.cancel();
          final summary = await api.scanLibraries();
          setState(() {
            _scanning = false;
            _scanStatus = t.scanCompleted
                .replaceAll('{comics}', '${summary.comics}')
                .replaceAll('{chapters}', '${summary.chapters}');
          });
          _invalidateDataProviders();
        } else {
          setState(() {
            _scanStatus = '${t.scanProgress}...';
          });
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _scanning = false;
            _scanStatus = e.toString();
          });
        }
      }
    });
  }
}
