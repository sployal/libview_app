import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class GoogleDriveService {
  static const String baseUrl = 'https://www.googleapis.com/drive/v3';
  static const String folderId = '1ltEhma0cQ62d3aw2sQVucKdkIUg5JBik'; // Your Semester 4 folder
  
  // You'll need to get this from Google Cloud Console
  static const String apiKey = 'AIzaSyBlCLsPvArqlkJecaq_wmBdjb5bIdd23go';
  
  // Optional OAuth 2.0 access token (Bearer). If set, this takes precedence over apiKey.
  // Paste your token here if you prefer setting it in code (optional)
  static const String? defaultAccessToken = null; // e.g., 'ya29.a0Af...'
  static String? accessToken = defaultAccessToken;
  
  // Call this once after obtaining a fresh token
  static void setAccessToken(String token) {
    accessToken = token.trim().isEmpty ? null : token.trim();
  }
  
  // Model classes for API responses
  static Future<List<DriveItem>> getFolderContents(String folderId) async {
    try {
      // Build Drive files.list request with proper query and shared drives flags
      final queryParameters = <String, String>{
        'q': '\u0027$folderId\u0027 in parents and trashed = false',
        'fields': 'files(id,name,mimeType,size,modifiedTime,webViewLink,thumbnailLink)',
        'spaces': 'drive',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        'pageSize': '1000',
        'orderBy': 'name',
      };
      // Use API key only when no OAuth token is provided
      if (accessToken == null || accessToken!.isEmpty) {
        queryParameters['key'] = apiKey;
      }
      final uri = Uri.parse('$baseUrl/files').replace(queryParameters: queryParameters);
      
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (accessToken != null && accessToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${accessToken!}';
      }
      
      final response = await http.get(uri, headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> files = data['files'] ?? [];
        
        return files.map((file) => DriveItem.fromJson(file)).toList();
      } else {
        throw Exception('Failed to load folder contents: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error fetching folder contents: $e');
      return [];
    }
  }
  
  // Get semester 4 subjects (folders)
  static Future<List<Subject>> getSemester4Subjects() async {
    try {
      final items = await getFolderContents(folderId);
      
      // Filter only folders (subjects)
      final subjects = items
          .where((item) => item.isFolder)
          .map((item) => Subject(
                id: item.id,
                name: item.name,
                code: _extractSubjectCode(item.name),
                folderId: item.id,
                color: _getSubjectColor(item.name),
              ))
          .toList();
      
      // Get file counts for each subject
      for (var subject in subjects) {
        final files = await getFolderContents(subject.folderId);
        subject.fileCount = files.where((f) => !f.isFolder).length;
      }
      
      return subjects;
    } catch (e) {
      print('Error fetching subjects: $e');
      // For live Semester 4, do NOT return sample data; show empty so the UI reflects the issue
      return [];
    }
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
  
  // Helper methods
  static String _extractSubjectCode(String folderName) {
    // Extract code from folder name (e.g., "EENG Engineering Project I" -> "EENG")
    final parts = folderName.split(' ');
    return parts.isNotEmpty ? parts[0] : 'N/A';
  }
  
  static Color _getSubjectColor(String subjectName) {
    // Assign colors based on subject name
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
      const Color(0xFFEC4899),
      const Color(0xFF84CC16),
    ];
    
    final hash = subjectName.hashCode;
    return colors[hash.abs() % colors.length];
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
        name: 'EENG Engineering Project I',
        code: 'EENG',
        folderId: '',
        color: const Color(0xFF6366F1),
        fileCount: 15,
      ),
      Subject(
        id: '2',
        name: 'EENG Electrical Machine design',
        code: 'EENG',
        folderId: '',
        color: const Color(0xFF10B981),
        fileCount: 12,
      ),
      Subject(
        id: '3',
        name: 'EENG 483 Communication Systems',
        code: 'EENG 483',
        folderId: '',
        color: const Color(0xFFEF4444),
        fileCount: 18,
      ),
      Subject(
        id: '4',
        name: 'EENG 482 Signals and Systems',
        code: 'EENG 482',
        folderId: '',
        color: const Color(0xFF8B5CF6),
        fileCount: 10,
      ),
      Subject(
        id: '5',
        name: 'EENG 476 Microprocessor II',
        code: 'EENG 476',
        folderId: '',
        color: const Color(0xFFF59E0B),
        fileCount: 14,
      ),
      Subject(
        id: '6',
        name: 'EENG 475 Control Engineering I',
        code: 'EENG 475',
        folderId: '',
        color: const Color(0xFF06B6D4),
        fileCount: 9,
      ),
      Subject(
        id: '7',
        name: 'EENG 465 Power Systems II',
        code: 'EENG 465',
        folderId: '',
        color: const Color(0xFFEC4899),
        fileCount: 16,
      ),
      Subject(
        id: '8',
        name: 'EENG 455 Electrical Network Analysis',
        code: 'EENG 455',
        folderId: '',
        color: const Color(0xFF84CC16),
        fileCount: 11,
      ),
    ];
  }
}

// Model classes
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