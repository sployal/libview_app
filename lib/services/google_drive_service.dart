import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class GoogleDriveService {
  static const String baseUrl = 'https://www.googleapis.com/drive/v3';
  static const String uploadUrl = 'https://www.googleapis.com/upload/drive/v3';
  
  // Default folder ID (kept for backward compatibility)
  static const String folderId = '1ltEhma0cQ62d3aw2sQVucKdkIUg5JBik';
  
  static const String apiKey = 'AIzaSyBlCLsPvArqlkJecaq_wmBdjb5bIdd23go';
  
  // Get folder contents
  static Future<List<DriveItem>> getFolderContents(String folderId) async {
    try {
      final queryParameters = <String, String>{
        'q': '\u0027$folderId\u0027 in parents and trashed = false',
        'fields': 'files(id,name,mimeType,size,modifiedTime,webViewLink,thumbnailLink)',
        'spaces': 'drive',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        'pageSize': '1000',
        'orderBy': 'name',
        'key': apiKey,
      };
      
      final uri = Uri.parse('$baseUrl/files').replace(queryParameters: queryParameters);
      
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      
      final response = await http.get(uri, headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> files = data['files'] ?? [];
        return files.map((file) => DriveItem.fromJson(file)).toList();
      } else {
        throw Exception('Failed to load folder contents: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching folder contents: $e');
      return [];
    }
  }
  
  // Create a new folder
  static Future<void> createFolder(String folderName, String parentFolderId) async {
    try {
      final queryParameters = <String, String>{
        'key': apiKey,
        'supportsAllDrives': 'true',
      };
      
      final uri = Uri.parse('$baseUrl/files').replace(queryParameters: queryParameters);
      
      final metadata = {
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': [parentFolderId],
      };
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(metadata),
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to create folder: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error creating folder: $e');
      throw e;
    }
  }
  
  // Upload a file
  static Future<void> uploadFile({
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    required String folderId,
  }) async {
    try {
      final boundary = 'boundary${DateTime.now().millisecondsSinceEpoch}';
      final queryParameters = <String, String>{
        'uploadType': 'multipart',
        'key': apiKey,
        'supportsAllDrives': 'true',
      };
      
      final uri = Uri.parse('$uploadUrl/files').replace(queryParameters: queryParameters);
      
      // Create metadata part
      final metadata = {
        'name': fileName,
        'parents': [folderId],
      };
      
      // Build multipart body
      final bodyParts = <String>[];
      
      // Part 1: Metadata
      bodyParts.add('--$boundary');
      bodyParts.add('Content-Type: application/json; charset=UTF-8');
      bodyParts.add('');
      bodyParts.add(json.encode(metadata));
      
      // Part 2: File data
      bodyParts.add('--$boundary');
      bodyParts.add('Content-Type: $mimeType');
      bodyParts.add('');
      
      final bodyStart = utf8.encode(bodyParts.join('\r\n') + '\r\n');
      final bodyEnd = utf8.encode('\r\n--$boundary--');
      
      // Combine all parts
      final body = <int>[];
      body.addAll(bodyStart);
      body.addAll(fileBytes);
      body.addAll(bodyEnd);
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': body.length.toString(),
        },
        body: body,
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to upload file: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error uploading file: $e');
      throw e;
    }
  }
  
  // Delete a file or folder
  static Future<void> deleteFile(String fileId) async {
    try {
      final queryParameters = <String, String>{
        'key': apiKey,
        'supportsAllDrives': 'true',
      };
      
      final uri = Uri.parse('$baseUrl/files/$fileId').replace(queryParameters: queryParameters);
      
      final response = await http.delete(uri);
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Failed to delete file: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error deleting file: $e');
      throw e;
    }
  }
  
  // ============================================================================
  // NEW METHOD: Load subjects from any Google Drive folder
  // ============================================================================
  static Future<List<Subject>> getSubjectsFromFolder(String folderId) async {
    try {
      final items = await getFolderContents(folderId);
      
      // Convert folders to subjects
      final List<Subject> subjects = [];
      final colors = [
        const Color(0xFF6366F1),
        const Color(0xFF10B981),
        const Color(0xFFEF4444),
        const Color(0xFFF59E0B),
        const Color(0xFF8B5CF6),
        const Color(0xFF06B6D4),
        const Color(0xFFEC4899),
        const Color(0xFF84CC16),
      ];
      
      int colorIndex = 0;
      
      for (var item in items) {
        if (item.isFolder) {
          // Count files in this subject folder
          int fileCount = 0;
          try {
            final subFolderItems = await getFolderContents(item.id);
            fileCount = subFolderItems.where((i) => !i.isFolder).length;
          } catch (e) {
            fileCount = 0;
          }
          
          subjects.add(Subject(
            id: item.id,
            name: item.name,
            code: _extractSubjectCode(item.name),
            folderId: item.id,
            color: colors[colorIndex % colors.length],
            fileCount: fileCount,
          ));
          
          colorIndex++;
        }
      }
      
      return subjects;
    } catch (e) {
      print('Error loading subjects from folder: $e');
      throw Exception('Failed to load subjects from folder: $e');
    }
  }
  
  // ============================================================================
  // BACKWARD COMPATIBILITY: Keep old method for existing Semester 4 code
  // ============================================================================
  static Future<List<Subject>> getSemester4Subjects() async {
    return getSubjectsFromFolder(folderId);
  }
  
  // Get files for a specific subject
  static Future<List<StudyMaterial>> getSubjectFiles(String subjectFolderId) async {
    try {
      final items = await getFolderContents(subjectFolderId);
      
      return items
          .where((item) => !item.isFolder)
          .map((item) => StudyMaterial(
                id: item.id,
                name: item.name,
                type: _getFileType(item.name),
                size: _formatFileSize(item.size),
                date: _formatDate(item.modifiedTime),
                downloadUrl: item.webViewLink,
                thumbnailUrl: item.thumbnailLink,
              ))
          .toList();
    } catch (e) {
      print('Error fetching subject files: $e');
      return [];
    }
  }
  
  // ============================================================================
  // Helper methods
  // ============================================================================
  
  // Extract subject code from folder name (e.g., "CS101 Data Structures" -> "CS101")
  static String _extractSubjectCode(String folderName) {
    // Try to extract code like "CS101" or "EENG 483" from the folder name
    final regExp = RegExp(r'[A-Z]{2,4}\s?\d{3}');
    final match = regExp.firstMatch(folderName);
    if (match != null) {
      return match.group(0)!.replaceAll(' ', '');
    }
    
    // If no code found, use first word
    final words = folderName.split(' ');
    if (words.isNotEmpty) {
      return words[0].toUpperCase();
    }
    
    return 'SUB';
  }
  
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
        return 'IMG';
      default:
        return 'FILE';
    }
  }
  
  static String _formatFileSize(String? sizeBytes) {
    if (sizeBytes == null) return 'Unknown';
    
    final size = int.tryParse(sizeBytes) ?? 0;
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  
  static String _formatDate(String? dateTime) {
    if (dateTime == null) return 'Unknown';
    
    try {
      final date = DateTime.parse(dateTime);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        return 'Today';
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
  
  // Fallback data if API fails
  static List<Subject> getFallbackSubjects() {
    return [
      Subject(
        id: '1',
        name: 'Sample Subject 1',
        code: 'SUB101',
        folderId: '',
        color: const Color(0xFF6366F1),
        fileCount: 0,
      ),
      Subject(
        id: '2',
        name: 'Sample Subject 2',
        code: 'SUB102',
        folderId: '',
        color: const Color(0xFF10B981),
        fileCount: 0,
      ),
    ];
  }
}

// ============================================================================
// Model classes
// ============================================================================

class DriveItem {
  final String id;
  final String name;
  final String mimeType;
  final String? size;
  final String? modifiedTime;
  final String? webViewLink;
  final String? thumbnailLink;
  
  DriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
    this.modifiedTime,
    this.webViewLink,
    this.thumbnailLink,
  });
  
  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
  
  factory DriveItem.fromJson(Map<String, dynamic> json) {
    return DriveItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      mimeType: json['mimeType'] ?? '',
      size: json['size'],
      modifiedTime: json['modifiedTime'],
      webViewLink: json['webViewLink'],
      thumbnailLink: json['thumbnailLink'],
    );
  }
}

class Subject {
  final String id;
  final String name;
  final String code;
  final String folderId;
  final Color color;
  int fileCount;
  
  Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.folderId,
    required this.color,
    this.fileCount = 0,
  });
}

class StudyMaterial {
  final String id;
  final String name;
  final String type;
  final String size;
  final String date;
  final String? downloadUrl;
  final String? thumbnailUrl;
  
  StudyMaterial({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.date,
    this.downloadUrl,
    this.thumbnailUrl,
  });
}