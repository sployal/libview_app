import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/google_drive_service.dart';
import '../services/download_service.dart';
import '../services/phone_document_service.dart';
import '../services/upload_service.dart';
import '../ui/adaptive_layout.dart';
import 'no_internet_screen.dart';
import 'phone_pdf.dart';
import 'web_view_screen.dart';

class SemesterDetailScreen extends StatefulWidget {
  final String semesterName;
  final String? folderId;
  final VoidCallback? onBack;

  const SemesterDetailScreen({
    super.key,
    this.semesterName = 'Semester',
    this.folderId,
    this.onBack,
  });

  @override
  State<SemesterDetailScreen> createState() => _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends State<SemesterDetailScreen> {
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
  bool isUploading = false;
  double uploadProgress = 0.0;
  bool _isMutatingFolder = false;
  String _role = 'student';
  bool _useLargeIcons = false;
  bool _unitsAsGrid = true;
  String _unitQuery = '';
  final TextEditingController _unitSearchController = TextEditingController();
  final FocusNode _unitSearchFocus = FocusNode();
  String _fileQuery = '';
  String _fileTypeFilter = 'All';
  final TextEditingController _fileSearchController = TextEditingController();
  final FocusNode _fileSearchFocus = FocusNode();
  static const _fileTypeFilters = ['All', 'PDF', 'DOC', 'PPT', 'IMG'];
  static const _filesViewPrefKey = 'semester_files_view_large_icons';
  static const _unitsViewPrefKey = 'semester_units_view_grid';

  bool get _canManageFolders => _role != 'student';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
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
      _useLargeIcons = prefs.getBool(_filesViewPrefKey) ?? false;
      _unitsAsGrid = prefs.getBool(_unitsViewPrefKey) ?? true;
    });
  }

  @override
  void dispose() {
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
    final sorted = [...subjects]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (query.isEmpty) return sorted;
    return sorted.where((subject) {
      return subject.name.toLowerCase().contains(query) ||
          subject.code.toLowerCase().contains(query);
    }).toList();
  }

  int get _totalUnitFiles =>
      subjects.fold(0, (sum, subject) => sum + subject.fileCount);

  List<StudyMaterial> get _visibleFiles {
    final query = _fileQuery.trim().toLowerCase();
    return currentFiles.where((file) {
      if (_fileTypeFilter != 'All' && file.type != _fileTypeFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return file.name.toLowerCase().contains(query);
    }).toList();
  }

  void _resetFileSearch() {
    _fileSearchController.clear();
    _fileQuery = '';
    _fileTypeFilter = 'All';
  }

  void _openUnit(Subject subject) {
    HapticFeedback.lightImpact();
    _loadSubjectFiles(subject);
  }

  Future<void> _loadUserRole() async {
    final role = await AuthService.instance.currentRole();
    if (!mounted) return;
    setState(() {
      _role = role;
    });
  }

  Future<void> _refreshSubjects() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    await _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (widget.folderId != null && widget.folderId!.isNotEmpty) {
        final loadedSubjects = await GoogleDriveService.getSubjectsFromFolder(widget.folderId!);
        setState(() {
          subjects = loadedSubjects;
          isLoading = false;
        });
      } else {
        setState(() {
          subjects = _getSampleSubjects();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load units. Please check your internet connection.';
        subjects = GoogleDriveService.getFallbackSubjects();
        isLoading = false;
      });
    }
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

  Future<void> _loadSubjectFiles(Subject subject) async {
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This unit is not connected to database'),
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
      _resetFileSearch();
    });

    try {
      final files = await GoogleDriveService.getSubjectFiles(subject.folderId);
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
  Future<void> _downloadFile(StudyMaterial material) async {
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
        setState(() {
          downloadProgress[material.id] = progress;
        });
      },
    );

    setState(() {
      downloadingFiles[material.id] = false;
      downloadProgress.remove(material.id);
    });

    // Show result to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
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
              : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: Duration(seconds: result.success ? 3 : 5),
        ),
      );
    }
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
          title: const Text(
            'Delete material?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            '“${material.name}” will be permanently removed from this unit.',
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
      title: 'Rename file',
      confirmLabel: 'Rename',
      initial: _fileStem(material.name),
      fieldLabel: 'File name',
    );
    if (name == null) return;

    final nextName = _fileNameWithExtension(name, material.name);
    if (nextName == material.name) return;

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
          currentFiles[index] = StudyMaterial(
            id: existing.id,
            name: savedName,
            type: existing.type,
            size: existing.size,
            date: existing.date,
            downloadUrl: existing.downloadUrl,
            thumbnailUrl: existing.thumbnailUrl,
          );
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
        if (selectedSubject != null && selectedSubject!.fileCount > 0) {
          selectedSubject!.fileCount -= 1;
        }
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

  Future<String?> _promptFolderName({
    required String title,
    required String confirmLabel,
    String initial = '',
    String fieldLabel = 'Folder name',
    String? helperText,
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
      _showMessage('This semester is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Create unit folder',
      confirmLabel: 'Create',
    );
    if (name == null) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.createFolder(
        parentFolderId: widget.folderId!,
        name: name,
      );
      if (!mounted) return;
      _showMessage('Created "$name"');
      await _loadSubjects();
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

  Future<void> _renameUnitFolder(Subject subject) async {
    if (!_canManageFolders) return;
    if (!_isLiveFolder || subject.folderId.isEmpty) {
      _showMessage('This unit is not connected to Drive', isError: true);
      return;
    }
    if (_isMutatingFolder) return;

    final name = await _promptFolderName(
      title: 'Rename folder',
      confirmLabel: 'Rename',
      initial: subject.name,
    );
    if (name == null || name == subject.name) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.renameFile(
        fileId: subject.folderId,
        name: name,
      );
      if (!mounted) return;
      _showMessage('Renamed to "$name"');
      await _loadSubjects();
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
      _showMessage('This unit is not connected to Drive', isError: true);
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

  Future<void> _deleteUnitFolder(Subject subject) async {
    if (_isMutatingFolder) return;

    setState(() {
      _isMutatingFolder = true;
    });

    try {
      await UploadService.instance.deleteFile(subject.folderId);
      if (!mounted) return;
      _showMessage('Deleted "${subject.name}"');
      await _loadSubjects();
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
      _showMessage('Open a live unit before uploading', isError: true);
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

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Choose a photo',
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    await _uploadPickedFile(
      folderId: subject.folderId,
      fileName: file.name,
      filePath: file.path,
      bytes: file.bytes,
    );
  }

  Future<void> _uploadPickedFile({
    required String folderId,
    required String fileName,
    String? filePath,
    List<int>? bytes,
  }) {
    return _uploadPickedFiles(
      folderId,
      [
        PhonePickedDocument(
          name: fileName,
          path: filePath ?? '',
          sizeBytes: bytes?.length ?? 0,
        ),
      ],
      bytesByName: bytes == null ? null : {fileName: bytes},
    );
  }

  Future<void> _uploadPickedFiles(
    String folderId,
    List<PhonePickedDocument> files, {
    Map<String, List<int>>? bytesByName,
  }) async {
    if (isUploading || files.isEmpty) return;

    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
    });

    var uploaded = 0;
    String? lastError;

    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        try {
          await UploadService.instance.uploadFile(
            folderId: folderId,
            fileName: file.name,
            filePath: file.path.isEmpty ? null : file.path,
            bytes: bytesByName?[file.name],
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                uploadProgress = (i + progress) / files.length;
              });
            },
          );
          uploaded++;
        } on UploadException catch (e) {
          lastError = e.message;
        } catch (_) {
          lastError = 'Upload failed. Please try again.';
        }
      }

      if (uploaded == files.length) {
        _showMessage(
          uploaded == 1
              ? '${files.first.name} uploaded successfully'
              : '$uploaded documents uploaded successfully',
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

      final subject = selectedSubject;
      if (uploaded > 0 && subject != null) {
        await _loadSubjectFiles(subject);
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          uploadProgress = 0.0;
        });
      }
    }
  }

  void _backToSubjects() {
    setState(() {
      openedMaterial = null;
      selectedSubject = null;
      currentFiles = [];
      downloadingFiles.clear();
      downloadProgress.clear();
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
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _previewUrl(StudyMaterial file) {
    final thumbnail = file.thumbnailUrl;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail.replaceFirst(RegExp(r'=s\d+'), '=s400');
    }
    return 'https://drive.google.com/thumbnail?id=${file.id}&sz=w400';
  }

  BoxDecoration _fileCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _fileTypeFallback(StudyMaterial file, {double iconSize = 24}) {
    final fileColor = _getFileColor(file.type);
    return ColoredBox(
      color: fileColor.withOpacity(0.1),
      child: Center(
        child: Icon(
          _getFileIcon(file.type),
          color: fileColor,
          size: iconSize,
        ),
      ),
    );
  }

  Widget _filePreview(StudyMaterial file, {required double iconSize}) {
    return Image.network(
      _previewUrl(file),
      key: ValueKey('preview-${file.id}'),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      cacheWidth: 400,
      errorBuilder: (_, __, ___) => _fileTypeFallback(file, iconSize: iconSize),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _fileTypeFallback(file, iconSize: iconSize);
      },
    );
  }

  Widget _fileOverflowMenu(StudyMaterial file, {required bool isDownloading}) {
    if (_deletingIds.contains(file.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
          ),
        ),
      );
    }
    if (!_canManageFolders) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'File options',
      enabled: !isDownloading,
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_vert_rounded,
        color: Color(0xFF6366F1),
      ),
      onSelected: (value) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          if (value == 'rename') {
            _renameMaterial(file);
          } else if (value == 'delete') {
            _confirmDelete(file);
          }
        });
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('Rename file'),
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

  Widget _downloadButton(StudyMaterial file, {required bool isDownloading}) {
    final fileColor = _getFileColor(file.type);
    return IconButton(
      icon: isDownloading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fileColor),
              ),
            )
          : Icon(
              Icons.download_rounded,
              color: fileColor,
            ),
      onPressed: isDownloading ? null : () => _downloadFile(file),
      tooltip: 'Download',
    );
  }

  Widget _buildDetailsFileList() {
    return ListView.builder(
      padding: AdaptiveLayout.pagePadding(context).copyWith(
        top: 12,
        bottom: AdaptiveLayout.bottomClearance(context),
      ),
      itemCount: _visibleFiles.length,
      itemBuilder: (context, index) {
        final file = _visibleFiles[index];
        final fileColor = _getFileColor(file.type);
        final isDownloading = downloadingFiles[file.id] ?? false;
        final progress = downloadProgress[file.id] ?? 0.0;

        return Container(
          key: ValueKey(file.id),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: _fileCardDecoration(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isDownloading ? null : () => _openFileInWebView(file),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: fileColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getFileIcon(file.type),
                        color: fileColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
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
                                  backgroundColor: const Color(0xFFE5E7EB),
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
                              '${file.type} • ${file.size} • ${file.date}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _fileOverflowMenu(file, isDownloading: isDownloading),
                    _downloadButton(file, isDownloading: isDownloading),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Color(0xFF9CA3AF),
                    ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = AdaptiveLayout.gridCount(constraints.maxWidth);
        return GridView.builder(
          padding: AdaptiveLayout.pagePadding(context).copyWith(
        top: 12,
        bottom: AdaptiveLayout.bottomClearance(context),
      ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: _visibleFiles.length,
          itemBuilder: (context, index) {
            final file = _visibleFiles[index];
            final isDownloading = downloadingFiles[file.id] ?? false;
            final progress = downloadProgress[file.id] ?? 0.0;

            return Container(
              key: ValueKey(file.id),
              decoration: _fileCardDecoration(),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isDownloading ? null : () => _openFileInWebView(file),
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
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      value: progress > 0 ? progress : null,
                                      strokeWidth: 3,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: _fileOverflowMenu(
                                file,
                                isDownloading: isDownloading,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: _downloadButton(
                                file,
                                isDownloading: isDownloading,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                        child: Text(
                          file.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
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
      canPop: widget.onBack == null && selectedSubject == null && openedMaterial == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onSystemBack();
      },
      child: openedMaterial != null
          ? WebViewScreen(
              key: ValueKey(openedMaterial!.id),
              url: openedMaterial!.downloadUrl!,
              title: openedMaterial!.name,
              subject: selectedSubject?.name ?? 'Unknown',
              onBack: _closeWebView,
            )
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

  Widget _buildFilesView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final visibleFiles = _visibleFiles;
    final folderCount = currentFiles.length;
    final matchCount = visibleFiles.length;
    final filesNoun = folderCount == 1 ? 'file' : 'files';
    final isFiltering =
        _fileQuery.trim().isNotEmpty || _fileTypeFilter != 'All';
    final countLabel = isFiltering
        ? '$matchCount of $folderCount $filesNoun'
        : '$folderCount $filesNoun';

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: titleColor,
        elevation: 0,
        toolbarHeight: 52,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _backToSubjects,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedSubject!.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: titleColor,
              ),
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
      ),
      floatingActionButton: _isLiveFolder &&
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
            LinearProgressIndicator(
              value: uploadProgress > 0 ? uploadProgress : null,
              backgroundColor: isDark
                  ? const Color(0xFF374151)
                  : const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              minHeight: 3,
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
                              'This units folder is empty',
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
          label,
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
    final field = isDark ? const Color(0xFF111827) : const Color(0xFFEEF2F6);
    final visible = _visibleUnits;
    final totalFiles = _totalUnitFiles;
    final pagePad = AdaptiveLayout.pagePadding(context);
    final bottomPad = AdaptiveLayout.bottomClearance(context);
    final tablet = AdaptiveLayout.isTablet(context);

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: false,
      floatingActionButton: _isLiveFolder && _canManageFolders
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
                    label: Text(_isMutatingFolder ? 'Working...' : 'New unit'),
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
        onRefresh: _refreshSubjects,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            compactSliverAppBar(
              backgroundColor: background,
              foregroundColor: titleColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _leaveSemester,
              ),
              title: Text(
                widget.semesterName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: tablet ? 22 : 18,
                  color: titleColor,
                ),
              ),
              actions: [
                if (!isLoading && subjects.isNotEmpty)
                  IconButton(
                    tooltip: _unitsAsGrid ? 'List view' : 'Grid view',
                    icon: Icon(
                      _unitsAsGrid
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                    ),
                    onPressed: _toggleUnitsView,
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _isMutatingFolder ? null : _refreshSubjects,
                  tooltip: 'Refresh',
                ),
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
                          ? 'Loading units'
                          : '${subjects.length} ${subjects.length == 1 ? 'unit' : 'units'}  ·  $totalFiles ${totalFiles == 1 ? 'file' : 'files'}',
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
                        decoration: InputDecoration(
                          hintText: 'Search units',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _unitQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _unitSearchController.clear();
                                    setState(() {
                                      _unitQuery = '';
                                    });
                                  },
                                ),
                          filled: true,
                          fillColor: field,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
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
                        'Loading units...',
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
                    'No units match “$_unitQuery”',
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
                            menu: _unitFolderMenu(subject),
                            onTap: () => _openUnit(subject),
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
                          menu: _unitFolderMenu(subject),
                          onTap: () => _openUnit(subject),
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
    if (!_isLiveFolder || !_canManageFolders) return null;
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
        if (value == 'rename') {
          _renameUnitFolder(subject);
        } else if (value == 'delete') {
          _confirmDeleteUnitFolder(subject);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline_rounded, size: 18),
              SizedBox(width: 10),
              Text('Rename folder'),
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
                'Delete folder',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
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
              'No units yet',
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
                  : 'Unit folders will show up here once they are added.',
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
                label: const Text('New unit'),
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
    this.menu,
  });

  final Subject subject;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final title = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final filesLabel =
        '${subject.fileCount} ${subject.fileCount == 1 ? 'file' : 'files'}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(22),
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
                      _FolderGlyph(color: subject.color, size: 46),
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
                      if (menu != null) menu!,
                      Icon(Icons.chevron_right_rounded, color: muted),
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
                          _FolderGlyph(color: subject.color, size: 54),
                          const Spacer(),
                          if (menu != null) menu!,
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
  const _FolderGlyph({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
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
        ],
      ),
    );
  }
}

enum _UploadSource { photos, documents }

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
              'Choose photos, or browse PDFs and documents on this phone',
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

  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initial = '',
    this.fieldLabel = 'Folder name',
    this.helperText,
  });

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;

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

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
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
          hintText: 'e.g. CS101 Data Structures',
          labelText: widget.fieldLabel,
          helperText: widget.helperText,
        ),
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