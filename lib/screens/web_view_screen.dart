import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? subject;

  const WebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.subject,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool isLoading = true;
  String? errorMessage;
  bool isDownloading = false;
  double downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  // NEW: Convert Google Drive URL to preview URL
  String _convertToPreviewUrl(String url) {
    try {
      final fileId = _extractFileId(url);
      
      if (fileId != null) {
        // Return the preview URL format which has minimal UI and no comments
        return 'https://drive.google.com/file/d/$fileId/preview';
      }
      
      // If we can't extract file ID, return original URL
      return url;
    } catch (e) {
      print('Error converting to preview URL: $e');
      return url;
    }
  }

  void _initializeWebView() {
    // Convert the URL to preview format before loading
    final previewUrl = _convertToPreviewUrl(widget.url);
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              errorMessage = null;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              errorMessage = 'Failed to load page: ${error.description}';
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // Block navigation to comment-related URLs
            if (request.url.contains('/comments') ||
                request.url.contains('/getcomments') ||
                request.url.contains('/comment')) {
              return NavigationDecision.prevent;
            }
            
            if (request.url.contains('drive.google.com') ||
                request.url.contains('docs.google.com') ||
                request.url.contains('googleusercontent.com')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(previewUrl));
  }

  // Extract file ID from Google Drive URL
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
      
      print('Could not extract file ID from URL: $url');
      return null;
    } catch (e) {
      print('Error extracting file ID: $e');
      return null;
    }
  }

  // Download file with proper metadata extraction
  Future<void> _downloadFile() async {
    // Step 1: Extract file ID from URL
    final fileId = _extractFileId(widget.url);
    
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
      isDownloading = true;
      downloadProgress = 0.0;
    });

    // Step 2: Download file using the file ID
    final result = await DownloadService.downloadFile(
      fileId: fileId,
      subject: widget.subject ?? 'Unknown',
      onProgress: (progress) {
        setState(() {
          downloadProgress = progress;
        });
      },
    );

    setState(() {
      isDownloading = false;
    });

    // Step 3: Show result to user
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _controller.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: isDownloading ? null : _downloadFile,
            tooltip: 'Download',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (isLoading)
            const Center(
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
                    'Loading...',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          if (errorMessage != null && !isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 64,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        _controller.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isDownloading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.downloading_rounded,
                        size: 48,
                        color: Color(0xFF6366F1),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Downloading...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Getting file information',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          value: downloadProgress,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(downloadProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}