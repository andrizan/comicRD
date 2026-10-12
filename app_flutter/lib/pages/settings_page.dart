import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/api_state.dart';
import '../state/library_source_actions.dart';
import '../state/library_state.dart';
import '../state/settings_data_state.dart';
import '../state/settings_state.dart';
import '../state/update_state.dart';
import '../utils/format_size.dart';
import '../utils/forui_theme.dart';
import '../widgets/soft_ui.dart';

enum _SettingsSection { library, reader, appearance, data, about }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _librarySource = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = {
    for (final section in _SettingsSection.values) section: GlobalKey(),
  };
  _SettingsSection _activeSection = _SettingsSection.library;
  bool _initialized = false;
  bool _listenersAttached = false;
  String? _message;
  bool _scanning = false;
  String? _scanStatus;
  double _scanProgress = 0.0;
  String? _scanCurrentPath;
  int _scanProcessed = 0;
  int _scanTotal = 0;
  Timer? _scanPollTimer;
  ProviderSubscription<AsyncValue<Map<String, String>>>? _settingsMapSub;
  bool _optimizingData = false;
  List<String> _optimizeLines = const [];
  String? _optimizeError;
  int? _dbSizeBytes;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncActiveSection);
  }

  @override
  void dispose() {
    _settingsMapSub?.close();
    _librarySource.dispose();
    _scroll.dispose();
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
    _loadDatabaseSize();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsMapProvider);
    final sourceStatus = ref.watch(librarySourceStatusProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final libraryCount = ref.watch(libraryCountProvider);
    final text = stringsFor(appSettings.localeCode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final showNav = constraints.maxWidth >= 1000;
        final padLeft = narrow ? 16.0 : 24.0;
        final padRight = narrow ? 16.0 : 40.0;
        final sections = <Widget>[
          _section(
            _SettingsSection.library,
            text.librarySection,
            _libraryCard(text, sourceStatus, libraryCount),
          ),
          _section(
            _SettingsSection.reader,
            text.readerSection,
            _readerCard(text, readerSettings),
          ),
          _section(
            _SettingsSection.appearance,
            text.appearanceSection,
            _appearanceCard(text, appSettings),
          ),
          _section(_SettingsSection.data, text.dataSection, _dataCard(text)),
          _section(
            _SettingsSection.about,
            text.updateAboutSection,
            _aboutCard(text),
          ),
        ];
        final content = settings.when(
          data: (_) => ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 64),
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const SizedBox(height: 32),
                sections[i],
              ],
            ],
          ),
          error: (error, _) =>
              SoftEmptyState(message: error.toString(), isError: true),
          loading: () => const Center(child: FCircularProgress.loader()),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(padLeft, 28, padRight, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PageHeading(
                      title: text.settings,
                      subtitle: Text(text.settingsDescription),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const _VersionPill(),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: showNav
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 220,
                            child: _SectionNav(
                              text: text,
                              active: _activeSection,
                              onSelect: _scrollToSection,
                            ),
                          ),
                          const SizedBox(width: 40),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 780,
                                ),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      )
                    : content,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(_SettingsSection section, String title, Widget card) {
    return Column(
      key: _sectionKeys[section],
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(header: true, child: SectionHeading(title: title)),
        const SizedBox(height: 12),
        card,
      ],
    );
  }

  void _scrollToSection(_SettingsSection section) {
    setState(() => _activeSection = section);
    final context = _sectionKeys[section]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Highlights the section whose top is closest above the viewport.
  void _syncActiveSection() {
    if (!_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    _SettingsSection? best;
    var bestDistance = double.infinity;
    for (final entry in _sectionKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final listTop =
          (_scroll.position.context.storageContext.findRenderObject()
                  as RenderBox?)
              ?.localToGlobal(Offset.zero)
              .dy;
      if (listTop == null) return;
      final distance = (top - listTop - viewport * 0.25).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.key;
      }
    }
    if (best != null && best != _activeSection) {
      setState(() => _activeSection = best!);
    }
  }

  // --- Library ---

  Widget _libraryCard(
    AppStrings text,
    AsyncValue<dynamic> sourceStatus,
    int libraryCount,
  ) {
    final colors = context.theme.colors;
    return SettingsCard(
      children: [
        SettingsRow(
          title: text.librarySource,
          description: text.librarySourceDescription,
          control: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SoftButton(
                label: text.changeFolder,
                icon: AppIcons.folderOpen,
                variant: SoftButtonVariant.soft,
                onPressed: _pickLibrarySource,
              ),
              SoftIconButton(
                icon: AppIcons.refresh,
                tooltip: text.refreshSourceStatus,
                onPressed: () => ref.invalidate(librarySourceStatusProvider),
              ),
            ],
          ),
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PathField(
                controller: _librarySource,
                hint: text.directoryPath,
                saveTooltip: text.save,
                onSubmit: _save,
              ),
              const SizedBox(height: 10),
              _sourceStatusLine(sourceStatus, text, libraryCount),
            ],
          ),
        ),
        SettingsRow(
          title: text.scanLibrary,
          description: text.scanLibraryDescription,
          control: _scanning
              ? SoftButton(
                  label: text.cancel,
                  variant: SoftButtonVariant.text,
                  onPressed: _cancelScan,
                )
              : SoftButton(
                  label: text.scanLibrary,
                  icon: AppIcons.refresh,
                  variant: SoftButtonVariant.soft,
                  onPressed: _startScan,
                ),
          below: _scanning
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _scanTotal > 0
                          ? text.scanProgressTemplate
                                .replaceAll('{processed}', '$_scanProcessed')
                                .replaceAll('{total}', '$_scanTotal')
                          : text.scanning,
                      style: TextStyle(
                        fontSize: 13,
                        height: 20 / 13,
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SoftProgressBar(
                      value: _scanProgress,
                      height: 8,
                      semanticLabel: text.scanProgress,
                    ),
                    if (_scanCurrentPath != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _scanCurrentPath!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 18 / 12,
                          fontWeight: FontWeight.w500,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                )
              : _scanStatus != null
              ? _StatusLine(label: _scanStatus!, tone: _StatusTone.muted)
              : null,
        ),
      ],
    );
  }

  Widget _sourceStatusLine(
    AsyncValue<dynamic> sourceStatus,
    AppStrings text,
    int libraryCount,
  ) {
    return sourceStatus.when(
      data: (status) {
        if (!status.configured) {
          return _StatusLine(
            label: text.notConfigured,
            tone: _StatusTone.muted,
            dot: true,
          );
        }
        if (status.error != null) {
          return _StatusLine(
            label: status.error!,
            tone: _StatusTone.error,
            dot: true,
          );
        }
        final titles = text.titlesCountTemplate.replaceAll(
          '{count}',
          '$libraryCount',
        );
        return _StatusLine(
          label: '${text.connected} · $titles',
          tone: _StatusTone.success,
          dot: true,
        );
      },
      error: (error, _) =>
          _StatusLine(label: error.toString(), tone: _StatusTone.error),
      loading: () => const SizedBox(height: 18),
    );
  }

  // --- Reader ---

  Widget _readerCard(AppStrings text, ReaderSettings readerSettings) {
    final notifier = ref.read(readerSettingsProvider.notifier);
    return SettingsCard(
      children: [
        SettingsRow(
          title: text.defaultZoom,
          description: text.defaultZoomDescription,
          controlWidth: 340,
          control: _SliderControl(
            valueLabel: '${(readerSettings.zoom * 100).round()}%',
            slider: SoftSlider(
              value: readerSettings.zoom,
              min: 0.2,
              max: 1.5,
              divisions: 26,
              semanticLabel:
                  '${text.defaultZoom} ${(readerSettings.zoom * 100).round()}%',
              onChanged: (value) => notifier.setZoom((value * 20).round() / 20),
            ),
          ),
        ),
        SettingsRow(
          title: text.pageGap,
          description: text.pageGapDescription,
          controlWidth: 340,
          control: _SliderControl(
            valueLabel: '${readerSettings.pageGap.round()} px',
            slider: SoftSlider(
              value: readerSettings.pageGap,
              min: 0,
              max: 80,
              divisions: 16,
              semanticLabel:
                  '${text.pageGap} ${readerSettings.pageGap.round()} px',
              onChanged: (value) =>
                  notifier.setPageGap(((value / 5).round() * 5).toDouble()),
            ),
          ),
        ),
        SettingsRow(
          title: text.unlimitedScroll,
          description: text.unlimitedScrollDescription,
          control: SoftSwitch(
            value: readerSettings.unlimitedScroll,
            semanticLabel: text.unlimitedScroll,
            onChanged: notifier.setUnlimitedScroll,
          ),
        ),
        SettingsRow(
          title: text.unlimitedScrollUp,
          description: text.unlimitedScrollUpDescription,
          control: SoftSwitch(
            value: readerSettings.unlimitedScrollUp,
            semanticLabel: text.unlimitedScrollUp,
            onChanged: readerSettings.unlimitedScroll
                ? notifier.setUnlimitedScrollUp
                : null,
          ),
        ),
        SettingsRow(
          title: text.forcePortrait,
          description: text.forcePortraitDescription,
          control: SoftSwitch(
            value: readerSettings.forcePortrait,
            semanticLabel: text.forcePortrait,
            onChanged: notifier.setForcePortrait,
          ),
        ),
      ],
    );
  }

  // --- Appearance ---

  Widget _appearanceCard(AppStrings text, AppSettings appSettings) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: text.theme,
          description: text.themeDescription,
          control: SoftSegmented<ThemeMode>(
            value: appSettings.themeMode,
            onChanged: _setThemeMode,
            segments: [
              SoftSegment(
                value: ThemeMode.system,
                label: text.themeSystem,
                icon: AppIcons.monitor,
              ),
              SoftSegment(
                value: ThemeMode.light,
                label: text.themeLight,
                icon: AppIcons.sun,
              ),
              SoftSegment(
                value: ThemeMode.dark,
                label: text.themeDark,
                icon: AppIcons.moon,
              ),
            ],
          ),
        ),
        SettingsRow(
          title: text.locale,
          description: text.localeDescription,
          control: SoftSegmented<String>(
            value: appSettings.localeCode,
            onChanged: _setLocale,
            segments: [
              SoftSegment(value: 'id', label: text.indonesian),
              SoftSegment(value: 'en', label: text.english),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    ref.read(appSettingsProvider.notifier).setThemeMode(mode);
    await ref
        .read(comicRdApiProvider)
        .setSetting('app_theme', jsonEncode(themeModeToSetting(mode)));
  }

  Future<void> _setLocale(String locale) async {
    ref.read(appSettingsProvider.notifier).setLocale(locale);
    await ref
        .read(comicRdApiProvider)
        .setSetting('app_locale', jsonEncode(locale));
  }

  // --- Data & backup ---

  Widget _dataCard(AppStrings text) {
    final dbSize = _dbSizeBytes;
    final optimizeDescription = dbSize == null
        ? text.optimizeDataDescription
        : '${text.optimizeDataDescription} · ${text.databaseSize} ${formatBytes(dbSize)}';
    return SettingsCard(
      children: [
        SettingsRow(
          title: text.exportBackup,
          description: text.exportBackupDescription,
          control: SoftButton(
            label: text.exportAction,
            icon: AppIcons.download,
            variant: SoftButtonVariant.soft,
            onPressed: _exportBackup,
          ),
          below: _message == text.backupExported
              ? _StatusLine(label: _message!, tone: _StatusTone.success)
              : null,
        ),
        SettingsRow(
          title: text.importBackup,
          description: text.importBackupDescription,
          control: SoftButton(
            label: text.importAction,
            icon: AppIcons.upload,
            variant: SoftButtonVariant.soft,
            onPressed: _importBackup,
          ),
          below: _message == text.backupImported
              ? _StatusLine(label: _message!, tone: _StatusTone.success)
              : null,
        ),
        SettingsRow(
          title: text.optimizeData,
          description: optimizeDescription,
          control: _optimizingData
              ? const SizedBox(
                  width: AppShape.controlHeight,
                  height: AppShape.controlHeight,
                  child: Center(child: FCircularProgress.loader()),
                )
              : SoftButton(
                  label: text.optimizeAction,
                  icon: AppIcons.database,
                  variant: SoftButtonVariant.soft,
                  onPressed: _runOptimize,
                ),
          below: _optimizeBelow(text),
        ),
      ],
    );
  }

  Widget? _optimizeBelow(AppStrings text) {
    if (_optimizeError != null) {
      return _StatusLine(label: _optimizeError!, tone: _StatusTone.error);
    }
    if (_optimizeLines.isEmpty) return null;
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusLine(
          label: text.optimizeDataCompleted,
          tone: _StatusTone.success,
        ),
        const SizedBox(height: 4),
        for (final line in _optimizeLines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 12.5,
                height: 18 / 12.5,
                fontWeight: FontWeight.w500,
                color: colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadDatabaseSize() async {
    try {
      final size = await ref.read(comicRdApiProvider).databaseSizeBytes();
      if (mounted) {
        setState(() => _dbSizeBytes = size);
      }
    } catch (_) {
      // Keep the size hidden if the query fails.
    }
  }

  Future<void> _runOptimize() async {
    final text = stringsFor(ref.read(appSettingsProvider).localeCode);
    setState(() {
      _optimizingData = true;
      _optimizeError = null;
      _optimizeLines = const [];
    });
    try {
      final result = await ref.read(comicRdApiProvider).optimizeDatabase();
      if (!mounted) return;
      invalidateLibraryData(ref);
      final freed = result.databaseSizeBefore - result.databaseSizeAfter;
      final lines = <String>[
        text.optimizeRemovedComics.replaceAll(
          '{count}',
          '${result.removedComics}',
        ),
        text.optimizeRemovedChapters.replaceAll(
          '{count}',
          '${result.removedChapters}',
        ),
        text.optimizeRemovedBookmarks.replaceAll(
          '{count}',
          '${result.removedChapterBookmarks + result.removedPageBookmarks}',
        ),
        text.optimizeRemovedFavorites.replaceAll(
          '{count}',
          '${result.removedFavorites}',
        ),
        text.optimizeRemovedThumbnails.replaceAll(
          '{count}',
          '${result.removedThumbnails}',
        ),
        text.optimizeFreedSpace.replaceAll(
          '{size}',
          formatBytes((freed > 0 ? freed : 0) + result.removedThumbnailBytes),
        ),
      ];
      if (result.skippedLibraryCount > 0) {
        lines.add(
          text.optimizeSkippedLibraries.replaceAll(
            '{count}',
            '${result.skippedLibraryCount}',
          ),
        );
      }
      setState(() {
        _optimizingData = false;
        _optimizeLines = lines;
        _dbSizeBytes = result.databaseSizeAfter;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optimizingData = false;
        _optimizeError = '$e';
      });
    }
  }

  // --- Update & about ---

  Widget _aboutCard(AppStrings text) {
    final updateState = ref.watch(updateProvider);
    final isAvailable = updateState.status == UpdateStatus.available;
    final isChecking = updateState.status == UpdateStatus.checking;
    final colors = context.theme.colors;
    final (
      String? statusLabel,
      _StatusTone tone,
    ) = switch (updateState.status) {
      UpdateStatus.idle => (null, _StatusTone.muted),
      UpdateStatus.checking => (text.checkingForUpdates, _StatusTone.muted),
      UpdateStatus.upToDate => (text.appUpToDate, _StatusTone.success),
      UpdateStatus.error => (text.updateCheckFailed, _StatusTone.error),
      UpdateStatus.available => (
        '${text.updateAvailable}: v${updateState.info!.latestVersion}',
        _StatusTone.accent,
      ),
    };
    return SettingsCard(
      children: [
        SettingsRow(
          title: text.appName,
          descriptionWidget: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version;
              final line = statusLabel ?? (version != null ? 'v$version' : '');
              return _StatusLine(
                label: version != null && statusLabel != null
                    ? 'v$version · $line'
                    : line,
                tone: tone,
                icon: tone == _StatusTone.success ? AppIcons.check : null,
              );
            },
          ),
          control: isChecking
              ? const SizedBox(
                  width: AppShape.controlHeight,
                  height: AppShape.controlHeight,
                  child: Center(child: FCircularProgress.loader()),
                )
              : SoftButton(
                  label: text.checkForUpdates,
                  variant: SoftButtonVariant.soft,
                  onPressed: () =>
                      ref.read(updateProvider.notifier).checkForUpdates(),
                ),
          below: isAvailable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (updateState.info!.releaseNotes.isNotEmpty) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 140),
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.muted,
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusControl,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            updateState.info!.releaseNotes,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 18 / 12.5,
                              fontWeight: FontWeight.w500,
                              color: colors.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SoftButton(
                          label: text.downloadUpdate,
                          icon: AppIcons.download,
                          variant: SoftButtonVariant.primary,
                          onPressed: () =>
                              _openReleasePage(updateState.info!.releaseUrl),
                        ),
                        SoftButton(
                          label: text.viewRelease,
                          icon: AppIcons.externalLink,
                          onPressed: () =>
                              _openReleasePage(updateState.info!.releaseUrl),
                        ),
                      ],
                    ),
                  ],
                )
              : null,
        ),
        SettingsRow(
          title: text.aboutSection,
          description: text.aboutDescription,
          control: SoftButton(
            label: text.viewOnGithub,
            icon: AppIcons.code,
            variant: SoftButtonVariant.text,
            onPressed: () =>
                _openReleasePage('https://github.com/andrizan/comicRD'),
          ),
        ),
      ],
    );
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

  // --- Actions ---

  String _decodeString(String? raw, String fallback) {
    if (raw == null) return fallback;
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : fallback;
  }

  Future<void> _pickLibrarySource() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    setState(() => _librarySource.text = path);
    await _save();
  }

  Future<void> _save() async {
    final appSettings = ref.read(appSettingsProvider);
    await applyLibrarySource(ref, _librarySource.text);
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
    if (!mounted) return;
    invalidateLibraryData(ref);
    setState(() => _message = text.backupImported);
  }

  Future<void> _startScan() async {
    final api = ref.read(comicRdApiProvider);
    final text = stringsFor(ref.read(appSettingsProvider).localeCode);
    setState(() {
      _scanning = true;
      _scanStatus = null;
      _scanProgress = 0.0;
      _scanCurrentPath = null;
      _scanProcessed = 0;
      _scanTotal = 0;
    });
    try {
      final started = await api.startScanLibraries();
      if (!mounted) return;
      if (started) {
        _pollScanStatus();
      } else {
        setState(() {
          _scanning = false;
          _scanStatus = text.scanNoChange;
        });
      }
    } catch (e) {
      if (!mounted) return;
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
          invalidateLibraryData(ref);
        } else {
          final progress = status.progress;
          setState(() {
            if (progress != null && progress.total > 0) {
              _scanProgress = progress.processed / progress.total;
              _scanProcessed = progress.processed;
              _scanTotal = progress.total;
              _scanCurrentPath = progress.currentPath.isNotEmpty
                  ? progress.currentPath
                  : null;
            } else {
              _scanProgress = 0.0;
              _scanProcessed = 0;
              _scanTotal = 0;
              _scanCurrentPath = null;
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

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _VersionPill extends StatelessWidget {
  const _VersionPill();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final info = snapshot.data!;
        return Semantics(
          label: 'Version ${info.version}',
          child: SoftBadge(
            label: 'v${info.version}',
            tone: SoftBadgeTone.accent,
          ),
        );
      },
    );
  }
}

/// The section list on the left of the two-pane layout.
class _SectionNav extends StatelessWidget {
  const _SectionNav({
    required this.text,
    required this.active,
    required this.onSelect,
  });

  final AppStrings text;
  final _SettingsSection active;
  final ValueChanged<_SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _SettingsSection.library: text.librarySection,
      _SettingsSection.reader: text.readerSection,
      _SettingsSection.appearance: text.appearanceSection,
      _SettingsSection.data: text.dataSection,
      _SettingsSection.about: text.updateAboutSection,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in labels.entries) ...[
          _SectionNavItem(
            label: entry.value,
            selected: entry.key == active,
            onPressed: () => onSelect(entry.key),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _SectionNavItem extends StatefulWidget {
  const _SectionNavItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SectionNavItem> createState() => _SectionNavItemState();
}

class _SectionNavItemState extends State<_SectionNavItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            height: AppShape.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: selected
                  ? colors.card
                  : _hovered
                  ? colors.secondary.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? colors.primary
                    : selected
                    ? reader.line
                    : Colors.transparent,
                width: _focused ? 2 : 1,
              ),
              boxShadow: selected ? AppShape.controlShadow(reader) : null,
            ),
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? colors.foreground : colors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A radius-28 card holding [SettingsRow]s separated by hairlines.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final reader = context.appReader;
    return SoftCard(
      radius: AppShape.radiusLarge,
      clip: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, color: reader.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Title + description on the left, the control on the right, with an
/// optional block underneath (status lines, progress, extra fields).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.control,
    this.description,
    this.descriptionWidget,
    this.below,
    this.controlWidth,
  });

  static const double _narrowBreakpoint = 560;

  final String title;
  final String? description;
  final Widget? descriptionWidget;
  final Widget control;
  final Widget? below;

  /// Fixed control width for sliders; buttons size themselves.
  final double? controlWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            height: 24 / 15,
            fontWeight: FontWeight.w700,
            color: colors.foreground,
          ),
        ),
        if (descriptionWidget != null)
          descriptionWidget!
        else if (description != null)
          Text(
            description!,
            style: TextStyle(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
              color: colors.mutedForeground,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < _narrowBreakpoint;
          final sizedControl = controlWidth == null
              ? control
              : SizedBox(
                  width: narrow
                      ? constraints.maxWidth
                      : math.min(controlWidth!, constraints.maxWidth * 0.55),
                  child: control,
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (narrow) ...[
                labelColumn,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: sizedControl),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: labelColumn),
                    const SizedBox(width: 24),
                    sizedControl,
                  ],
                ),
              if (below != null) ...[const SizedBox(height: 12), below!],
            ],
          );
        },
      ),
    );
  }
}

class _SliderControl extends StatelessWidget {
  const _SliderControl({required this.valueLabel, required this.slider});

  final String valueLabel;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Expanded(child: slider),
        const SizedBox(width: 12),
        SizedBox(
          width: 52,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.foreground,
            ),
          ),
        ),
      ],
    );
  }
}

/// The library path: an editable mono field with a save action.
class _PathField extends StatelessWidget {
  const _PathField({
    required this.controller,
    required this.hint,
    required this.saveTooltip,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final String saveTooltip;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: AppShape.controlHeight,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(AppShape.radiusControl),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const [
                    'Menlo',
                    'Consolas',
                    'DejaVu Sans Mono',
                    'Courier New',
                  ],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.foreground,
                ),
                cursorColor: colors.primary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.mutedForeground,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SoftIconButton(
              icon: AppIcons.save,
              tooltip: saveTooltip,
              iconSize: 16,
              outline: false,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

enum _StatusTone { muted, success, error, accent }

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.tone,
    this.dot = false,
    this.icon,
  });

  final String label;
  final _StatusTone tone;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final reader = context.appReader;
    final color = switch (tone) {
      _StatusTone.muted => colors.mutedForeground,
      _StatusTone.success => reader.success,
      _StatusTone.error => colors.destructive,
      _StatusTone.accent => colors.secondaryForeground,
    };
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ] else if (dot) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
