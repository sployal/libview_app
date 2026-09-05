import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/client_service.dart';
import '../services/google_drive_service.dart';
import '../services/download_service.dart';
import '../services/phone_document_service.dart';
import '../services/upload_service.dart';
import '../ui/adaptive_layout.dart';
import '../ui/file_details.dart';
import '../ui/file_sort.dart';
import '../ui/folder_lock_dialog.dart';
import '../ui/move_file_dialog.dart';
import '../ui/preview_overlay_icon.dart';
import '../ui/drive_thumbnail.dart';
import 'no_internet_screen.dart';
import 'phone_audio.dart';
import 'phone_pdf.dart';
import 'web_view_screen.dart';
import 'media_player_screen.dart';

class ClientFilesBrowserScreen extends StatefulWidget {
  final String workspaceName;
  final String? folderId;
  final VoidCallback? onBack;
  final String? clientId;
  final String? initialFolderId;
  final String? initialFolderName;

  const ClientFilesBrowserScreen({
    super.key,
    this.workspaceName = 'Files',
    this.folderId,
    this.onBack,
    this.clientId,
    this.initialFolderId,
    this.initialFolderName,
  });

  @override
  State<ClientFilesBrowserScreen> createState() =>
      _ClientFilesBrowserScreenState();
}

class _ClientFilesBrowserScreenState extends State<ClientFilesBrowserScreen> {
  List<Subject> subjects = [];
  bool isLoading = true;
  String? errorMessage;
  
  Subject? selectedSubject;
  StudyMaterial? openedMaterial;
  List<StudyMaterial> currentFiles = [];
  bool isLoadingFiles = false;
  
  // NEW: Track downloading state for each file
  Map<String, bool> downloadingFiles = {};
  Map<String, double> downloadProgress = {};
  final Set<String> _deletingIds = {};
  final Set<String> _movingIds = {};
  bool isUploading = false;
  double uploadProgress = 0.0;
  static const int _maxImageUploadSelection = 10;
  static const int _maxVideoUploadSelection = 5;
  final _UploadProgressSession _uploadSession = _UploadProgressSession();
  CancelToken? _uploadCancelToken;
  bool _uploadDialogVisible = false;
  BuildContext? _uploadDialogContext;
  bool _isMutatingFolder = false;
  final List<Subject> _folderTrail = [];
  final Set<String> _lockedFolderIds = {};
  final Set<String> _sessionUnlockedFolderIds = {};
  bool _useLargeIcons = true;
  FileSortMode _fileSort = FileSortMode.nameAz;
  FileSortMode _folderSort = FileSortMode.nameAz;
  bool _unitsAsGrid = false;
  String _unitQuery = '';
  final TextEditingController _unitSearchController = TextEditingController();
  final FocusNode _unitSearchFocus = FocusNode();
  String _fileQuery = '';
  String _fileTypeFilter = 'All';
  final TextEditingController _fileSearchController = TextEditingController();
  final FocusNode _fileSearchFocus = FocusNode();
  static const _fileTypeFilters = [
    'All',
    'PDF',
    'DOC',
    'PPT',
    'IMG',
    'VID',
    'AUD',
  ];
  static const _filesViewPrefKey = 'client_files_view_grid';
  static const _filesSortPrefKey = 'client_files_sort_mode';
  static const _unitsViewPrefKey = 'client_folders_view_list';
  static const _unitsSortPrefKey = 'client_folders_sort_mode';

  bool get _canManageFolders => true;
  final Map<String, StudyMaterial> _selectedItems = {};
  final Map<String, Subject> _selectedUnits = {};

  bool get _fileSelectionMode => _selectedItems.isNotEmpty;
  bool get _folderSelectionMode => _selectedUnits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadFilesViewPreference();
    _loadSubjects();
    _unitSearchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _fileSearchFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadFilesViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _useLargeIcons = prefs.getBool(_filesViewPrefKey) ?? true;
      _fileSort = FileSortModeX.fromStorage(prefs.getString(_filesSortPrefKey));
      _folderSort = FileSortModeX.fromStorage(prefs.getString(_unitsSortPrefKey));
      _unitsAsGrid = prefs.getBool(_unitsViewPrefKey) ?? false;
    });
  }

  @override
  void dispose() {
    _uploadCancelToken?.cancel('disposed');
    _uploadSession.dispose();
    _unitSearchController.dispose();
    _unitSearchFocus.dispose();
    _fileSearchController.dispose();
    _fileSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleFilesView() async {
    setState(() {
      _useLargeIcons = !_useLargeIcons;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filesViewPrefKey, _useLargeIcons);
  }

  Future<void> _openFileSort() async {
    final next = await showFileSortSheet(
      context: context,
      selected: _fileSort,
    );
    if (next == null || !mounted || next == _fileSort) return;
    setState(() {
      _fileSort = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filesSortPrefKey, next.storageValue);
  }

  Future<void> _openFolderSort() async {
    final next = await showFileSortSheet(
      context: context,
      selected: _folderSort,
      kind: FileSortKind.folders,
    );
    if (next == null || !mounted || next == _folderSort) return;
    setState(() {
      _folderSort = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_unitsSortPrefKey, next.storageValue);
  }

  Future<void> _toggleUnitsView() async {
    HapticFeedback.selectionClick();
    setState(() {
      _unitsAsGrid = !_unitsAsGrid;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unitsViewPrefKey, _unitsAsGrid);
  }

  List<Subject> get _visibleUnits {
    final query = _unitQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? subjects
        : subjects.where((subject) {
            return subject.name.toLowerCase().contains(query) ||
                subject.code.toLowerCase().contains(query);
          });
    return FileSort.apply(
      filtered,
      mode: _folderSort,
      nameOf: (subject) => subject.name,
      sizeOf: (subject) => subject.fileCount,
      dateOf: (subject) => subject.modifiedAt,
      uploadedOf: (subject) => subject.createdAt,
    );
  }

  int get _totalUnitFiles =>
      subjects.fold(0, (sum, subject) => sum + subject.fileCount);

  int get _totalUnitFolders => subjects.fold(
        0,
        (sum, subject) => sum + 1 + subject.folderCount,
      );

  int get _listedFolderCount =>
      currentFiles.where((file) => file.isFolder).length;

  int get _nestedFileCount {
    var files = 0;
    for (final file in currentFiles) {
      if (file.isFolder) {
        files += file.fileCount;
      } else {
        files += 1;
      }
    }
    return files;
  }

  void _subtractListedItemCounts(StudyMaterial item) {
    final subject = selectedSubject;
    if (subject == null) return;
    if (item.isFolder) {
      final nextFiles = subject.fileCount - item.fileCount;
      final nextFolders = subject.folderCount - (1 + item.folderCount);
      subject.fileCount = nextFiles < 0 ? 0 : nextFiles;
      subject.folderCount = nextFolders < 0 ? 0 : nextFolders;
    } else if (subject.fileCount > 0) {
      subject.fileCount -= 1;
    }
  }

  List<StudyMaterial> get _visibleFiles {
    final query = _fileQuery.trim().toLowerCase();
    final filtered = currentFiles.where((file) {
      if (query.isNotEmpty && !file.name.toLowerCase().contains(query)) {
        return false;
      }
      if (file.isFolder) return true;
      if (_fileTypeFilter != 'All' && file.type != _fileTypeFilter) {
        return false;
      }
      return true;
    });
    final sorted = FileSort.apply(
      filtered,
      mode: _fileSort,
      nameOf: (file) => file.name,
      typeOf: (file) => file.type,
      sizeOf: (file) => file.sizeBytes ?? FileSort.parseSizeBytes(file.size),
      dateOf: (file) => file.modifiedAt ?? FileSort.parseDate(file.date),
      uploadedOf: (file) => file.createdAt,
    );
    return [
      ...sorted.where((file) => file.isFolder),
      ...sorted.where((file) => !file.isFolder),
    ];
  }

  void _resetFileSearch() {
    _fileSearchController.clear();
    _fileQuery = '';
    _fileTypeFilter = 'All';
  }

  void _clearFileSelection() {
    if (_selectedItems.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(_selectedItems.clear);
  }

  void _clearFolderSelection() {
    if (_selectedUnits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(_selectedUnits.clear);
  }

  void _toggleSelectedFile(StudyMaterial file) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedItems.containsKey(file.id)) {
        _selectedItems.remove(file.id);
      } else {
        _selectedItems[file.id] = file;
      }
    });
  }

  void _toggleSelectedUnit(Subject subject) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedUnits.containsKey(subject.folderId)) {
        _selectedUnits.remove(subject.folderId);
      } else {
        _selectedUnits[subject.folderId] = subject;
      }
    });
  }

  void _onListedItemTap(StudyMaterial file, {required bool isDownloading}) {
    if (_fileSelectionMode) {
      _toggleSelectedFile(file);
      return;
    }
    if (isDownloading) return;
    _openListedItem(file);
  }

  void _onListedItemLongPress(StudyMaterial file) {
    _toggleSelectedFile(file);
  }

  void _onUnitTap(Subject subject) {
    if (_folderSelectionMode) {
      _toggleSelectedUnit(subject);
      return;
    }
    _openUnit(subject);
  }

  void _onUnitLongPress(Subject subject) {
    _toggleSelectedUnit(subject);
  }

  void _selectAllVisibleFiles() {
    final visible = _visibleFiles;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedItems.length == visible.length) {
        _selectedItems.clear();
        return;
      }
      for (final file in visible) {
        _selectedItems[file.id] = file;
      }
    });
  }

  void _selectAllVisibleUnits() {
    final visible = _visibleUnits;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedUnits.length == visible.length) {
        _selectedUnits.clear();
        return;
      }
      for (final subject in visible) {
        _selectedUnits[subject.folderId] = subject;
      }
    });
  }

  List<StudyMaterial> get _selectedFileList => _selectedItems.values.toList();

  List<Subject> get _selectedUnitList => _selectedUnits.values.toList();

  List<MoveFileTarget> _commonMoveTargetsForFiles(List<StudyMaterial> items) {
    if (items.isEmpty) return const [];
    final selectedFolderIds = {
      for (final item in items)
        if (item.isFolder) item.id,
    };
    Set<String>? commonIds;
    final byId = <String, MoveFileTarget>{};
    for (final item in items) {
      final targets = item.isFolder
          ? _moveFolderTargets(folderId: item.id, fromFiles: true)
          : _moveTargets();
      for (final target in targets) {
        byId[target.id] = target;
      }
      final ids = targets.map((target) => target.id).toSet()
        ..removeAll(selectedFolderIds);
      commonIds = commonIds == null ? ids : commonIds.intersection(ids);
    }
    if (commonIds == null || commonIds.isEmpty) return const [];
    return [
      for (final id in commonIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  List<MoveFileTarget> _commonMoveTargetsForUnits(List<Subject> items) {
    if (items.isEmpty) return const [];
    final selectedIds = {
      for (final item in items) item.folderId,
    };
    Set<String>? commonIds;
    final byId = <String, MoveFileTarget>{};
    for (final item in items) {
      final targets = _moveFolderTargets(
        folderId: item.folderId,
        fromFiles: false,
      );
      for (final target in targets) {
        byId[target.id] = target;
      }
      final ids = targets.map((target) => target.id).toSet()..removeAll(selectedIds);
      commonIds = commonIds == null ? ids : commonIds.intersection(ids);
    }
    if (commonIds == null || commonIds.isEmpty) return const [];
    return [
      for (final id in commonIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> _openUnit(Subject subject) async {
    _selectedUnits.clear();
    final locked = subject.isLocked || _lockedFolderIds.contains(subject.folderId);
    if (locked && !_sessionUnlockedFolderIds.contains(subject.folderId)) {
      final opened = await _promptOpenLockedFolder(subject);
      if (!opened || !mounted) return;
    }
    HapticFeedback.lightImpact();
    final clientId = widget.clientId;
    if (clientId != null && clientId.isNotEmpty) {
      ClientRecentFolders.record(
        clientId: clientId,
        folderId: subject.folderId,
        name: subject.name,
      );
    }
    _folderTrail.clear();
    _loadSubjectFiles(subject);
  }

  Future<void> _refreshSubjects() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    await _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final showFullPage = subjects.isEmpty;
    setState(() {
      if (showFullPage) isLoading = true;
      errorMessage = null;
    });

    try {
      if (widget.folderId != null && widget.folderId!.isNotEmpty) {
        final loadedSubjects = await GoogleDriveService.getSubjectsFromFolder(
          widget.folderId!,
          nestedCounts: true,
        );
        var lockedIds = <String>{};
        try {
          lockedIds = await UploadService.instance.fetchLockedFolderIds(widget.folderId!);
        } catch (_) {}
        final withLocks = loadedSubjects
            .map(
              (subject) => subject.copyWith(
                isLocked: lockedIds.contains(subject.folderId),
              ),
            )
            .toList();
        setState(() {
          subjects = withLocks;
          _lockedFolderIds
            ..clear()
            ..addAll(lockedIds);
          isLoading = false;
          final ids = withLocks.map((subject) => subject.folderId).toSet();
          _selectedUnits.removeWhere((id, _) => !ids.contains(id));
        });
        _openInitialFolderIfNeeded(withLocks);
      } else {
        setState(() {
          subjects = _getSampleSubjects();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load folders. Please check your internet connection.';
        if (subjects.isEmpty) {
          subjects = [];
        }
        isLoading = false;
      });
    }
  }

  void _insertCreatedFolder(UploadResult result, String fallbackName) {
    final id = result.id;
    final name = result.name.isNotEmpty ? result.name : fallbackName;
    if (id.isEmpty || name.isEmpty) return;
    setState(() {
      subjects.removeWhere((subject) => subject.folderId == id);
      subjects.add(
        GoogleDriveService.subjectFromFolder(
          id: id,
          name: name,
          colorIndex: subjects.length,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          isLocked: _lockedFolderIds.contains(id),
        ),
      );
      errorMessage = null;
    });
  }

  void _applyFolderRename(Subject subject, String name) {
    final code = GoogleDriveService.subjectCodeFromName(name);
    final now = DateTime.now();
    setState(() {
      final index = subjects.indexWhere((item) => item.folderId == subject.folderId);
      if (index != -1) {
        subjects[index] = subjects[index].copyWith(
          name: name,
          code: code,
          modifiedAt: now,
        );
      }
      if (selectedSubject?.folderId == subject.folderId) {
        selectedSubject = selectedSubject!.copyWith(
          name: name,
          code: code,
          modifiedAt: now,
        );
      }
    });
  }

  void _removeFolder(Subject subject) {
    setState(() {
      subjects.removeWhere((item) => item.folderId == subject.folderId);
      _selectedUnits.remove(subject.folderId);
      _lockedFolderIds.remove(subject.folderId);
      _sessionUnlockedFolderIds.remove(subject.folderId);
      if (selectedSubject?.folderId == subject.folderId) {
        selectedSubject = null;
        currentFiles = [];
        _folderTrail.clear();
      }
    });
  }

  void _openInitialFolderIfNeeded(List<Subject> folders) {
    final targetId = widget.initialFolderId;
    if (targetId == null || targetId.isEmpty || selectedSubject != null) {
      return;
    }
    Subject? match;
    for (final folder in folders) {
      if (folder.folderId == targetId || folder.id == targetId) {
        match = folder;
        break;
      }
    }
    match ??= Subject(
      id: targetId,
      name: widget.initialFolderName ?? 'Folder',
      code: '',
      folderId: targetId,
      color: const Color(0xFF0EA5E9),
      isLocked: _lockedFolderIds.contains(targetId),
    );
    _openUnit(match);
  }

  List<Subject> _getSampleSubjects() {
    return [
      Subject(
        id: '1',
        name: 'Sample unit 1',
        code: 'SUB101',
        folderId: '',
        color: const Color(0xFF6366F1),
        fileCount: 0,
      ),
      Subject(
        id: '2',
        name: 'Sample unit 2',
        code: 'SUB102',
        folderId: '',
        color: const Color(0xFF10B981),
        fileCount: 0,
      ),
    ];
  }

  bool get _isLiveFolder => widget.folderId != null && widget.folderId!.isNotEmpty;

  Future<String?> _clientQuotaError(int incomingBytes) async {
    final clientId = widget.clientId;
    final rootId = widget.folderId;
    if (clientId == null || clientId.isEmpty || rootId == null || rootId.isEmpty) {
      return null;
    }
    final client = await ClientService.instance.getClient(clientId);
    if (client == null) return null;
    final used = await GoogleDriveService.summarizeFolder(rootId);
    if (used.bytes + incomingBytes > client.storageLimitBytes) {
      return 'Storage limit exceeded. '
          '${ClientWorkspace.formatStorage(used.bytes)} of '
          '${ClientWorkspace.formatStorage(client.storageLimitBytes)} used.';
    }
    return null;
  }

  void _insertUploadedFile(UploadResult result, PhonePickedDocument file) {
    final name = result.name.isNotEmpty ? result.name : file.name;
    final id = result.id.isNotEmpty
        ? result.id
        : 'local-${DateTime.now().microsecondsSinceEpoch}';
    final parsedSize = int.tryParse(result.size ?? '');
    final sizeBytes =
        parsedSize != null && parsedSize > 0 ? parsedSize : file.sizeBytes;
    final createdAt = result.createdAt ?? DateTime.now();
    final modifiedAt = result.modifiedAt ?? file.modifiedAt ?? createdAt;
    final material = StudyMaterial(
      id: id,
      name: name,
      type: _typeFromFileName(name),
      size: _displayFileSize(result.size, file.sizeBytes),
      date: GoogleDriveService.formatDate(modifiedAt.toUtc().toIso8601String()),
      downloadUrl: result.webViewLink,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      createdAt: createdAt,
    );

    setState(() {
      currentFiles.removeWhere((item) => item.id == id);
      currentFiles.insert(0, material);
      if (selectedSubject != null) {
        selectedSubject!.fileCount += 1;
      }
    });
  }

  String _typeFromFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'DOC';
      case 'ppt':
      case 'pptx':
        return 'PPT';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return 'IMG';
      case 'mp4':
      case 'm4v':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
      case '3gp':
      case '3g2':
      case 'wmv':
      case 'flv':
      case 'mpeg':
      case 'mpg':
      case 'ts':
      case 'm2ts':
      case 'mts':
      case 'ogv':
      case 'asf':
      case 'vob':
      case 'f4v':
        return 'VID';
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'flac':
      case 'ogg':
      case 'oga':
      case 'opus':
      case 'wma':
      case 'aiff':
      case 'aif':
      case 'amr':
      case 'mid':
      case 'midi':
      case 'caf':
      case 'weba':
        return 'AUD';
      default:
        return 'FILE';
    }
  }

  String _displayFileSize(String? remoteSize, int localBytes) {
    final parsed = int.tryParse(remoteSize ?? '');
    final size = parsed != null && parsed > 0 ? parsed : localBytes;
    if (size <= 0) return 'Unknown';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Future<void> _loadSubjectFiles(Subject subject) async {
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This folder is not connected to Drive'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    setState(() {
      selectedSubject = subject;
      isLoadingFiles = true;
      currentFiles = [];
      downloadingFiles.clear();
      downloadProgress.clear();
      _selectedItems.clear();
      _resetFileSearch();
    });

    try {
      final files = await GoogleDriveService.getSubjectFiles(
        subject.folderId,
        includeFolders: true,
      );
      setState(() {
        currentFiles = files;
        isLoadingFiles = false;
      });
    } catch (e) {
      setState(() {
        isLoadingFiles = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load files: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  bool _isListedFolderLocked(StudyMaterial file) {
    return file.isFolder && _lockedFolderIds.contains(file.id);
  }

  Subject _subjectFromListedFolder(StudyMaterial folder) {
    return GoogleDriveService.subjectFromFolder(
      id: folder.id,
      name: folder.name,
      colorIndex: _folderTrail.length + 1,
      fileCount: folder.fileCount,
      folderCount: folder.folderCount,
      modifiedAt: folder.modifiedAt,
      createdAt: folder.createdAt,
      isLocked: _isListedFolderLocked(folder),
    );
  }

  Future<void> _openListedItem(StudyMaterial material) async {
    if (material.isFolder) {
      await _openNestedFolder(material);
      return;
    }
    await _openFileInWebView(material);
  }

  Future<void> _openNestedFolder(StudyMaterial folder) async {
    final subject = _subjectFromListedFolder(folder);
    final locked =
        subject.isLocked || _lockedFolderIds.contains(subject.folderId);
    if (locked && !_sessionUnlockedFolderIds.contains(subject.folderId)) {
      final opened = await _promptOpenLockedFolder(subject);
      if (!opened || !mounted) return;
    }
    HapticFeedback.lightImpact();
    if (selectedSubject != null) {
      _folderTrail.add(selectedSubject!);
    }
    await _loadSubjectFiles(subject);
  }

  Future<void> _openFileInWebView(StudyMaterial material) async {
    if (material.downloadUrl == null || material.downloadUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File URL not available'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    setState(() {
      openedMaterial = material;
    });
  }

  void _closeWebView() {
    setState(() {
      openedMaterial = null;
    });
  }

  // NEW: Extract file ID from Google Drive URL
  String? _extractFileId(String url) {
    try {
      // Pattern 1: /d/FILE_ID/
      RegExp pattern1 = RegExp(r'/d/([a-zA-Z0-9_-]+)');
      Match? match = pattern1.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      // Pattern 2: ?id=FILE_ID or &id=FILE_ID
      RegExp pattern2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');
      match = pattern2.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      // Pattern 3: /file/d/FILE_ID/
      RegExp pattern3 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      match = pattern3.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  // NEW: Download individual file
  Future<void> _downloadFile(
    StudyMaterial material, {
    bool notify = true,
  }) async {
    if (material.downloadUrl == null || material.downloadUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('File URL not available'),
              ),
            ],
          ),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    // Extract file ID from URL
    final fileId = _extractFileId(material.downloadUrl!);
    
    if (fileId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Could not identify file from URL'),
                ),
              ],
            ),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      downloadingFiles[material.id] = true;
      downloadProgress[material.id] = 0.0;
    });

    // Download file using the file ID
    final result = await DownloadService.downloadFile(
      fileId: fileId,
      subject: selectedSubject?.name ?? 'Unknown',
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          downloadProgress[material.id] = progress;
        });
      },
    );

    if (!mounted) return;

    setState(() {
      downloadingFiles[material.id] = false;
      downloadProgress.remove(material.id);
    });

    if (!notify) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.success
                  ? Icons.check_circle
                  : result.cancelled
                      ? Icons.cancel_rounded
                      : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(result.message),
            ),
          ],
        ),
        backgroundColor: result.success
            ? const Color(0xFF10B981)
            : result.cancelled
                ? const Color(0xFF6B7280)
                : const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: Duration(seconds: result.success || result.cancelled ? 3 : 5),
      ),
    );
  }

  void _cancelDownload(StudyMaterial material) {
    final url = material.downloadUrl;
    if (url == null || url.isEmpty) return;
    final fileId = _extractFileId(url);
    if (fileId == null) return;
    DownloadService.cancelDownload(fileId);
  }

  Future<void> _confirmDelete(StudyMaterial material) async {
    if (!_canManageFolders) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            material.isFolder ? 'Delete folder?' : 'Delete material?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            material.isFolder
                ? '“${material.name}” and everything inside it will be permanently removed.'
                : '“${material.name}” will be permanently removed from this folder.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteMaterial(material);
    }
  }

  Future<void> _renameMaterial(StudyMaterial material) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder) {
      _showMessage('This file is not connected to Drive', isError: true);
      return;
    }

    final name = await _promptFolderName(
      title: material.isFolder ? 'Rename folder' : 'Rename file',
      confirmLabel: 'Rename',
      initial: material.isFolder ? material.name : _fileStem(material.name),
      fieldLabel: material.isFolder ? 'Folder name' : 'File name',
      takenNames: currentFiles
          .where((file) => file.id != material.id)
          .map((file) => file.name)
          .toList(),
      takenError: material.isFolder
          ? 'A folder with that name already exists'
          : 'A file with that name already exists',
      clashAsFile: !material.isFolder,
      extensionFrom: material.isFolder ? null : material.name,
    );
    if (name == null) return;

    final nextName = material.isFolder
        ? name
        : _fileNameWithExtension(name, material.name);
    if (nextName == material.name) return;
    if (_fileNameTaken(nextName, ignoreId: material.id)) {
      _showMessage(
        material.isFolder
            ? 'A folder named "$nextName" already exists'
            : 'A file named "$nextName" already exists',
        isError: true,
      );
      return;
    }

    try {
      final result = await UploadService.instance.renameFile(
        fileId: material.id,
        name: nextName,
      );
      if (!mounted) return;
      final savedName = result.name.isNotEmpty ? result.name : nextName;
      setState(() {
        final index = currentFiles.indexWhere((item) => item.id == material.id);
        if (index != -1) {
          final existing = currentFiles[index];
          currentFiles[index] = existing.copyWith(name: savedName);
        }
      });
      _showMessage('Renamed to "$savedName"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to rename file', isError: true);
    }
  }

  Future<void> _deleteMaterial(StudyMaterial material) async {
    if (_deletingIds.contains(material.id)) return;

    setState(() {
      _deletingIds.add(material.id);
    });

    try {
      if (_isLiveFolder) {
        await UploadService.instance.deleteFile(material.id);
      }

      if (!mounted) return;
      setState(() {
        currentFiles.removeWhere((item) => item.id == material.id);
        _deletingIds.remove(material.id);
        _subtractListedItemCounts(material);
      });
      _showMessage('Deleted ${material.name}');
    } on UploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(material.id);
      });
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(material.id);
      });
      _showMessage('Failed to delete ${material.name}', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _folderNameTaken(String name, {String? ignoreId}) {
    if (name.trim().isEmpty) return false;
    return subjects.any((subject) {
      if (ignoreId != null && subject.folderId == ignoreId) return false;
      return GoogleDriveService.folderNamesClash(subject.name, name);
    });
  }

  bool _canOfferMove(StudyMaterial file) {
    if (file.isFolder) return false;
    return _moveTargets().isNotEmpty;
  }

  List<MoveFileTarget> _moveFolderTargets({
    required String folderId,
    required bool fromFiles,
  }) {
    final targets = <MoveFileTarget>[];
    if (fromFiles) {
      final rootId = widget.folderId;
      if (rootId != null && rootId.isNotEmpty && rootId != folderId) {
        targets.add(
          MoveFileTarget(
            id: rootId,
            name: widget.workspaceName,
            isMain: true,
          ),
        );
      }
      final folders = currentFiles
          .where((file) => file.isFolder && file.id != folderId)
          .toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      for (final folder in folders) {
        if (folder.id.isEmpty) continue;
        targets.add(MoveFileTarget(id: folder.id, name: folder.name));
      }
      return targets;
    }

    final folders = [...subjects]
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    for (final subject in folders) {
      if (subject.folderId.isEmpty || subject.folderId == folderId) continue;
      targets.add(MoveFileTarget(id: subject.folderId, name: subject.name));
    }
    return targets;
  }

  bool _canOfferMoveFolder({
    required String folderId,
    required bool fromFiles,
  }) {
    return _moveFolderTargets(folderId: folderId, fromFiles: fromFiles)
        .isNotEmpty;
  }

  List<MoveFileTarget> _moveTargets() {
    final folders = currentFiles.where((file) => file.isFolder).toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    final targets = <MoveFileTarget>[];
    if (_folderTrail.isNotEmpty) {
      final main = _folderTrail.first;
      if (main.folderId.isNotEmpty &&
          main.folderId != selectedSubject?.folderId) {
        targets.add(
          MoveFileTarget(
            id: main.folderId,
            name: main.name,
            isMain: true,
          ),
        );
      }
    }
    for (final folder in folders) {
      if (folder.id.isEmpty) continue;
      targets.add(MoveFileTarget(id: folder.id, name: folder.name));
    }
    return targets;
  }

  Future<void> _moveMaterial(StudyMaterial material) async {
    if (!_canManageFolders || material.isFolder) return;
    if (_movingIds.contains(material.id) || _deletingIds.contains(material.id)) {
      return;
    }
    final targets = _moveTargets();
    if (targets.isEmpty) return;

    final destination = await showMoveFileDialog(
      context: context,
      fileName: material.name,
      targets: targets,
    );
    if (destination == null || !mounted) return;

    setState(() {
      _movingIds.add(material.id);
    });

    try {
      await UploadService.instance.moveFile(
        fileId: material.id,
        parentFolderId: destination.id,
      );
      if (!mounted) return;
      setState(() {
        currentFiles.removeWhere((item) => item.id == material.id);
        _movingIds.remove(material.id);
        _subtractListedItemCounts(material);
      });
      _showMessage(
        destination.isMain
            ? 'Moved to ${destination.name}'
            : 'Moved to "${destination.name}"',
      );
    } on UploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _movingIds.remove(material.id);
      });
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movingIds.remove(material.id);
      });
      _showMessage('Failed to move ${material.name}', isError: true);
    }
  }

  Future<void> _moveUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (_isMutatingFolder) return;
    final targets = _moveFolderTargets(
      folderId: subject.folderId,
      fromFiles: false,
    );
    if (targets.isEmpty) return;

    final destination = await showMoveFileDialog(
      context: context,
      fileName: subject.name,
      targets: targets,
      isFolder: true,
    );
    if (destination == null || !mounted) return;

    setState(() {
      _isMutatingFolder = true;
    });
    try {
      await UploadService.instance.moveFile(
        fileId: subject.folderId,
        parentFolderId: destination.id,
      );
      if (!mounted) return;
      setState(() {
        subjects.removeWhere((item) => item.folderId == subject.folderId);
        if (selectedSubject?.folderId == subject.folderId) {
          selectedSubject = null;
          currentFiles = [];
          _folderTrail.clear();
        }
      });
      _showMessage('Moved to "${destination.name}"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to move "${subject.name}"', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _moveListedFolder(StudyMaterial folder) async {
    if (!_canManageFolders || !folder.isFolder) return;
    if (_movingIds.contains(folder.id) || _deletingIds.contains(folder.id)) {
      return;
    }
    final targets = _moveFolderTargets(folderId: folder.id, fromFiles: true);
    if (targets.isEmpty) return;

    final destination = await showMoveFileDialog(
      context: context,
      fileName: folder.name,
      targets: targets,
      isFolder: true,
    );
    if (destination == null || !mounted) return;

    setState(() {
      _movingIds.add(folder.id);
    });
    try {
      final result = await UploadService.instance.moveFile(
        fileId: folder.id,
        parentFolderId: destination.id,
      );
      if (!mounted) return;
      setState(() {
        currentFiles.removeWhere((item) => item.id == folder.id);
        _movingIds.remove(folder.id);
      });
      if (destination.isMain) {
        _insertCreatedFolder(result, folder.name);
      }
      _showMessage(
        destination.isMain
            ? 'Moved to the main folders'
            : 'Moved to "${destination.name}"',
      );
    } on UploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _movingIds.remove(folder.id);
      });
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movingIds.remove(folder.id);
      });
      _showMessage('Failed to move "${folder.name}"', isError: true);
    }
  }

  bool _fileNameTaken(String name, {String? ignoreId}) {
    if (name.trim().isEmpty) return false;
    return currentFiles.any((file) {
      if (ignoreId != null && file.id == ignoreId) return false;
      return GoogleDriveService.fileNamesClash(file.name, name);
    });
  }

  String? _firstDuplicateUploadName(Iterable<String> names) {
    final seen = <String>[];
    for (final name in names) {
      if (_fileNameTaken(name) ||
          seen.any((existing) => GoogleDriveService.fileNamesClash(existing, name))) {
        return name;
      }
      seen.add(name);
    }
    return null;
  }

  Future<String?> _promptFolderName({
    required String title,
    required String confirmLabel,
    String initial = '',
    String fieldLabel = 'Folder name',
    String? helperText,
    List<String> takenNames = const [],
    String takenError = 'A folder with that name already exists',
    bool clashAsFile = false,
    String? extensionFrom,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) {
        return _FolderNameDialog(
          title: title,
          confirmLabel: confirmLabel,
          initial: initial,
          fieldLabel: fieldLabel,
          helperText: helperText,
          takenNames: takenNames,
          takenError: takenError,
          clashAsFile: clashAsFile,
          extensionFrom: extensionFrom,
        );
      },
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  String _fileExtension(String name) {
    final trimmed = name.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot <= 0 || dot == trimmed.length - 1) return '';
    final extension = trimmed.substring(dot);
    final suffix = extension.substring(1);
    if (suffix.contains(' ') || suffix.length > 8) return '';
    return extension;
  }

  String _fileStem(String name) {
    final trimmed = name.trim();
    final extension = _fileExtension(trimmed);
    if (extension.isEmpty) return trimmed;
    return trimmed.substring(0, trimmed.length - extension.length);
  }

  String _fileNameWithExtension(String nextName, String originalName) {
    final extension = _fileExtension(originalName);
    if (extension.isEmpty) return nextName.trim();
    return '${_fileStem(nextName)}$extension';
  }

  Future<void> _createUnitFolder() async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || widget.folderId == null || widget.folderId!.isEmpty) {
      _showMessage('This workspace is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Create folder',
      confirmLabel: 'Create',
      takenNames: subjects.map((subject) => subject.name).toList(),
    );
    if (name == null) return;
    if (_folderNameTaken(name)) {
      _showMessage('A folder named "$name" already exists', isError: true);
      return;
    }

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      final result = await UploadService.instance.createFolder(
        parentFolderId: widget.folderId!,
        name: name,
      );
      if (!mounted) return;
      _insertCreatedFolder(result, name);
      _showMessage('Created "${result.name.isNotEmpty ? result.name : name}"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to create folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _createNestedFolder() async {
    if (!_canManageFolders) return;
    final parentId = selectedSubject?.folderId ?? '';
    if (!_isLiveFolder || parentId.isEmpty) {
      _showMessage('This folder is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Create folder',
      confirmLabel: 'Create',
      takenNames: currentFiles.map((file) => file.name).toList(),
    );
    if (name == null) return;
    if (_fileNameTaken(name)) {
      _showMessage('A folder named "$name" already exists', isError: true);
      return;
    }

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      final result = await UploadService.instance.createFolder(
        parentFolderId: parentId,
        name: name,
      );
      if (!mounted) return;
      _insertCreatedNestedFolder(result, name);
      _showMessage('Created "${result.name.isNotEmpty ? result.name : name}"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to create folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  void _insertCreatedNestedFolder(UploadResult result, String fallbackName) {
    final id = result.id;
    final name = result.name.isNotEmpty ? result.name : fallbackName;
    if (id.isEmpty || name.isEmpty) return;
    setState(() {
      currentFiles.removeWhere((file) => file.id == id);
      currentFiles.add(
        StudyMaterial(
          id: id,
          name: name,
          type: 'FOLDER',
          size: GoogleDriveService.folderContentsLabel(
            fileCount: 0,
            folderCount: 0,
          ),
          date: GoogleDriveService.formatDate(DateTime.now().toIso8601String()),
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      );
      if (selectedSubject != null) {
        selectedSubject!.folderCount += 1;
      }
    });
  }

  Future<void> _renameUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This folder is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Rename folder',
      confirmLabel: 'Rename',
      initial: subject.name,
      takenNames: subjects
          .where((item) => item.folderId != subject.folderId)
          .map((item) => item.name)
          .toList(),
    );
    if (name == null || name == subject.name) return;
    if (_folderNameTaken(name, ignoreId: subject.folderId)) {
      _showMessage('A folder named "$name" already exists', isError: true);
      return;
    }

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      final result = await UploadService.instance.renameFile(
        fileId: subject.folderId,
        name: name,
      );
      if (!mounted) return;
      final savedName = result.name.isNotEmpty ? result.name : name;
      _applyFolderRename(subject, savedName);
      _showMessage('Renamed to "$savedName"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to rename folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This folder is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete folder',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will permanently delete "${subject.name}" and all files inside it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteUnitFolder(subject);
    }
  }

  void _setFolderLocked(String folderId, bool locked) {
    if (locked) {
      _lockedFolderIds.add(folderId);
    } else {
      _lockedFolderIds.remove(folderId);
      _sessionUnlockedFolderIds.remove(folderId);
    }
    final index = subjects.indexWhere((item) => item.folderId == folderId);
    if (index != -1) {
      subjects[index] = subjects[index].copyWith(isLocked: locked);
    }
    if (selectedSubject?.folderId == folderId) {
      selectedSubject = selectedSubject!.copyWith(isLocked: locked);
    }
  }

  Future<bool> _promptOpenLockedFolder(Subject subject) async {
    final password = await showFolderLockDialog(
      context: context,
      mode: FolderLockDialogMode.enter,
      folderName: subject.name,
    );
    if (password == null || !mounted) return false;
    try {
      await UploadService.instance.verifyClientFolderPassword(
        folderId: subject.folderId,
        password: password,
      );
      if (!mounted) return false;
      _sessionUnlockedFolderIds.add(subject.folderId);
      return true;
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
      return false;
    } catch (_) {
      _showMessage('Could not open this folder', isError: true);
      return false;
    }
  }

  Future<void> _lockUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This folder is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final password = await showFolderLockDialog(
      context: context,
      mode: FolderLockDialogMode.lock,
      folderName: subject.name,
    );
    if (password == null || !mounted) return;

    setState(() {
      _isMutatingFolder = true;
    });
    try {
      await UploadService.instance.lockClientFolder(
        folderId: subject.folderId,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _setFolderLocked(subject.folderId, true);
      });
      _showMessage('“${subject.name}” is locked');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to lock folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _unlockUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This folder is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final password = await showFolderLockDialog(
      context: context,
      mode: FolderLockDialogMode.unlock,
      folderName: subject.name,
    );
    if (password == null || !mounted) return;

    setState(() {
      _isMutatingFolder = true;
    });
    try {
      await UploadService.instance.unlockClientFolder(
        folderId: subject.folderId,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _setFolderLocked(subject.folderId, false);
      });
      _showMessage('“${subject.name}” is unlocked');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to unlock folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<void> _deleteUnitFolder(Subject subject) async {
    if (_isMutatingFolder) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.deleteFile(subject.folderId);
      if (!mounted) return;
      _removeFolder(subject);
      _showMessage('Deleted "${subject.name}"');
    } on UploadException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Failed to delete folder', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingFolder = false;
        });
      }
    }
  }

  Future<_UploadSource?> _showUploadSourceSheet() {
    return showModalBottomSheet<_UploadSource>(
      context: context,
      backgroundColor: const Color(0xFF1B2230),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _UploadSourceSheet(),
    );
  }

  Future<void> _pickAndUploadFile() async {
    if (!_canManageFolders) return;
    final subject = selectedSubject;
    if (subject == null || !_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('Open a folder before uploading', isError: true);
      return;
    }
    if (isUploading) return;
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    final source = await _showUploadSourceSheet();
    if (source == null || !mounted) return;

    if (source == _UploadSource.documents) {
      final picked = await Navigator.push<List<PhonePickedDocument>>(
        context,
        MaterialPageRoute(builder: (_) => const PhonePdfScreen()),
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      await _uploadPickedFiles(subject.folderId, picked);
      return;
    }

    if (source == _UploadSource.videos) {
      await _pickAndUploadMedia(
        folderId: subject.folderId,
        kind: 'video',
        pickerType: FileType.video,
        maxSelection: _maxVideoUploadSelection,
        pickerTitle: 'Select videos to upload',
      );
      return;
    }

    if (source == _UploadSource.audio) {
      final picked = await Navigator.push<List<PhonePickedDocument>>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneAudioScreen()),
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      await _uploadPickedFiles(subject.folderId, picked);
      return;
    }

    _enableAndroidPhotoPicker();
    List<XFile> images;
    try {
      images = await ImagePicker().pickMultiImage(
        limit: _maxImageUploadSelection,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showMessage(
        e.message ?? 'Could not open photos',
        isError: true,
      );
      return;
    }
    if (images.isEmpty || !mounted) return;
    if (images.length > _maxImageUploadSelection) {
      _showMessage(
        'You can upload up to $_maxImageUploadSelection images at a time',
        isError: true,
      );
      return;
    }

    final picked = <PhonePickedDocument>[];
    final usedNames = <String>{};
    for (final image in images) {
      final sizeBytes = await image.length();
      final originalName = image.name;
      final name = _uniquePickedName(originalName, usedNames);
      usedNames.add(name);
      final resolved = await PhonePickedDocument.fromFile(
        name: originalName,
        path: image.path,
        sizeBytes: sizeBytes,
      );
      picked.add(
        PhonePickedDocument(
          name: name,
          path: resolved.path,
          sizeBytes: sizeBytes,
          modifiedAt: resolved.modifiedAt,
        ),
      );
    }

    if (picked.isEmpty || !mounted) return;
    await _uploadPickedFiles(subject.folderId, picked);
  }

  Future<void> _pickAndUploadMedia({
    required String folderId,
    required String kind,
    required FileType pickerType,
    required int maxSelection,
    required String pickerTitle,
  }) async {
    List<PhonePickedDocument> raw = const [];
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        raw = await PhoneDocumentService.instance.pickMediaForUpload(
          kind: kind,
          maxSelection: maxSelection,
        );
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: pickerType,
          allowMultiple: true,
          withData: false,
          dialogTitle: pickerTitle,
        );
        if (result == null || result.files.isEmpty) return;
        final picked = <PhonePickedDocument>[];
        for (final file in result.files) {
          final path = file.path;
          if (path == null || path.isEmpty) continue;
          picked.add(
            await PhonePickedDocument.fromFile(
              name: file.name,
              path: path,
              sizeBytes: file.size,
            ),
          );
        }
        raw = picked;
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showMessage(e.message ?? 'Could not open files', isError: true);
      return;
    }
    if (raw.isEmpty || !mounted) return;
    if (raw.length > maxSelection) {
      _showMessage(
        'You can upload up to $maxSelection files at a time',
        isError: true,
      );
      return;
    }

    final usedNames = <String>{};
    final picked = <PhonePickedDocument>[];
    for (final file in raw) {
      final name = _uniquePickedName(file.name, usedNames);
      usedNames.add(name);
      picked.add(
        PhonePickedDocument(
          name: name,
          path: file.path,
          sizeBytes: file.sizeBytes,
          modifiedAt: file.modifiedAt,
        ),
      );
    }

    if (picked.isEmpty || !mounted) return;
    await _uploadPickedFiles(folderId, picked);
  }

  void _enableAndroidPhotoPicker() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  String _uniquePickedName(String fileName, Iterable<String> usedNames) {
    bool taken(String name) =>
        usedNames.any((used) => GoogleDriveService.fileNamesClash(used, name));
    if (!taken(fileName)) return fileName;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var n = 2;
    var candidate = '${stem}_$n$ext';
    while (taken(candidate)) {
      n++;
      candidate = '${stem}_$n$ext';
    }
    return candidate;
  }

  Future<void> _uploadPickedFiles(
    String folderId,
    List<PhonePickedDocument> files, {
    Map<String, List<int>>? bytesByName,
  }) async {
    if (isUploading || files.isEmpty) return;

    final duplicate = _firstDuplicateUploadName(files.map((file) => file.name));
    if (duplicate != null) {
      _showMessage('A file named "$duplicate" already exists', isError: true);
      return;
    }

    final cancelToken = CancelToken();
    _uploadCancelToken = cancelToken;
    _uploadSession.start(files.length);

    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
    });
    _showUploadProgressDialog();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);

    final incomingBytes = files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    final quotaError = await _clientQuotaError(incomingBytes);
    if (quotaError != null) {
      _uploadCancelToken = null;
      if (mounted) {
        _hideUploadProgressDialog();
        setState(() {
          isUploading = false;
          uploadProgress = 0.0;
        });
        _showMessage(quotaError, isError: true);
      }
      return;
    }

    var uploaded = 0;
    var cancelled = false;
    String? lastError;

    try {
      for (var i = 0; i < files.length; i++) {
        if (cancelToken.isCancelled) {
          cancelled = true;
          break;
        }

        final file = files[i];
        _uploadSession.beginFile(file.name, file.sizeBytes, i);

        try {
          final result = await UploadService.instance.uploadFile(
            folderId: folderId,
            fileName: file.name,
            filePath: file.path.isEmpty ? null : file.path,
            bytes: bytesByName?[file.name],
            modifiedAt: file.modifiedAt,
            cancelToken: cancelToken,
            onProgress: (progress) {
              if (!mounted) return;
              _uploadSession.updateFileProgress(progress);
            },
            onBytes: (sent, total) {
              if (!mounted) return;
              _uploadSession.updateBytes(sent, total);
            },
          );
          uploaded++;
          if (mounted) {
            _uploadSession.markCompleted();
            _insertUploadedFile(result, file);
          }
        } on UploadCancelledException {
          cancelled = true;
          break;
        } on UploadException catch (e) {
          lastError = e.message;
        } catch (_) {
          lastError = 'Upload failed. Please try again.';
        }
      }
    } finally {
      _uploadCancelToken = null;
      if (mounted) {
        _hideUploadProgressDialog();
        setState(() {
          isUploading = false;
          uploadProgress = 0.0;
        });
      }
    }

    if (!mounted) return;

    if (cancelled) {
      _showMessage(
        uploaded == 0
            ? 'Upload cancelled'
            : 'Upload cancelled. $uploaded of ${files.length} uploaded.',
        isError: true,
      );
    } else if (uploaded == files.length) {
      _showMessage(
        uploaded == 1
            ? '${files.first.name} uploaded successfully'
            : '$uploaded files uploaded successfully',
      );
    } else if (uploaded > 0) {
      _showMessage(
        '$uploaded of ${files.length} uploaded. ${lastError ?? 'Some files failed.'}',
        isError: true,
      );
    } else {
      _showMessage(
        lastError ?? 'Upload failed. Please try again.',
        isError: true,
      );
    }
  }

  void _showUploadProgressDialog() {
    if (_uploadDialogVisible || !mounted) return;
    _uploadDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        _uploadDialogContext = dialogContext;
        return ListenableBuilder(
          listenable: _uploadSession,
          builder: (context, _) {
            return _UploadProgressDialog(
              session: _uploadSession,
              onCancel: _cancelActiveUpload,
            );
          },
        );
      },
    ).whenComplete(() {
      _uploadDialogVisible = false;
      _uploadDialogContext = null;
    });
  }

  void _hideUploadProgressDialog() {
    if (!_uploadDialogVisible) return;
    final dialogContext = _uploadDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  void _cancelActiveUpload() {
    if (_uploadCancelToken == null || _uploadCancelToken!.isCancelled) return;
    _uploadSession.markCancelling();
    _uploadCancelToken!.cancel('cancelled');
  }

  void _backToSubjects() {
    if (_folderTrail.isNotEmpty) {
      final parent = _folderTrail.removeLast();
      _loadSubjectFiles(parent);
      return;
    }
    setState(() {
      openedMaterial = null;
      selectedSubject = null;
      currentFiles = [];
      downloadingFiles.clear();
      downloadProgress.clear();
      _selectedItems.clear();
      _resetFileSearch();
    });
  }

  void _leaveSemester() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.maybePop(context);
  }

  Future<void> _onSystemBack() async {
    if (_fileSelectionMode) {
      _clearFileSelection();
      return;
    }
    if (_folderSelectionMode) {
      _clearFolderSelection();
      return;
    }
    if (openedMaterial != null) {
      _closeWebView();
      return;
    }
    if (selectedSubject != null) {
      _backToSubjects();
      return;
    }
    _leaveSemester();
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'DOC':
        return Icons.description_rounded;
      case 'PPT':
        return Icons.slideshow_rounded;
      case 'XLS':
        return Icons.table_chart_rounded;
      case 'IMG':
        return Icons.image_rounded;
      case 'VID':
        return Icons.videocam_rounded;
      case 'AUD':
        return Icons.audiotrack_rounded;
      case 'FOLDER':
        return Icons.folder_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String type) {
    switch (type) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'DOC':
        return const Color(0xFF3B82F6);
      case 'PPT':
        return const Color(0xFFF59E0B);
      case 'XLS':
        return const Color(0xFF10B981);
      case 'IMG':
        return const Color(0xFF8B5CF6);
      case 'VID':
        return const Color(0xFF0EA5E9);
      case 'AUD':
        return const Color(0xFFEC4899);
      case 'FOLDER':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF6B7280);
    }
  }

  BoxDecoration _fileCardDecoration({
    required bool isDark,
    bool selected = false,
  }) {
    return BoxDecoration(
      color: selected
          ? (isDark
              ? const Color(0xFF312E81).withOpacity(0.45)
              : const Color(0xFFEEF2FF))
          : (isDark ? const Color(0xFF1F2937) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      border: selected
          ? Border.all(color: const Color(0xFF6366F1), width: 1.5)
          : null,
      boxShadow: [
        if (!isDark)
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
      ],
    );
  }

  Widget _fileTypeFallback(StudyMaterial file, {double iconSize = 24}) {
    final fileColor = _getFileColor(file.type);
    return ColoredBox(
      color: fileColor.withOpacity(0.1),
      child: Center(
        child: file.isFolder
            ? _FolderGlyph(
                color: fileColor,
                size: iconSize,
                locked: _isListedFolderLocked(file),
              )
            : Icon(
                _getFileIcon(file.type),
                color: fileColor,
                size: iconSize,
              ),
      ),
    );
  }

  Widget _filePreview(StudyMaterial file, {required double iconSize}) {
    final fallback = _fileTypeFallback(file, iconSize: iconSize);
    if (file.isFolder || !file.canLoadDriveThumbnail) {
      return fallback;
    }
    final preview = DriveThumbnail(
      fileId: file.id,
      fallback: fallback,
    );
    if (file.type != 'VID' && file.type != 'AUD') {
      return preview;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
        ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(
              file.type == 'AUD'
                  ? Icons.graphic_eq_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  void _applyListedItemAction(StudyMaterial file, String value) {
    if (value == 'select') {
      _toggleSelectedFile(file);
    } else if (value == 'open') {
      _openListedItem(file);
    } else if (value == 'info') {
      showFileDetailsDialog(
        context: context,
        info: FileDetailsInfo.fromStudyMaterial(
          file,
          folderName: selectedSubject?.name,
        ),
      );
    } else if (value == 'rename') {
      _renameMaterial(file);
    } else if (value == 'lock') {
      _lockUnitFolder(_subjectFromListedFolder(file));
    } else if (value == 'unlock') {
      _unlockUnitFolder(_subjectFromListedFolder(file));
    } else if (value == 'move') {
      if (file.isFolder) {
        _moveListedFolder(file);
      } else {
        _moveMaterial(file);
      }
    } else if (value == 'download') {
      _downloadFile(file);
    } else if (value == 'cancel') {
      _cancelDownload(file);
    } else if (value == 'delete') {
      _confirmDelete(file);
    }
  }

  void _applyUnitFolderAction(Subject subject, String value) {
    if (value == 'select') {
      _toggleSelectedUnit(subject);
    } else if (value == 'open') {
      _openUnit(subject);
    } else if (value == 'info') {
      showFileDetailsDialog(
        context: context,
        info: FileDetailsInfo.fromSubject(subject),
      );
    } else if (value == 'rename') {
      _renameUnitFolder(subject);
    } else if (value == 'lock') {
      _lockUnitFolder(subject);
    } else if (value == 'unlock') {
      _unlockUnitFolder(subject);
    } else if (value == 'move') {
      _moveUnitFolder(subject);
    } else if (value == 'delete') {
      _confirmDeleteUnitFolder(subject);
    }
  }

  Future<void> _downloadSelectedFiles() async {
    final files = _selectedFileList.where((file) => !file.isFolder).toList();
    if (files.isEmpty) {
      _showMessage('Select files to download', isError: true);
      return;
    }
    for (final file in files) {
      if (!mounted) return;
      await _downloadFile(file, notify: false);
    }
    if (!mounted) return;
    _showMessage(
      files.length == 1
          ? 'Download finished for "${files.first.name}"'
          : 'Finished downloading ${files.length} files',
    );
  }

  Future<void> _moveSelectedFiles() async {
    if (!_canManageFolders) return;
    final items = _selectedFileList;
    if (items.isEmpty) return;
    final targets = _commonMoveTargetsForFiles(items);
    if (targets.isEmpty) {
      _showMessage('No shared destination for the selection', isError: true);
      return;
    }
    final folders = items.where((item) => item.isFolder).length;
    final files = items.length - folders;
    final label = items.length == 1
        ? items.first.name
        : folders > 0 && files > 0
            ? '${items.length} items'
            : folders > 0
                ? '$folders folders'
                : '$files files';
    final destination = await showMoveFileDialog(
      context: context,
      fileName: label,
      targets: targets,
      isFolder: files == 0,
    );
    if (destination == null || !mounted) return;

    var moved = 0;
    for (final item in List<StudyMaterial>.from(items)) {
      if (!mounted) return;
      try {
        if (item.isFolder) {
          await UploadService.instance.moveFile(
            fileId: item.id,
            parentFolderId: destination.id,
          );
        } else {
          await UploadService.instance.moveFile(
            fileId: item.id,
            parentFolderId: destination.id,
          );
        }
        moved += 1;
        if (!mounted) return;
        setState(() {
          currentFiles.removeWhere((file) => file.id == item.id);
          _selectedItems.remove(item.id);
          _subtractListedItemCounts(item);
        });
      } on UploadException catch (e) {
        _showMessage(e.message, isError: true);
        return;
      } catch (_) {
        _showMessage('Failed to move "${item.name}"', isError: true);
        return;
      }
    }
    if (!mounted) return;
    _showMessage(
      destination.isMain
          ? 'Moved $moved ${moved == 1 ? 'item' : 'items'} to ${destination.name}'
          : 'Moved $moved ${moved == 1 ? 'item' : 'items'} to "${destination.name}"',
    );
  }

  Future<void> _deleteSelectedFiles() async {
    if (!_canManageFolders) return;
    final items = _selectedFileList;
    if (items.isEmpty) return;
    final folders = items.where((item) => item.isFolder).length;
    final files = items.length - folders;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            items.length == 1
                ? (items.first.isFolder ? 'Delete folder?' : 'Delete material?')
                : 'Delete ${items.length} items?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            items.length == 1
                ? (items.first.isFolder
                    ? '“${items.first.name}” and everything inside it will be permanently removed.'
                    : '“${items.first.name}” will be permanently removed from this folder.')
                : 'This will permanently delete $files ${files == 1 ? 'file' : 'files'}'
                    '${folders == 0 ? '' : ' and $folders ${folders == 1 ? 'folder' : 'folders'}'}'
                    '${folders > 0 ? ', including folder contents' : ''}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    var deleted = 0;
    for (final item in List<StudyMaterial>.from(items)) {
      if (!mounted) return;
      try {
        if (_isLiveFolder) {
          await UploadService.instance.deleteFile(item.id);
        }
        deleted += 1;
        if (!mounted) return;
        setState(() {
          currentFiles.removeWhere((file) => file.id == item.id);
          _selectedItems.remove(item.id);
          _deletingIds.remove(item.id);
          _subtractListedItemCounts(item);
        });
      } on UploadException catch (e) {
        _showMessage(e.message, isError: true);
        return;
      } catch (_) {
        _showMessage('Failed to delete ${item.name}', isError: true);
        return;
      }
    }
    if (!mounted) return;
    _showMessage('Deleted $deleted ${deleted == 1 ? 'item' : 'items'}');
  }

  Future<void> _moveSelectedUnits() async {
    if (!_canManageFolders) return;
    final items = _selectedUnitList;
    if (items.isEmpty) return;
    final targets = _commonMoveTargetsForUnits(items);
    if (targets.isEmpty) {
      _showMessage('No shared destination for the selection', isError: true);
      return;
    }
    final destination = await showMoveFileDialog(
      context: context,
      fileName: items.length == 1 ? items.first.name : '${items.length} folders',
      targets: targets,
      isFolder: true,
    );
    if (destination == null || !mounted) return;
    var moved = 0;
    for (final subject in List<Subject>.from(items)) {
      if (!mounted) return;
      try {
        await UploadService.instance.moveFile(
          fileId: subject.folderId,
          parentFolderId: destination.id,
        );
        moved += 1;
        if (!mounted) return;
        setState(() {
          subjects.removeWhere((item) => item.folderId == subject.folderId);
          _selectedUnits.remove(subject.folderId);
        });
      } on UploadException catch (e) {
        _showMessage(e.message, isError: true);
        return;
      } catch (_) {
        _showMessage('Failed to move "${subject.name}"', isError: true);
        return;
      }
    }
    if (!mounted) return;
    _showMessage('Moved $moved ${moved == 1 ? 'folder' : 'folders'} to "${destination.name}"');
  }

  Future<void> _deleteSelectedUnits() async {
    if (!_canManageFolders) return;
    final items = _selectedUnitList;
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            items.length == 1 ? 'Delete folder' : 'Delete ${items.length} folders',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            items.length == 1
                ? 'This will permanently delete "${items.first.name}" and all files inside it.'
                : 'This will permanently delete ${items.length} folders and everything inside them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    var deleted = 0;
    for (final subject in List<Subject>.from(items)) {
      if (!mounted) return;
      try {
        await UploadService.instance.deleteFile(subject.folderId);
        deleted += 1;
        if (!mounted) return;
        _selectedUnits.remove(subject.folderId);
        _removeFolder(subject);
      } on UploadException catch (e) {
        _showMessage(e.message, isError: true);
        return;
      } catch (_) {
        _showMessage('Failed to delete folder', isError: true);
        return;
      }
    }
    if (!mounted) return;
    _showMessage('Deleted $deleted ${deleted == 1 ? 'folder' : 'folders'}');
  }

  List<_ItemActionChoice> _listedItemActions(
    StudyMaterial file, {
    required bool isDownloading,
  }) {
    final itemLabel = file.isFolder ? 'folder' : 'file';
    final canMove = file.isFolder
        ? _canOfferMoveFolder(folderId: file.id, fromFiles: true)
        : _canOfferMove(file);
    final fileColor = _getFileColor(file.type);
    return [
      if (!_fileSelectionMode)
        const _ItemActionChoice(
          value: 'select',
          icon: Icons.check_circle_outline_rounded,
          label: 'Select',
          color: Color(0xFF6366F1),
        ),
      if (!isDownloading)
        _ItemActionChoice(
          value: 'open',
          icon: file.isFolder
              ? Icons.folder_open_rounded
              : Icons.open_in_new_rounded,
          label: file.isFolder ? 'Open folder' : 'Open file',
        ),
      _ItemActionChoice(
        value: 'info',
        icon: Icons.info_outline_rounded,
        label: file.isFolder ? 'Folder info' : 'File info',
        color: const Color(0xFF6366F1),
      ),
      if (!file.isFolder && isDownloading)
        const _ItemActionChoice(
          value: 'cancel',
          icon: Icons.close_rounded,
          label: 'Cancel download',
          color: Color(0xFFEF4444),
        ),
      if (!file.isFolder && !isDownloading)
        _ItemActionChoice(
          value: 'download',
          icon: Icons.download_rounded,
          label: 'Download',
          color: fileColor,
        ),
      if (_canManageFolders && !isDownloading) ...[
        _ItemActionChoice(
          value: 'rename',
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename $itemLabel',
        ),
        if (file.isFolder)
          _isListedFolderLocked(file)
              ? const _ItemActionChoice(
                  value: 'unlock',
                  icon: Icons.lock_open_rounded,
                  label: 'Unlock folder',
                  color: Color(0xFF10B981),
                )
              : const _ItemActionChoice(
                  value: 'lock',
                  icon: Icons.lock_rounded,
                  label: 'Lock folder',
                  color: Color(0xFFF59E0B),
                ),
        if (canMove)
          _ItemActionChoice(
            value: 'move',
            icon: Icons.drive_file_move_rounded,
            label: file.isFolder ? 'Move folder' : 'Move file',
            color: const Color(0xFF6366F1),
          ),
        const _ItemActionChoice(
          value: 'delete',
          icon: Icons.delete_rounded,
          label: 'Delete',
          color: Color(0xFFEF4444),
        ),
      ],
    ];
  }

  List<_ItemActionChoice> _unitFolderActions(Subject subject) {
    return [
      if (!_folderSelectionMode)
        const _ItemActionChoice(
          value: 'select',
          icon: Icons.check_circle_outline_rounded,
          label: 'Select',
          color: Color(0xFF6366F1),
        ),
      const _ItemActionChoice(
        value: 'open',
        icon: Icons.folder_open_rounded,
        label: 'Open folder',
      ),
      const _ItemActionChoice(
        value: 'info',
        icon: Icons.info_outline_rounded,
        label: 'Folder info',
        color: Color(0xFF6366F1),
      ),
      if (_canManageFolders) ...[
        if (subject.isLocked)
          const _ItemActionChoice(
            value: 'unlock',
            icon: Icons.lock_open_rounded,
            label: 'Unlock folder',
            color: Color(0xFF10B981),
          )
        else
          const _ItemActionChoice(
            value: 'lock',
            icon: Icons.lock_rounded,
            label: 'Lock folder',
            color: Color(0xFFF59E0B),
          ),
        const _ItemActionChoice(
          value: 'rename',
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename folder',
        ),
        if (_canOfferMoveFolder(folderId: subject.folderId, fromFiles: false))
          const _ItemActionChoice(
            value: 'move',
            icon: Icons.drive_file_move_rounded,
            label: 'Move folder',
            color: Color(0xFF6366F1),
          ),
        const _ItemActionChoice(
          value: 'delete',
          icon: Icons.delete_rounded,
          label: 'Delete folder',
          color: Color(0xFFEF4444),
        ),
      ],
    ];
  }

  Future<void> _showItemActionSheet({
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required Color leadingColor,
    required List<_ItemActionChoice> actions,
    required ValueChanged<String> onSelected,
  }) async {
    if (actions.isEmpty) return;
    HapticFeedback.mediumImpact();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _ItemActionSheet(
        title: title,
        subtitle: subtitle,
        leadingIcon: leadingIcon,
        leadingColor: leadingColor,
        actions: actions,
      ),
    );
    if (value == null || !mounted) return;
    onSelected(value);
  }

  Future<void> _showListedItemActions(
    StudyMaterial file, {
    required bool isDownloading,
  }) async {
    if (_deletingIds.contains(file.id) ||
        _movingIds.contains(file.id) ||
        _isMutatingFolder) {
      return;
    }
    final fileColor = _getFileColor(file.type);
    await _showItemActionSheet(
      title: file.name,
      subtitle: file.isFolder
          ? (_isListedFolderLocked(file)
              ? 'Locked · ${file.size}'
              : file.size)
          : '${file.type} • ${file.size}',
      leadingIcon: file.isFolder
          ? Icons.folder_rounded
          : _getFileIcon(file.type),
      leadingColor: fileColor,
      actions: _listedItemActions(file, isDownloading: isDownloading),
      onSelected: (value) => _applyListedItemAction(file, value),
    );
  }

  Future<void> _showUnitFolderActions(Subject subject) async {
    if (_isMutatingFolder) return;
    await _showItemActionSheet(
      title: subject.name,
      subtitle:
          '${GoogleDriveService.folderContentsLabel(fileCount: subject.fileCount, folderCount: subject.folderCount)}'
          '${subject.isLocked ? ' • Locked' : ''}',
      leadingIcon: Icons.folder_rounded,
      leadingColor: subject.color,
      actions: _unitFolderActions(subject),
      onSelected: (value) => _applyUnitFolderAction(subject, value),
    );
  }

  Widget _fileOverflowMenu(
    StudyMaterial file, {
    required bool isDownloading,
    bool onPreview = false,
  }) {
    if (_deletingIds.contains(file.id) || _movingIds.contains(file.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
      );
    }
    if (!_canManageFolders) return const SizedBox.shrink();
    if (_fileSelectionMode) return const SizedBox.shrink();
    final itemLabel = file.isFolder ? 'folder' : 'file';
    final canMove = file.isFolder
        ? _canOfferMoveFolder(folderId: file.id, fromFiles: true)
        : _canOfferMove(file);
    return PopupMenuButton<String>(
      tooltip: file.isFolder ? 'Folder options' : 'File options',
      enabled: !isDownloading && !_isMutatingFolder,
      padding: EdgeInsets.zero,
      icon: onPreview
          ? const PreviewOverlayIcon(icon: Icons.more_vert_rounded)
          : const Icon(
              Icons.more_vert_rounded,
              color: Color(0xFF6366F1),
            ),
      onSelected: (value) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          _applyListedItemAction(file, value);
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 10),
              Text('Select'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Text(file.isFolder ? 'Folder info' : 'File info'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
              const SizedBox(width: 10),
              Text('Rename $itemLabel'),
            ],
          ),
        ),
        if (file.isFolder)
          _isListedFolderLocked(file)
              ? const PopupMenuItem(
                  value: 'unlock',
                  child: Row(
                    children: [
                      Icon(Icons.lock_open_rounded, size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 10),
                      Text('Unlock folder'),
                    ],
                  ),
                )
              : const PopupMenuItem(
                  value: 'lock',
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 18, color: Color(0xFFF59E0B)),
                      SizedBox(width: 10),
                      Text('Lock folder'),
                    ],
                  ),
                ),
        if (canMove)
          PopupMenuItem(
            value: 'move',
            child: Row(
              children: [
                const Icon(Icons.drive_file_move_rounded, size: 18, color: Color(0xFF6366F1)),
                const SizedBox(width: 10),
                Text(file.isFolder ? 'Move folder' : 'Move file'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
              SizedBox(width: 10),
              Text(
                'Delete',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _downloadButton(
    StudyMaterial file, {
    required bool isDownloading,
    bool onPreview = false,
  }) {
    if (file.isFolder) return const SizedBox.shrink();
    final fileColor = _getFileColor(file.type);
    if (isDownloading) {
      return IconButton(
        icon: onPreview
            ? const PreviewOverlayIcon(
                icon: Icons.close_rounded,
                destructive: true,
              )
            : const Icon(Icons.close_rounded),
        color: const Color(0xFFEF4444),
        onPressed: () => _cancelDownload(file),
        tooltip: 'Cancel download',
      );
    }
    return IconButton(
      icon: onPreview
          ? const PreviewOverlayIcon(icon: Icons.download_rounded)
          : Icon(
              Icons.download_rounded,
              color: fileColor,
            ),
      onPressed: () => _downloadFile(file),
      tooltip: 'Download',
    );
  }

  Widget _buildDetailsFileList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return ListView.builder(
      padding: AdaptiveLayout.pagePadding(context).copyWith(
        top: 12,
        bottom: AdaptiveLayout.bottomClearance(context) +
            (_fileSelectionMode ? 96 : 0),
      ),
      itemCount: _visibleFiles.length,
      itemBuilder: (context, index) {
        final file = _visibleFiles[index];
        final fileColor = _getFileColor(file.type);
        final isDownloading = downloadingFiles[file.id] ?? false;
        final progress = downloadProgress[file.id] ?? 0.0;
        final selected = _selectedItems.containsKey(file.id);

        return Container(
          key: ValueKey(file.id),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: _fileCardDecoration(isDark: isDark, selected: selected),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onListedItemTap(
                file,
                isDownloading: isDownloading,
              ),
              onLongPress: () => _onListedItemLongPress(file),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF6366F1)
                            : fileColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 24,
                            )
                          : file.isFolder
                              ? _FolderGlyph(
                                  color: fileColor,
                                  size: 40,
                                  locked: _isListedFolderLocked(file),
                                )
                              : Icon(
                                  _getFileIcon(file.type),
                                  color: fileColor,
                                  size: 24,
                                ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (isDownloading)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: isDark
                                      ? const Color(0xFF374151)
                                      : const Color(0xFFE5E7EB),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(fileColor),
                                  minHeight: 3,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Downloading ${(progress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: fileColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              file.isFolder
                                  ? (_isListedFolderLocked(file)
                                      ? 'Locked · ${GoogleDriveService.folderContentsLabel(fileCount: file.fileCount, folderCount: file.folderCount)}'
                                      : GoogleDriveService.folderContentsLabel(
                                          fileCount: file.fileCount,
                                          folderCount: file.folderCount,
                                        ))
                                  : '${file.type} • ${file.size} • ${file.date}',
                              style: TextStyle(
                                fontSize: 13,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_fileSelectionMode)
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF9CA3AF),
                      )
                    else ...[
                      _fileOverflowMenu(file, isDownloading: isDownloading),
                      _downloadButton(file, isDownloading: isDownloading),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: muted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLargeIconsGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = AdaptiveLayout.gridCount(constraints.maxWidth);
        return GridView.builder(
          padding: AdaptiveLayout.pagePadding(context).copyWith(
        top: 12,
        bottom: AdaptiveLayout.bottomClearance(context) +
            (_fileSelectionMode ? 96 : 0),
      ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: _visibleFiles.length,
          itemBuilder: (context, index) {
            final file = _visibleFiles[index];
            final isDownloading = downloadingFiles[file.id] ?? false;
            final progress = downloadProgress[file.id] ?? 0.0;
            final selected = _selectedItems.containsKey(file.id);

            return Container(
              key: ValueKey(file.id),
              decoration: _fileCardDecoration(isDark: isDark, selected: selected),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onListedItemTap(
                    file,
                    isDownloading: isDownloading,
                  ),
                  onLongPress: () => _onListedItemLongPress(file),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: _filePreview(file, iconSize: 56),
                            ),
                            if (isDownloading)
                              ColoredBox(
                                color: Colors.black.withOpacity(0.35),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: CircularProgressIndicator(
                                          value: progress > 0 ? progress : null,
                                          strokeWidth: 3,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                  Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${(progress * 100).toInt()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_fileSelectionMode)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: selected
                                      ? const Color(0xFF6366F1)
                                      : Colors.white,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              Positioned(
                                top: 0,
                                right: 0,
                                child: _fileOverflowMenu(
                                  file,
                                  isDownloading: isDownloading,
                                  onPreview: true,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: _downloadButton(
                                  file,
                                  isDownloading: isDownloading,
                                  onPreview: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Column(
                          children: [
                            Text(
                              file.name,
                              textAlign: TextAlign.center,
                              maxLines: file.isFolder ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                            if (file.isFolder) ...[
                              const SizedBox(height: 3),
                              Text(
                                GoogleDriveService.folderContentsLabel(
                                  fileCount: file.fileCount,
                                  folderCount: file.folderCount,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fileSelectionMode &&
          !_folderSelectionMode &&
          widget.onBack == null &&
          selectedSubject == null &&
          openedMaterial == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onSystemBack();
      },
      child: openedMaterial != null
          ? (UploadService.isPlayableMediaType(openedMaterial!.type)
              ? MediaPlayerScreen(
                  key: ValueKey(openedMaterial!.id),
                  fileId: openedMaterial!.id,
                  title: openedMaterial!.name,
                  isAudio: openedMaterial!.type == 'AUD',
                  subject: selectedSubject?.name ?? 'Unknown',
                  onBack: _closeWebView,
                )
              : WebViewScreen(
                  key: ValueKey(openedMaterial!.id),
                  url: openedMaterial!.downloadUrl!,
                  title: openedMaterial!.name,
                  subject: selectedSubject?.name ?? 'Unknown',
                  onBack: _closeWebView,
                ))
          : selectedSubject != null
              ? _buildFilesView()
              : _buildSubjectsView(),
    );
  }

  /// Parent [MainScreen] uses [Scaffold.extendBody], and nested Scaffolds
  /// ignore [MediaQuery] padding for FAB placement (they use keyboard
  /// [viewInsets] instead). Offset the FAB so it sits above the app nav.
  double get _fabNavLift {
    return MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight +
        28;
  }

  Widget _fabAboveNav(Widget fab) {
    return Padding(
      padding: EdgeInsets.only(bottom: _fabNavLift),
      child: fab,
    );
  }

  Widget _buildSelectionBar({
    required bool isDark,
    required int count,
    VoidCallback? onDownload,
    VoidCallback? onMove,
    VoidCallback? onDelete,
    VoidCallback? onMore,
  }) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final actions = <Widget>[
      if (onDownload != null)
        _selectionBarAction(
          icon: Icons.download_rounded,
          label: 'Download',
          color: const Color(0xFF6366F1),
          onTap: onDownload,
        ),
      if (onMove != null)
        _selectionBarAction(
          icon: Icons.drive_file_move_rounded,
          label: 'Move',
          color: const Color(0xFF6366F1),
          onTap: onMove,
        ),
      if (onMore != null)
        _selectionBarAction(
          icon: Icons.more_horiz_rounded,
          label: 'More',
          color: const Color(0xFF6B7280),
          onTap: onMore,
        ),
      if (onDelete != null)
        _selectionBarAction(
          icon: Icons.delete_rounded,
          label: count == 1 ? 'Delete' : 'Delete $count',
          color: const Color(0xFFEF4444),
          onTap: onDelete,
        ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, _fabNavLift - 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 28,
                  color: isDark
                      ? const Color(0xFF374151)
                      : const Color(0xFFE5E7EB),
                ),
              Expanded(child: actions[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectionBarAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final visibleFiles = _visibleFiles;
    final folderCount = _listedFolderCount;
    final fileCount = _nestedFileCount;
    final matchCount = visibleFiles.length;
    final itemCountLabel = GoogleDriveService.folderContentsLabel(
      fileCount: fileCount,
      folderCount: folderCount,
    );
    final isFiltering =
        _fileQuery.trim().isNotEmpty || _fileTypeFilter != 'All';
    final totalListed = folderCount + fileCount;
    final countLabel = isFiltering
        ? '$matchCount of $totalListed'
        : itemCountLabel;

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: _fileSelectionMode
          ? _buildSelectionBar(
              isDark: isDark,
              count: _selectedItems.length,
              onDownload: _selectedFileList.any((file) => !file.isFolder)
                  ? _downloadSelectedFiles
                  : null,
              onMove: _canManageFolders &&
                      _commonMoveTargetsForFiles(_selectedFileList).isNotEmpty
                  ? _moveSelectedFiles
                  : null,
              onDelete: _canManageFolders ? _deleteSelectedFiles : null,
              onMore: _selectedItems.length == 1
                  ? () {
                      final file = _selectedFileList.first;
                      _showListedItemActions(
                        file,
                        isDownloading: downloadingFiles[file.id] ?? false,
                      );
                    }
                  : null,
            )
          : null,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: titleColor,
        elevation: 0,
        toolbarHeight: 52,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            _fileSelectionMode
                ? Icons.close_rounded
                : Icons.arrow_back_rounded,
          ),
          onPressed:
              _fileSelectionMode ? _clearFileSelection : _backToSubjects,
        ),
        title: _fileSelectionMode
            ? Text(
                '${_selectedItems.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: titleColor,
                ),
              )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    selectedSubject!.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: titleColor,
                    ),
                  ),
                ),
                if (selectedSubject!.isLocked) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                ],
              ],
            ),
            Text(
              selectedSubject!.code,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: muted,
              ),
            ),
          ],
        ),
        actions: [
          if (_fileSelectionMode)
            IconButton(
              tooltip: _selectedItems.length == visibleFiles.length
                  ? 'Deselect all'
                  : 'Select all',
              icon: Icon(
                _selectedItems.length == visibleFiles.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: _selectAllVisibleFiles,
            )
          else ...[
            if (_isLiveFolder &&
                _canManageFolders &&
                selectedSubject!.folderId.isNotEmpty)
              IconButton(
                tooltip: 'New folder',
                icon: _isMutatingFolder
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                        ),
                      )
                    : const Icon(Icons.create_new_folder_rounded),
                onPressed: _isMutatingFolder ? null : _createNestedFolder,
              ),
            IconButton(
              tooltip: 'Sort · ${_fileSort.label}',
              icon: const Icon(Icons.sort_rounded),
              onPressed: _openFileSort,
            ),
            IconButton(
              tooltip: _useLargeIcons ? 'Details view' : 'Large icons',
              icon: Icon(
                _useLargeIcons
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
              onPressed: _toggleFilesView,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: isUploading
                  ? null
                  : () => _loadSubjectFiles(selectedSubject!),
            ),
          ],
        ],
      ),
      floatingActionButton: !_fileSelectionMode &&
              _isLiveFolder &&
              _canManageFolders &&
              selectedSubject!.folderId.isNotEmpty
          ? _fabAboveNav(
              IgnorePointer(
                ignoring: _fileSearchFocus.hasFocus,
                child: AnimatedOpacity(
                  opacity: _fileSearchFocus.hasFocus ? 0 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: FloatingActionButton.extended(
                onPressed: isUploading ? null : _pickAndUploadFile,
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                icon: isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(isUploading ? 'Uploading...' : 'Upload file'),
              ),
                ),
              ),
            )
          : null,
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Column(
        children: [
          if (isUploading)
            ListenableBuilder(
              listenable: _uploadSession,
              builder: (context, _) {
                final value = _uploadSession.overallProgress;
                return LinearProgressIndicator(
                  value: value > 0 ? value : null,
                  backgroundColor: isDark
                      ? const Color(0xFF374151)
                      : const Color(0xFFE5E7EB),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  minHeight: 3,
                );
              },
            ),
          if (!isLoadingFiles && currentFiles.isNotEmpty)
            _buildFolderFileSearch(
              isDark: isDark,
              muted: muted,
              countLabel: countLabel,
            ),
          Expanded(
            child: isLoadingFiles
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6366F1),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading files...',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : currentFiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No files found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This folder is empty',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                            if (_isLiveFolder &&
                                _canManageFolders &&
                                selectedSubject!.folderId.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _isMutatingFolder
                                    ? null
                                    : _createNestedFolder,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                ),
                                icon: const Icon(
                                  Icons.create_new_folder_rounded,
                                ),
                                label: const Text('New folder'),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed:
                                    isUploading ? null : _pickAndUploadFile,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                ),
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text('Upload file'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF6366F1),
                        onRefresh: () =>
                            _loadSubjectFiles(selectedSubject!),
                        child: visibleFiles.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.sizeOf(context)
                                            .height *
                                        0.28,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 56,
                                            color: muted,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No matching files',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: titleColor,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _fileQuery.trim().isEmpty
                                                ? 'Try a different filter'
                                                : 'Nothing matches “${_fileQuery.trim()}”',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _useLargeIcons
                                ? _buildLargeIconsGrid()
                                : _buildDetailsFileList(),
                      ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildFolderFileSearch({
    required bool isDark,
    required Color muted,
    required String countLabel,
  }) {
    const accent = Color(0xFF818CF8);
    final fieldFill =
        isDark ? const Color(0xFF1F2937) : const Color(0xFFEEF2F6);
    final chipFill =
        isDark ? const Color(0xFF1F2937) : Colors.white;
    final chipBorder = isDark
        ? const Color(0xFF374151)
        : const Color(0xFFE5E7EB);
    final highlighted = _fileSearchFocus.hasFocus || _fileQuery.isNotEmpty;
    final pagePad = AdaptiveLayout.pagePadding(context);

    return Padding(
      padding: pagePad.copyWith(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _fileSearchController,
            focusNode: _fileSearchFocus,
            onChanged: (value) => setState(() => _fileQuery = value),
            onTapOutside: (_) => _fileSearchFocus.unfocus(),
            textInputAction: TextInputAction.search,
            style: TextStyle(
              color: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'Search notes, slides, labs...',
              hintStyle: TextStyle(color: muted, fontSize: 15),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: highlighted ? accent : muted,
              ),
              suffixIcon: _fileQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _fileSearchController.clear();
                        setState(() => _fileQuery = '');
                      },
                      icon: Icon(Icons.close_rounded, color: muted),
                    ),
              filled: true,
              fillColor: fieldFill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(
                  color: highlighted
                      ? accent
                      : (isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFD1D5DB)),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: accent, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in _fileTypeFilters)
                _fileFilterChip(
                  label,
                  selected: _fileTypeFilter == label,
                  fill: chipFill,
                  border: chipBorder,
                  muted: muted,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            countLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileFilterChip(
    String label, {
    required bool selected,
    required Color fill,
    required Color border,
    required Color muted,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _fileTypeFilter = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF7C83F8) : fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF7C83F8) : border,
          ),
        ),
        child: Text(
          switch (label) {
            'VID' => 'Video',
            'AUD' => 'Audio',
            _ => label,
          },
          style: TextStyle(
            color: selected ? Colors.white : muted,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectsView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    const accent = Color(0xFF818CF8);
    final fieldFill =
        isDark ? const Color(0xFF1F2937) : const Color(0xFFEEF2F6);
    final unitSearchHighlighted =
        _unitSearchFocus.hasFocus || _unitQuery.isNotEmpty;
    final visible = _visibleUnits;
    final totalFiles = _totalUnitFiles;
    final pagePad = AdaptiveLayout.pagePadding(context);
    final bottomPad = AdaptiveLayout.bottomClearance(context) +
        (_folderSelectionMode ? 96 : 0);
    final tablet = AdaptiveLayout.isTablet(context);

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: _folderSelectionMode
          ? _buildSelectionBar(
              isDark: isDark,
              count: _selectedUnits.length,
              onMove: _canManageFolders &&
                      _commonMoveTargetsForUnits(_selectedUnitList).isNotEmpty
                  ? _moveSelectedUnits
                  : null,
              onDelete: _canManageFolders ? _deleteSelectedUnits : null,
              onMore: _selectedUnits.length == 1
                  ? () => _showUnitFolderActions(_selectedUnitList.first)
                  : null,
            )
          : null,
      floatingActionButton: !_folderSelectionMode &&
              _isLiveFolder &&
              _canManageFolders
          ? _fabAboveNav(
              IgnorePointer(
                ignoring: _unitSearchFocus.hasFocus,
                child: AnimatedOpacity(
                  opacity: _unitSearchFocus.hasFocus ? 0 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: FloatingActionButton.extended(
                    onPressed: _isMutatingFolder ? null : _createUnitFolder,
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    icon: _isMutatingFolder
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.create_new_folder_rounded),
                    label: Text(_isMutatingFolder ? 'Working...' : 'New folder'),
                  ),
                ),
              ),
            )
          : null,
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: RefreshIndicator(
        color: const Color(0xFF6366F1),
        onRefresh: _folderSelectionMode ? () async {} : _refreshSubjects,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            compactSliverAppBar(
              backgroundColor: background,
              foregroundColor: titleColor,
              leading: IconButton(
                icon: Icon(
                  _folderSelectionMode
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                ),
                onPressed: _folderSelectionMode
                    ? _clearFolderSelection
                    : _leaveSemester,
              ),
              title: Text(
                _folderSelectionMode
                    ? '${_selectedUnits.length} selected'
                    : widget.workspaceName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: tablet ? 22 : 18,
                  color: titleColor,
                ),
              ),
              actions: [
                if (_folderSelectionMode)
                  IconButton(
                    tooltip: _selectedUnits.length == visible.length
                        ? 'Deselect all'
                        : 'Select all',
                    icon: Icon(
                      _selectedUnits.length == visible.length
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    onPressed: _selectAllVisibleUnits,
                  )
                else ...[
                  if (!isLoading && subjects.isNotEmpty) ...[
                    IconButton(
                      tooltip:
                          'Sort · ${_folderSort.labelFor(FileSortKind.folders)}',
                      icon: const Icon(Icons.sort_rounded),
                      onPressed: _openFolderSort,
                    ),
                    IconButton(
                      tooltip: _unitsAsGrid ? 'List view' : 'Grid view',
                      icon: Icon(
                        _unitsAsGrid
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                      ),
                      onPressed: _toggleUnitsView,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _isMutatingFolder ? null : _refreshSubjects,
                    tooltip: 'Refresh',
                  ),
                ],
              ],
            ),
            SliverPadding(
              padding: pagePad.copyWith(top: 4, bottom: 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading
                          ? 'Loading folders'
                          : '${_totalUnitFolders} ${_totalUnitFolders == 1 ? 'folder' : 'folders'}  ·  $totalFiles ${totalFiles == 1 ? 'file' : 'files'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                    if (subjects.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _unitSearchController,
                        focusNode: _unitSearchFocus,
                        onChanged: (value) {
                          setState(() {
                            _unitQuery = value;
                          });
                        },
                        onTapOutside: (_) => _unitSearchFocus.unfocus(),
                        textInputAction: TextInputAction.search,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFF9FAFB)
                              : const Color(0xFF111827),
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search folders',
                          hintStyle: TextStyle(color: muted, fontSize: 15),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: unitSearchHighlighted ? accent : muted,
                          ),
                          suffixIcon: _unitQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _unitSearchController.clear();
                                    setState(() {
                                      _unitQuery = '';
                                    });
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: muted,
                                  ),
                                ),
                          filled: true,
                          fillColor: fieldFill,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide(
                              color: unitSearchHighlighted
                                  ? accent
                                  : (isDark
                                      ? const Color(0xFF374151)
                                      : const Color(0xFFD1D5DB)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: const BorderSide(
                              color: accent,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF3F1F1F)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF6366F1),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading folders...',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (subjects.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _UnitsEmptyState(
                  canCreate: _isLiveFolder && _canManageFolders,
                  isBusy: _isMutatingFolder,
                  onCreate: _createUnitFolder,
                ),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No folders match “$_unitQuery”',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ),
              )
            else if (_unitsAsGrid)
              SliverPadding(
                padding: pagePad.copyWith(top: 8, bottom: bottomPad),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount =
                        AdaptiveLayout.gridCount(constraints.crossAxisExtent);
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: tablet ? 1.05 : 0.86,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final subject = visible[index];
                          return _UnitFolderTile(
                            subject: subject,
                            isDark: isDark,
                            compact: false,
                            selected:
                                _selectedUnits.containsKey(subject.folderId),
                            selectionMode: _folderSelectionMode,
                            menu: _unitFolderMenu(subject),
                            onTap: () => _onUnitTap(subject),
                            onLongPress: () => _onUnitLongPress(subject),
                          );
                        },
                        childCount: visible.length,
                      ),
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: pagePad.copyWith(top: 8, bottom: bottomPad),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = AdaptiveLayout.listColumns(
                      constraints.crossAxisExtent,
                    );
                    Widget tile(int index, {required bool tight}) {
                      final subject = visible[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: tight ? 0 : 10),
                        child: _UnitFolderTile(
                          subject: subject,
                          isDark: isDark,
                          compact: true,
                          selected:
                              _selectedUnits.containsKey(subject.folderId),
                          selectionMode: _folderSelectionMode,
                          menu: _unitFolderMenu(subject),
                          onTap: () => _onUnitTap(subject),
                          onLongPress: () => _onUnitLongPress(subject),
                        ),
                      );
                    }

                    if (columns == 1) {
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => tile(index, tight: false),
                          childCount: visible.length,
                        ),
                      );
                    }

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 78,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => tile(index, tight: true),
                        childCount: visible.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget? _unitFolderMenu(Subject subject) {
    if (!_isLiveFolder) return null;
    if (_folderSelectionMode) return null;
    return PopupMenuButton<String>(
      tooltip: 'Folder options',
      enabled: !_isMutatingFolder,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_horiz_rounded,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF9CA3AF)
            : const Color(0xFF6B7280),
      ),
      onSelected: (value) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          _applyUnitFolderAction(subject, value);
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 10),
              Text('Select'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 10),
              Text('Folder info'),
            ],
          ),
        ),
        if (_canManageFolders) ...[
          if (subject.isLocked)
            const PopupMenuItem(
              value: 'unlock',
              child: Row(
                children: [
                  Icon(Icons.lock_open_rounded, size: 18, color: Color(0xFF10B981)),
                  SizedBox(width: 10),
                  Text('Unlock folder'),
                ],
              ),
            )
          else
            const PopupMenuItem(
              value: 'lock',
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 18, color: Color(0xFFF59E0B)),
                  SizedBox(width: 10),
                  Text('Lock folder'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                SizedBox(width: 10),
                Text('Rename folder'),
              ],
            ),
          ),
          if (_canOfferMoveFolder(folderId: subject.folderId, fromFiles: false))
            const PopupMenuItem(
              value: 'move',
              child: Row(
                children: [
                  Icon(Icons.drive_file_move_rounded, size: 18, color: Color(0xFF6366F1)),
                  SizedBox(width: 10),
                  Text('Move folder'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_rounded,
                  size: 18,
                  color: Color(0xFFEF4444),
                ),
                SizedBox(width: 10),
                Text(
                  'Delete folder',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _UnitsEmptyState extends StatelessWidget {
  const _UnitsEmptyState({
    required this.canCreate,
    required this.isBusy,
    required this.onCreate,
  });

  final bool canCreate;
  final bool isBusy;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 40,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No folders yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              canCreate
                  ? 'Create a folder to start collecting materials.'
                  : 'Folders will show up here once they are added.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
              ),
            ),
            if (canCreate) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: isBusy ? null : onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                ),
                icon: const Icon(Icons.create_new_folder_rounded),
                label: const Text('New folder'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnitFolderTile extends StatelessWidget {
  const _UnitFolderTile({
    required this.subject,
    required this.isDark,
    required this.compact,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    this.menu,
  });

  final Subject subject;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final title = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final filesLabel = GoogleDriveService.folderContentsLabel(
      fileCount: subject.fileCount,
      folderCount: subject.folderCount,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? const Color(0xFF312E81).withOpacity(0.45)
                    : const Color(0xFFEEF2FF))
                : card,
            borderRadius: BorderRadius.circular(22),
            border: selected
                ? Border.all(color: const Color(0xFF6366F1), width: 1.5)
                : null,
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: compact
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      _FolderGlyph(
                        color: subject.color,
                        size: 46,
                        locked: subject.isLocked,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: title,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              filesLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selectionMode)
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: selected
                              ? const Color(0xFF6366F1)
                              : const Color(0xFF9CA3AF),
                        )
                      else ...[
                        if (menu != null) menu!,
                        Icon(Icons.chevron_right_rounded, color: muted),
                      ],
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _FolderGlyph(
                            color: subject.color,
                            size: 54,
                            locked: subject.isLocked,
                          ),
                          const Spacer(),
                          if (selectionMode)
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFF9CA3AF),
                            )
                          else if (menu != null)
                            menu!,
                        ],
                      ),
                      const Spacer(),
                      Text(
                        subject.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: title,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        filesLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: subject.color,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _FolderGlyph extends StatelessWidget {
  const _FolderGlyph({
    required this.color,
    required this.size,
    this.locked = false,
  });

  final Color color;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(5, 6),
            child: Container(
              width: size * 0.62,
              height: size * 0.48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.22),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Icon(Icons.folder_rounded, color: color, size: size * 0.78),
          if (locked)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.38,
                height: size * 0.38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: size * 0.22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _UploadSource { photos, documents, videos, audio }

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Upload from',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose photos, documents, videos, or audio on this phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            _UploadSourceOption(
              icon: Icons.photo_library_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Photos & images',
              subtitle: 'Same picker as profile photo',
              onTap: () => Navigator.pop(context, _UploadSource.photos),
            ),
            const SizedBox(height: 10),
            _UploadSourceOption(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: const Color(0xFFE25A45),
              title: 'PDF & documents',
              subtitle: 'Search recent PDFs, Word, Excel, and PowerPoint',
              onTap: () => Navigator.pop(context, _UploadSource.documents),
            ),
            const SizedBox(height: 10),
            _UploadSourceOption(
              icon: Icons.videocam_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Videos',
              subtitle: 'Same gallery picker as photos, videos only',
              onTap: () => Navigator.pop(context, _UploadSource.videos),
            ),
            const SizedBox(height: 10),
            _UploadSourceOption(
              icon: Icons.audiotrack_rounded,
              iconColor: const Color(0xFFEC4899),
              title: 'Audio',
              subtitle: 'Search music, recordings, and voice notes on this phone',
              onTap: () => Navigator.pop(context, _UploadSource.audio),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadSourceOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _UploadSourceOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A3344),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initial;
  final String fieldLabel;
  final String? helperText;
  final List<String> takenNames;
  final String takenError;
  final bool clashAsFile;
  final String? extensionFrom;

  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initial = '',
    this.fieldLabel = 'Folder name',
    this.helperText,
    this.takenNames = const [],
    this.takenError = 'A folder with that name already exists',
    this.clashAsFile = false,
    this.extensionFrom,
  });

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isTaken(String typed) {
    final name = widget.extensionFrom == null
        ? typed.trim()
        : GoogleDriveService.fileNameWithExtension(typed, widget.extensionFrom!);
    final clash = widget.clashAsFile
        ? GoogleDriveService.fileNamesClash
        : GoogleDriveService.folderNamesClash;
    return widget.takenNames.any((taken) => clash(taken, name));
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_isTaken(name)) {
      setState(() {
        _error = widget.takenError;
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: '',
          labelText: widget.fieldLabel,
          helperText: widget.helperText,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) {
            setState(() {
              _error = null;
            });
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _UploadProgressSession extends ChangeNotifier {
  static const double _sendShare = 0.85;

  bool cancelling = false;
  int index = 0;
  int total = 0;
  int completed = 0;
  String fileName = '';
  int fileBytes = 0;
  int sentBytes = 0;
  double fileProgress = 0;
  bool awaitingServer = false;
  bool _disposed = false;

  double get overallProgress {
    if (total <= 0) return 0;
    return ((completed + fileProgress) / total).clamp(0.0, 1.0);
  }

  void start(int count) {
    cancelling = false;
    index = 0;
    total = count;
    completed = 0;
    fileName = '';
    fileBytes = 0;
    sentBytes = 0;
    fileProgress = 0;
    awaitingServer = false;
    _notify();
  }

  void beginFile(String name, int size, int fileIndex) {
    index = fileIndex;
    fileName = name;
    fileBytes = size;
    sentBytes = 0;
    fileProgress = 0;
    awaitingServer = false;
    _notify();
  }

  void updateFileProgress(double progress) {
    final send = progress.clamp(0.0, 1.0);
    final next = send >= 1.0 ? _sendShare : send * _sendShare;
    final becameAwaiting = send >= 1.0 && !awaitingServer;
    awaitingServer = send >= 1.0;
    final prevPct = (fileProgress * 100).floor();
    final nextPct = (next * 100).floor();
    fileProgress = next;
    if (nextPct == prevPct && !becameAwaiting) return;
    _notify();
  }

  void updateBytes(int sent, int totalBytes) {
    final previous = sentBytes;
    final cap = fileBytes > 0 ? fileBytes : (totalBytes > 0 ? totalBytes : sent);
    sentBytes = sent.clamp(0, cap);
    final step = cap > 0 ? (cap / 100).clamp(4096, 256 * 1024) : 32768;
    if ((sentBytes - previous).abs() < step && sentBytes != cap) return;
    _notify();
  }

  void markCompleted() {
    completed++;
    fileProgress = 0;
    sentBytes = fileBytes;
    awaitingServer = false;
    _notify();
  }

  void markCancelling() {
    cancelling = true;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _UploadProgressDialog extends StatelessWidget {
  const _UploadProgressDialog({
    required this.session,
    required this.onCancel,
  });

  final _UploadProgressSession session;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overall = session.overallProgress;
    final percent = (overall * 100).clamp(0, 100).round();
    final currentNumber = session.total == 0 ? 0 : session.index + 1;
    final sizeLabel = _formatUploadBytes(
      session.fileBytes > 0 ? session.fileBytes : session.sentBytes,
    );
    final sentLabel = session.sentBytes > 0
        ? _formatUploadBytes(session.sentBytes)
        : '0B';
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !session.cancelling) onCancel();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_rounded,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.total == 1
                              ? 'Uploading file'
                              : 'Uploading files',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.cancelling
                              ? 'Stopping upload...'
                              : '${session.completed} of ${session.total} complete',
                          style: TextStyle(
                            fontSize: 13,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                session.fileName.isEmpty ? 'Preparing…' : session.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                session.total == 0
                    ? sizeLabel
                    : 'File $currentNumber of ${session.total}  ·  $sentLabel of $sizeLabel',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: session.fileName.isEmpty && overall == 0
                      ? null
                      : overall,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? const Color(0xFF374151)
                      : const Color(0xFFE5E7EB),
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: session.cancelling
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          'Cancelling…',
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                        ),
                        child: const Text(
                          'Cancel upload',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemActionChoice {
  const _ItemActionChoice({
    required this.value,
    required this.icon,
    required this.label,
    this.color,
  });

  final String value;
  final IconData icon;
  final String label;
  final Color? color;
}

class _ItemActionSheet extends StatelessWidget {
  const _ItemActionSheet({
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.leadingColor,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final Color leadingColor;
  final List<_ItemActionChoice> actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF151B28) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: leadingColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(leadingIcon, color: leadingColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: actions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      final color = action.color ?? titleColor;
                      return Material(
                        color: card,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => Navigator.pop(context, action.value),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Icon(action.icon, size: 20, color: color),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    action.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatUploadBytes(int bytes) {
  if (bytes <= 0) return '0B';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}