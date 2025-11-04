import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DownloadService {
  static final Dio _dio = Dio();
  static const String apiKey = 'AIzaSyBlCLsPvArqlkJecaq_wmBdjb5bIdd23go';
  static const String baseUrl = 'https://www.googleapis.com/drive/v3';
  
  // Get Android SDK version
  static Future<int> getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }
  
  // Request storage permission (only for Android 12 and below)
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true; // No permission needed for non-Android platforms
    }
    
    try {
      final sdkInt = await getAndroidSdkVersion();
      
      // Android 13+ (API 33+): No storage permission needed for app-specific directories
      if (sdkInt >= 33) {
        return true;
      }
      
      // Android 12 and below (API 32 and below): Request storage permission
      if (await Permission.storage.isGranted) {
        return true;
      }
      
      final status = await Permission.storage.request();
      return status.isGranted;
    } catch (e) {
      print('Error requesting permission: $e');
      // If we can't determine version, assume Android 13+ behavior
      return true;
    }
  }
  
  // Get Edupal folder path with proper Android 13+ handling
  static Future<String> getEdupalFolderPath() async {
    try {
      final sdkInt = Platform.isAndroid ? await getAndroidSdkVersion() : 0;
      
      if (Platform.isAndroid && sdkInt >= 33) {
        // Android 13+: Use app-specific external storage (no permissions needed)
        final directory = await getExternalStorageDirectory();
        if (directory == null) {
          throw Exception('Could not access external storage');
        }
        
        final edupalDir = Directory('${directory.path}/Edupal');
        if (!await edupalDir.exists()) {
          await edupalDir.create(recursive: true);
        }
        return edupalDir.path;
      } else if (Platform.isAndroid) {
        // Android 12 and below: Try public storage first, fallback to app-specific
        try {
          final publicPath = '/storage/emulated/0/Edupal';
          final publicDir = Directory(publicPath);
          
          if (!await publicDir.exists()) {
            await publicDir.create(recursive: true);
          }
          
          // Test if we can write to this directory
          final testFile = File('$publicPath/.test');
          await testFile.writeAsString('test');
          await testFile.delete();
          
          return publicPath;
        } catch (e) {
          // If public storage fails, use app-specific directory
          print('Public storage not accessible, using app-specific: $e');
          final directory = await getExternalStorageDirectory();
          if (directory == null) {
            throw Exception('Could not access external storage');
          }
          
          final edupalDir = Directory('${directory.path}/Edupal');
          if (!await edupalDir.exists()) {
            await edupalDir.create(recursive: true);
          }
          return edupalDir.path;
        }
      } else {
        // iOS or other platforms
        final directory = await getApplicationDocumentsDirectory();
        final edupalDir = Directory('${directory.path}/Edupal');
        if (!await edupalDir.exists()) {
          await edupalDir.create(recursive: true);
        }
        return edupalDir.path;
      }
    } catch (e) {
      print('Error getting Edupal folder path: $e');
      // Final fallback
      final directory = await getApplicationDocumentsDirectory();
      final edupalDir = Directory('${directory.path}/Edupal');
      if (!await edupalDir.exists()) {
        await edupalDir.create(recursive: true);
      }
      return edupalDir.path;
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
      
      // Step 4: Get download path
      final folderPath = await getEdupalFolderPath();
      final filePath = '$folderPath/$fileName';
      
      // Step 5: Download file with progress
      await _dio.download(
        downloadUrl,
        filePath,
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
      
      // Step 6: Verify file was downloaded correctly
      final file = File(filePath);
      if (!await file.exists()) {
        return DownloadResult(
          success: false,
          message: 'File download failed',
        );
      }
      
      final fileSize = await file.length();
      
      // Check if file is too small (might be an error response)
      if (fileSize < 100) {
        final content = await file.readAsString();
        if (content.contains('<html') || content.contains('<!DOCTYPE') || content.contains('error')) {
          await file.delete();
          return DownloadResult(
            success: false,
            message: 'Download failed: Invalid file received',
          );
        }
      }
      
      // Step 7: Save download metadata
      await _saveDownloadMetadata(
        fileName: fileName,
        subject: subject,
        size: fileSize,
        filePath: filePath,
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
      'date': DateTime.now().toIso8601String(),
      'type': _getFileType(fileName),
    });
    
    await prefs.setString('downloads', json.encode(downloads));
  }
  
  // Get all downloads
  static Future<List<DownloadItem>> getDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadsJson = prefs.getString('downloads') ?? '[]';
      final List<dynamic> downloads = json.decode(downloadsJson);
      
      // Filter out files that no longer exist
      final validDownloads = <DownloadItem>[];
      for (var json in downloads) {
        final item = DownloadItem.fromJson(json);
        final file = File(item.filePath);
        if (await file.exists()) {
          validDownloads.add(item);
        }
      }
      
      // Update the list if files were removed
      if (validDownloads.length != downloads.length) {
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
  
  // Delete download
  static Future<bool> deleteDownload(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      final prefs = await SharedPreferences.getInstance();
      final downloadsJson = prefs.getString('downloads') ?? '[]';
      final List<dynamic> downloads = json.decode(downloadsJson);
      
      downloads.removeWhere((item) => item['filePath'] == filePath);
      
      await prefs.setString('downloads', json.encode(downloads));
      return true;
    } catch (e) {
      print('Error deleting download: $e');
      return false;
    }
  }
  
  // Clear all downloads
  static Future<void> clearAllDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('downloads');
      
      final folderPath = await getEdupalFolderPath();
      final folder = Directory(folderPath);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
        await folder.create();
      }
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
        return 'IMG';
      default:
        return 'FILE';
    }
  }
  
  // Format file size
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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

// Download item model
class DownloadItem {
  final String name;
  final String subject;
  final int size;
  final String filePath;
  final String date;
  final String type;
  
  DownloadItem({
    required this.name,
    required this.subject,
    required this.size,
    required this.filePath,
    required this.date,
    required this.type,
  });
  
  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      name: json['name'] ?? '',
      subject: json['subject'] ?? '',
      size: json['size'] ?? 0,
      filePath: json['filePath'] ?? '',
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
      'date': date,
      'type': type,
    };
  }
}