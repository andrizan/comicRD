import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../state/update_state.dart';
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
  double _scanProgress = 0.0;
  String? _scanCurrentPath;
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
                      const SizedBox(height: 28),
                      _readerSection(text, readerSettings),
                      const SizedBox(height: 28),
                      _applicationSection(text, appSettings),
                      const SizedBox(height: 28),
                      _updateSection(text),
                      const SizedBox(height: 28),
                      _backupSection(text),
                      const SizedBox(height: 28),
                      _aboutSection(text),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
        ),
        const SizedBox(height: 6),
        Text(
          text.settingsDescription,
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 13,
            color: context.appMutedText,
          ),
        ),
      ],
    );
  }

  // --- SECTIONS ---

  Widget _librarySection(AppStrings text, AsyncValue<dynamic> sourceStatus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.librarySection),
        _SettingsCard(
          child: _SettingsRow(
            title: text.librarySource,
            description: text.librarySourceDescription,
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconButton(
                  tooltip: text.browseDirectory,
                  icon: AppIcons.folderOpen,
                  onPress: _pickLibrarySource,
                ),
                const SizedBox(width: 4),
                _iconButton(
                  tooltip: text.save,
                  icon: AppIcons.save,
                  onPress: _save,
                ),
                const SizedBox(width: 4),
                _iconButton(
                  tooltip: text.refreshSourceStatus,
                  icon: AppIcons.refresh,
                  onPress: () => ref.invalidate(librarySourceStatusProvider),
                ),
              ],
            ),
            below: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  KeyboardListener(
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
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sourceStatus(sourceStatus, text),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.scanLibrary,
            description: text.scanLibraryDescription,
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_scanning) ...[
                  FButton(
                    variant: .outline,
                    onPress: _cancelScan,
                    child: Text(text.cancelScan),
                  ),
                  const SizedBox(width: 8),
                ],
                FButton(
                  variant: .outline,
                  onPress: _scanning ? null : _startScan,
                  prefix: _scanning
                      ? const FCircularProgress.loader()
                      : const Icon(AppIcons.refresh, size: 16),
                  child: Text(_scanning ? text.scanning : text.scanLibrary),
                ),
              ],
            ),
            below: _scanSectionBelow(text),
          ),
        ),
      ],
    );
  }

  Widget? _scanSectionBelow(AppStrings text) {
    if (_scanning) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scanCurrentPath != null) ...[
              LinearProgressIndicator(
                value: _scanProgress > 0 ? _scanProgress : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
            ],
            if (_scanStatus != null)
              Text(
                _scanStatus!,
                style: TextStyle(fontSize: 12, color: context.appMutedText),
              ),
          ],
        ),
      );
    }
    if (_scanStatus != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          _scanStatus!,
          style: TextStyle(fontSize: 12, color: context.appMutedText),
        ),
      );
    }
    return null;
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
        style: TextStyle(fontSize: 12, color: context.appColors.destructive),
      ),
      loading: () => const FCircularProgress.loader(),
    );
  }

  Widget _readerSection(AppStrings text, ReaderSettings readerSettings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.readerSection),
        _SettingsCard(
          child: _SettingsRow(
            title: text.defaultZoom,
            description:
                '${text.defaultZoomDescription} (${(readerSettings.zoom * 100).round()}%)',
            control: SizedBox(
              width: 240,
              child: FSlider(
                control: .managedContinuous(
                  initial: FSliderValue(
                    max: (readerSettings.zoom - 0.2) / 1.3,
                  ),
                  onChange: (value) => Future(() {
                    ref
                        .read(readerSettingsProvider.notifier)
                        .setZoom(0.2 + value.max * 1.3);
                  }),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.pageGap,
            description:
                '${text.pageGapDescription} (${readerSettings.pageGap.round()}px)',
            control: SizedBox(
              width: 240,
              child: FSlider(
                control: .managedContinuous(
                  initial: FSliderValue(max: readerSettings.pageGap / 80),
                  onChange: (value) => Future(() {
                    ref
                        .read(readerSettingsProvider.notifier)
                        .setPageGap((value.max * 80).clamp(0, 80).toDouble());
                  }),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.unlimitedScroll,
            description: text.unlimitedScrollDescription,
            control: FSwitch(
              value: readerSettings.unlimitedScroll,
              onChange: (value) => ref
                  .read(readerSettingsProvider.notifier)
                  .setUnlimitedScroll(value),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.unlimitedScrollUp,
            description: text.unlimitedScrollUpDescription,
            control: FSwitch(
              value: readerSettings.unlimitedScrollUp,
              onChange: readerSettings.unlimitedScroll
                  ? (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .setUnlimitedScrollUp(value)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _applicationSection(AppStrings text, AppSettings appSettings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.applicationSection),
        _SettingsCard(
          child: _SettingsRow(
            title: text.theme,
            description: text.themeDescription,
            control: SizedBox(
              width: 220,
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
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting(
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
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.locale,
            description: text.localeDescription,
            control: SizedBox(
              width: 220,
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
                      ref.read(appSettingsProvider.notifier).setLocale(value);
                      await ref
                          .read(comicRdApiProvider)
                          .setSetting('app_locale', jsonEncode(value));
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
          ),
        ),
      ],
    );
  }

  Widget _updateSection(AppStrings text) {
    final updateState = ref.watch(updateProvider);
    final isAvailable = updateState.status == UpdateStatus.available;
    final isChecking = updateState.status == UpdateStatus.checking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.updateSection),
        _SettingsCard(
          child: _SettingsRow(
            title: _updateCardTitle(updateState, text),
            description: _updateCardDescription(updateState, text),
            control: isChecking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: FCircularProgress.loader(),
                  )
                : FButton(
                    variant: .outline,
                    onPress: () =>
                        ref.read(updateProvider.notifier).checkForUpdates(),
                    prefix: const Icon(AppIcons.refresh, size: 16),
                    child: Text(text.checkForUpdates),
                  ),
            below: isAvailable
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (updateState.info!.releaseNotes.isNotEmpty) ...[
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.appColors.muted.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                updateState.info!.releaseNotes,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appColors.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FButton(
                              onPress: () => _openReleasePage(
                                updateState.info!.releaseUrl,
                              ),
                              prefix: const Icon(AppIcons.download, size: 16),
                              child: Text(text.downloadUpdate),
                            ),
                            FButton(
                              variant: .outline,
                              onPress: () => _openReleasePage(
                                updateState.info!.releaseUrl,
                              ),
                              child: Text(text.viewRelease),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  String _updateCardTitle(UpdateState updateState, AppStrings text) {
    return switch (updateState.status) {
      UpdateStatus.idle => text.updateSection,
      UpdateStatus.checking => text.checkingForUpdates,
      UpdateStatus.upToDate => text.appUpToDate,
      UpdateStatus.error => text.updateCheckFailed,
      UpdateStatus.available =>
        '${text.updateAvailable}: v${updateState.info!.latestVersion}',
    };
  }

  String? _updateCardDescription(UpdateState updateState, AppStrings text) {
    return switch (updateState.status) {
      UpdateStatus.idle => text.checkForUpdates,
      UpdateStatus.checking => null,
      UpdateStatus.upToDate => null,
      UpdateStatus.error => null,
      UpdateStatus.available => text.viewRelease,
    };
  }

  void _openReleasePage(String url) {
    if (url.isEmpty) return;
    Process.run('xdg-open', [url]).catchError((_) {
      return Process.run('open', [url]).catchError((_) {
        return Process.run('cmd', ['/c', 'start', url]).catchError((_) {
          return ProcessResult(0, 0, '', '');
        });
      });
    });
  }

  Widget _backupSection(AppStrings text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.backupSection),
        _SettingsCard(
          child: _SettingsRow(
            title: text.exportBackup,
            description: text.exportBackupDescription,
            control: FButton(
              onPress: _exportBackup,
              prefix: const Icon(AppIcons.download, size: 16),
              child: Text(text.exportBackup),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          child: _SettingsRow(
            title: text.importBackup,
            description: text.importBackupDescription,
            control: FButton(
              variant: .outline,
              onPress: _importBackup,
              prefix: const Icon(AppIcons.upload, size: 16),
              child: Text(text.importBackup),
            ),
            below: _message != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FAlert(
                      icon: const Icon(FLucideIcons.check),
                      title: Text(_message!),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _aboutSection(AppStrings text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text.aboutSection),
        _SettingsCard(
          child: _SettingsRow(
            title: text.appName,
            description: text.aboutDescription,
            control: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version;
                return Text(
                  version != null ? 'v$version' : '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.mutedForeground,
                  ),
                );
              },
            ),
            below: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FButton(
                variant: .outline,
                onPress: () =>
                    _openReleasePage('https://github.com/andrizan/comicRD'),
                prefix: const Icon(AppIcons.code, size: 16),
                child: Text(text.viewOnGithub),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- HELPERS ---

  Widget _activeIndicator(BuildContext context, bool selected) {
    return selected
        ? Icon(AppIcons.check, size: 16, color: context.appAccent)
        : const SizedBox.shrink();
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
      setState(
        () => _message = stringsFor(appSettings.localeCode).settingsSaved,
      );
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
    ref.invalidate(allFavoritesProvider);
  }

  Future<void> _startScan() async {
    final api = ref.read(comicRdApiProvider);
    final text = stringsFor(ref.read(appSettingsProvider).localeCode);
    setState(() {
      _scanning = true;
      _scanStatus = null;
      _scanProgress = 0.0;
      _scanCurrentPath = null;
    });
    try {
      final started = await api.startScanLibraries();
      if (started) {
        _pollScanStatus();
      } else {
        setState(() {
          _scanning = false;
          _scanStatus = text.scanNoChange;
        });
      }
    } catch (e) {
      setState(() {
        _scanning = false;
        _scanStatus = e.toString();
      });
    }
  }

  Future<void> _cancelScan() async {
    try {
      await ref.read(comicRdApiProvider).cancelScanLibraries();
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanStatus = e.toString();
        });
      }
    }
  }

  void _pollScanStatus() {
    _scanPollTimer?.cancel();
    _scanPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      try {
        final api = ref.read(comicRdApiProvider);
        final text = stringsFor(ref.read(appSettingsProvider).localeCode);
        final status = await api.getLibraryScanStatus();
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (!status.running) {
          timer.cancel();
          final summary = status.lastSummary;
          setState(() {
            _scanning = false;
            _scanProgress = 0.0;
            _scanCurrentPath = null;
            if (summary != null) {
              _scanStatus = text.scanCompleted
                  .replaceAll('{comics}', '${summary.comics}')
                  .replaceAll('{chapters}', '${summary.chapters}');
            } else {
              _scanStatus ??= text.scanNoChange;
            }
          });
          _invalidateDataProviders();
        } else {
          final progress = status.progress;
          setState(() {
            if (progress != null && progress.total > 0) {
              _scanProgress = progress.processed / progress.total;
              _scanCurrentPath = progress.currentPath.isNotEmpty
                  ? progress.currentPath
                  : null;
              _scanStatus =
                  '${text.scanProgress}: ${progress.processed} / ${progress.total}';
            } else {
              _scanProgress = 0.0;
              _scanCurrentPath = null;
              _scanStatus = '${text.scanProgress}...';
            }
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

// --- Win 11 style widgets ---

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: appFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.appAccent,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.description,
    required this.control,
    this.below,
  });

  static const double _narrowBreakpoint = 520;

  final String title;
  final String? description;
  final Widget control;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _narrowBreakpoint;
            final labelColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: appFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: TextStyle(fontSize: 12, color: context.appMutedText),
                  ),
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        labelColumn,
                        const SizedBox(height: 10),
                        control,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: labelColumn),
                        const SizedBox(width: 16),
                        control,
                      ],
                    ),
            );
          },
        ),
        if (below != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: below!,
          ),
      ],
    );
  }
}
