import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

class DownloadService {
  static final Dio _dio = Dio();
  static const String baseUrl = 'https://www.googleapis.com/drive/v3';
  static const MethodChannel _downloadsChannel =
      MethodChannel('com.example.libview/downloads');

  /// Bumped whenever the tracked download list changes so UI can refresh.
  static final ValueNotifier<int> listVersion = ValueNotifier(0);

  static void _notifyListChanged() {
    listVersion.value++;
  }

  static String get apiKey {
    final key = dotenv.env['GOOGLE_DRIVE_DOWNLOAD_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw StateError('GOOGLE_DRIVE_DOWNLOAD_API_KEY is missing from .env');
    }
    return key;
  }
  
  // Get Android SDK version
  static Future<int> getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }
  
  // Android 13+ has no storage prompt for PDFs/docs; those are opened via URI.
  // Android 12 and below still need the Files/Media permission to open Downloads.
  static Future<bool> requestStoragePermission({bool forOpening = false}) async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final sdkInt = await getAndroidSdkVersion();

      if (sdkInt >= 33) {
        return true;
      }

      // MediaStore can save without this; opening still needs it on Android 10–12.
      if (!forOpening && sdkInt >= 29) {
        return true;
      }

      if (await Permission.storage.isGranted) {
        return true;
      }

      final status = await Permission.storage.request();
      if (status.isGranted) {
        return true;
      }

      if (status.isPermanentlyDenied && forOpening) {
        await openAppSettings();
      }
      return false;
    } catch (e) {
      print('Error requesting permission: $e');
      return true;
    }
  }

  // Phone's default Downloads folder (or closest equivalent on iOS/desktop)
  static Future<String> getDownloadsFolderPath() async {
    try {
      if (Platform.isAndroid) {
        try {
          final downloads = await getDownloadsDirectory();
          if (downloads != null) {
            return downloads.path;
          }
        } catch (_) {}
        return '/storage/emulated/0/Download';
      }

      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads.path;
      }

      return (await getApplicationDocumentsDirectory()).path;
    } catch (e) {
      print('Error getting Downloads folder path: $e');
      return (await getApplicationDocumentsDirectory()).path;
    }
  }
  
  // Fetch file metadata from Google Drive API
  static Future<DriveFileMetadata?> getFileMetadata(String fileId) async {
    try {
      final queryParameters = <String, String>{
        'fields': 'id,name,mimeType,size,webContentLink,exportLinks',
        'key': apiKey,
        'supportsAllDrives': 'true',
      };
      
      final uri = Uri.parse('$baseUrl/files/$fileId').replace(queryParameters: queryParameters);
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DriveFileMetadata.fromJson(data);
      } else {
        print('Failed to get file metadata: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching file metadata: $e');
      return null;
    }
  }
  
  // Get proper download URL based on file type
  static String? getDownloadUrl(DriveFileMetadata metadata) {
    // Check if it's a Google Workspace file (Docs, Sheets, Slides)
    if (metadata.mimeType.contains('google-apps')) {
      // Use export links for Google Workspace files
      if (metadata.exportLinks != null) {
        if (metadata.mimeType.contains('document')) {
          // Export Google Doc as PDF
          return metadata.exportLinks!['application/pdf'];
        } else if (metadata.mimeType.contains('spreadsheet')) {
          // Export Google Sheet as Excel
          return metadata.exportLinks!['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'];
        } else if (metadata.mimeType.contains('presentation')) {
          // Export Google Slides as PowerPoint
          return metadata.exportLinks!['application/vnd.openxmlformats-officedocument.presentationml.presentation'];
        }
      }
      return null;
    }
    
    // For regular files (PDF, images, etc.), use webContentLink
    if (metadata.webContentLink != null) {
      return metadata.webContentLink;
    }
    
    // Fallback: construct direct download URL
    return 'https://www.googleapis.com/drive/v3/files/${metadata.id}?alt=media&key=$apiKey';
  }
  
  // Get proper filename with extension
  static String getProperFilename(DriveFileMetadata metadata) {
    String filename = metadata.name;
    
    // If it's a Google Workspace file, add proper extension
    if (metadata.mimeType.contains('google-apps')) {
      if (!filename.contains('.')) {
        if (metadata.mimeType.contains('document')) {
          filename = '$filename.pdf';
        } else if (metadata.mimeType.contains('spreadsheet')) {
          filename = '$filename.xlsx';
        } else if (metadata.mimeType.contains('presentation')) {
          filename = '$filename.pptx';
        }
      }
    }
    
    // Sanitize filename (remove invalid characters)
    filename = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    
    return filename;
  }
  
  // Download file with proper Android 13+ handling
  static Future<DownloadResult> downloadFile({
    required String fileId,
    required String subject,
    Function(double)? onProgress,
  }) async {
    try {
      // Request permission (only for Android 12 and below)
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        return DownloadResult(
          success: false,
          message: 'Storage permission denied',
        );
      }
      
      // Step 1: Get file metadata from Google Drive API
      final metadata = await getFileMetadata(fileId);
      if (metadata == null) {
        return DownloadResult(
          success: false,
          message: 'Failed to get file information from Google Drive',
        );
      }
      
      // Step 2: Get proper filename with extension
      final fileName = getProperFilename(metadata);
      
      // Step 3: Get proper download URL
      final downloadUrl = getDownloadUrl(metadata);
      if (downloadUrl == null) {
        return DownloadResult(
          success: false,
          message: 'This file type cannot be downloaded',
        );
      }
      
      // Step 4: Download to a temp file, then move into the public Downloads folder
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      
      await _dio.download(
        downloadUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            final progress = received / total;
            onProgress(progress);
          }
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) {
            return status! < 500;
          },
        ),
      );

      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        return DownloadResult(
          success: false,
          message: 'File download failed',
        );
      }

      final fileSize = await tempFile.length();
      if (fileSize < 100) {
        final content = await tempFile.readAsString();
        await tempFile.delete();
        if (content.contains('<html') || content.contains('<!DOCTYPE') || content.contains('error')) {
          return DownloadResult(
            success: false,
            message: 'Download failed: Invalid file received',
          );
        }
      }

      final saved = await _saveToPublicDownloads(
        sourcePath: tempPath,
        fileName: fileName,
      );
      final filePath = saved.filePath;
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      
      // Step 7: Save download metadata
      await _saveDownloadMetadata(
        fileName: fileName,
        subject: subject,
        size: fileSize,
        filePath: filePath,
        contentUri: saved.contentUri,
      );
      
      return DownloadResult(
        success: true,
        message: 'Download complete',
        filePath: filePath,
      );
    } catch (e) {
      print('Download error: $e');
      return DownloadResult(
        success: false,
        message: 'Download failed: ${e.toString()}',
      );
    }
  }
  
  // Save download metadata to SharedPreferences
  static Future<void> _saveDownloadMetadata({
    required String fileName,
    required String subject,
    required int size,
    required String filePath,
    String? contentUri,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final downloadsJson = prefs.getString('downloads') ?? '[]';
    final List<dynamic> downloads = json.decode(downloadsJson);
    
    // Check if file already exists in downloads
    downloads.removeWhere((item) => item['filePath'] == filePath);
    
    downloads.insert(0, {
      'name': fileName,
      'subject': subject,
      'size': size,
      'filePath': filePath,
      'contentUri': contentUri,
      'date': DateTime.now().toIso8601String(),
      'type': _getFileType(fileName),
    });
    
    await prefs.setString('downloads', json.encode(downloads));
    _notifyListChanged();
  }
  
  // Get all downloads
  static Future<List<DownloadItem>> getDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadsJson = prefs.getString('downloads') ?? '[]';
      final List<dynamic> downloads = json.decode(downloadsJson);
      
      // Filter out files that no longer exist
      final validDownloads = <DownloadItem>[];
      var metadataChanged = false;
      for (var json in downloads) {
        var item = DownloadItem.fromJson(json);
        if (!await _downloadExists(item)) {
          metadataChanged = true;
          continue;
        }
        if (Platform.isAndroid &&
            (item.contentUri == null || item.contentUri!.isEmpty)) {
          final resolvedUri = await _resolveContentUri(item);
          if (resolvedUri != null && resolvedUri.isNotEmpty) {
            item = DownloadItem(
              name: item.name,
              subject: item.subject,
              size: item.size,
              filePath: item.filePath,
              contentUri: resolvedUri,
              date: item.date,
              type: item.type,
            );
            metadataChanged = true;
          }
        }
        validDownloads.add(item);
      }
      
      if (metadataChanged) {
        await prefs.setString(
          'downloads',
          json.encode(validDownloads.map((e) => e.toJson()).toList()),
        );
      }
      
      return validDownloads;
    } catch (e) {
      print('Error loading downloads: $e');
      return [];
    }
  }
  
  static Future<bool> _downloadExists(DownloadItem item) async {
    if (Platform.isAndroid) {
      try {
        final exists = await _downloadsChannel.invokeMethod<bool>(
          'downloadExists',
          {
            'uri': item.contentUri,
            'filePath': item.filePath,
            'fileName': item.name,
          },
        );
        return exists == true;
      } catch (_) {}
    }
    return File(item.filePath).exists();
  }

  static Future<String?> _resolveContentUri(DownloadItem item) async {
    try {
      return await _downloadsChannel.invokeMethod<String>(
        'resolveDownload',
        {
          'uri': item.contentUri,
          'filePath': item.filePath,
          'fileName': item.name,
        },
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> openDownloadedFile(DownloadItem item) async {
    final hasPermission = await requestStoragePermission(forOpening: true);
    if (!hasPermission) {
      throw Exception('Storage permission is needed to open this file');
    }

    if (Platform.isAndroid) {
      try {
        await _downloadsChannel.invokeMethod<bool>(
          'openDownload',
          {
            'uri': item.contentUri,
            'filePath': item.filePath,
            'fileName': item.name,
            'mimeType': _getMimeType(item.name),
          },
        );
      } on PlatformException catch (e) {
        throw Exception(e.message ?? 'Could not open this file');
      }
      return;
    }

    final result = await OpenFile.open(item.filePath);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  static Future<void> shareDownloads(List<DownloadItem> items) async {
    if (items.isEmpty) return;

    final hasPermission = await requestStoragePermission(forOpening: true);
    if (!hasPermission) {
      throw Exception('Storage permission is needed to share this file');
    }

    if (Platform.isAndroid) {
      try {
        await _downloadsChannel.invokeMethod<bool>(
          'shareDownloads',
          {
            'items': items
                .map(
                  (item) => {
                    'uri': item.contentUri,
                    'filePath': item.filePath,
                    'fileName': item.name,
                    'mimeType': _getMimeType(item.name),
                  },
                )
                .toList(),
          },
        );
      } on PlatformException catch (e) {
        throw Exception(e.message ?? 'Could not share these files');
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: items.map((item) => XFile(item.filePath)).toList(),
        text: items.length == 1
            ? 'Sharing ${items.first.name}'
            : 'Sharing ${items.length} files',
      ),
    );
  }

  // Delete download
  static Future<bool> deleteDownload(
    String filePath, {
    String? contentUri,
    bool notify = true,
  }) async {
    try {
      if (Platform.isAndroid) {
        await _downloadsChannel.invokeMethod<bool>(
          'deleteDownload',
          {
            'uri': contentUri,
            'filePath': filePath,
          },
        );
      } else {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final downloadsJson = prefs.getString('downloads') ?? '[]';
      final List<dynamic> downloads = json.decode(downloadsJson);
      
      downloads.removeWhere((item) => item['filePath'] == filePath);
      
      await prefs.setString('downloads', json.encode(downloads));
      if (notify) {
        _notifyListChanged();
      }
      return true;
    } catch (e) {
      print('Error deleting download: $e');
      return false;
    }
  }

  static Future<int> deleteDownloads(List<DownloadItem> items) async {
    var deleted = 0;
    for (final item in items) {
      final success = await deleteDownload(
        item.filePath,
        contentUri: item.contentUri,
        notify: false,
      );
      if (success) deleted++;
    }
    if (deleted > 0) {
      _notifyListChanged();
    }
    return deleted;
  }
  
  static Future<_SavedDownload> _saveToPublicDownloads({
    required String sourcePath,
    required String fileName,
  }) async {
    if (Platform.isAndroid) {
      final saved = await _downloadsChannel.invokeMethod<dynamic>(
        'saveToDownloads',
        {
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': _getMimeType(fileName),
        },
      );
      if (saved is Map) {
        final path = saved['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return _SavedDownload(
            filePath: path,
            contentUri: saved['uri'] as String?,
          );
        }
      }
      throw Exception('Could not save file to Downloads');
    }

    final folderPath = await getDownloadsFolderPath();
    var destPath = '$folderPath/$fileName';
    final destFile = File(destPath);
    if (await destFile.exists()) {
      destPath = _uniquePath(folderPath, fileName);
    }
    await File(sourcePath).copy(destPath);
    return _SavedDownload(filePath: destPath);
  }

  static String _uniquePath(String folderPath, String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var index = 1;
    var candidate = '$folderPath/$base ($index)$ext';
    while (File(candidate).existsSync()) {
      index++;
      candidate = '$folderPath/$base ($index)$ext';
    }
    return candidate;
  }

  static String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  // Clear all downloads tracked by the app (does not wipe the whole Downloads folder)
  static Future<void> clearAllDownloads() async {
    try {
      final downloads = await getDownloads();
      for (final item in downloads) {
        await deleteDownload(
          item.filePath,
          contentUri: item.contentUri,
          notify: false,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('downloads');
      _notifyListChanged();
    } catch (e) {
      print('Error clearing downloads: $e');
    }
  }
  
  // Helper: Get file type from extension
  static String _getFileType(String fileName) {
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
      case 'xls':
      case 'xlsx':
        return 'XLS';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'heic':
      case 'heif':
      case 'tif':
      case 'tiff':
        return 'IMG';
      default:
        return 'FILE';
    }
  }
  
  // Format file size
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
  
  // Format date
  static String formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} minutes ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hours ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}

// Drive file metadata model
class DriveFileMetadata {
  final String id;
  final String name;
  final String mimeType;
  final String? size;
  final String? webContentLink;
  final Map<String, String>? exportLinks;
  
  DriveFileMetadata({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
    this.webContentLink,
    this.exportLinks,
  });
  
  factory DriveFileMetadata.fromJson(Map<String, dynamic> json) {
    return DriveFileMetadata(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      mimeType: json['mimeType'] ?? '',
      size: json['size'],
      webContentLink: json['webContentLink'],
      exportLinks: json['exportLinks'] != null
          ? Map<String, String>.from(json['exportLinks'])
          : null,
    );
  }
}

// Download result model
class DownloadResult {
  final bool success;
  final String message;
  final String? filePath;
  
  DownloadResult({
    required this.success,
    required this.message,
    this.filePath,
  });
}

class _SavedDownload {
  final String filePath;
  final String? contentUri;

  _SavedDownload({required this.filePath, this.contentUri});
}

// Download item model
class DownloadItem {
  final String name;
  final String subject;
  final int size;
  final String filePath;
  final String? contentUri;
  final String date;
  final String type;
  
  DownloadItem({
    required this.name,
    required this.subject,
    required this.size,
    required this.filePath,
    this.contentUri,
    required this.date,
    required this.type,
  });
  
  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      name: json['name'] ?? '',
      subject: json['subject'] ?? '',
      size: json['size'] ?? 0,
      filePath: json['filePath'] ?? '',
      contentUri: json['contentUri'] as String?,
      date: json['date'] ?? '',
      type: json['type'] ?? 'FILE',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'subject': subject,
      'size': size,
      'filePath': filePath,
      'contentUri': contentUri,
      'date': date,
      'type': type,
    };
  }
}