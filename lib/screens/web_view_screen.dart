import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? subject;
  final VoidCallback? onBack;

  const WebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.subject,
    this.onBack,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool isLoading = true;
  bool isDownloading = false;
  double downloadProgress = 0.0;
  String? _activeDownloadFileId;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  // Convert Google Drive URL to preview URL
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

  static const String _viewerCleanupJs = r'''
(function() {
  var root = document.head || document.documentElement;
  if (!root) return;

  if (!document.getElementById('edupal-hide-open-style')) {
    var css = document.createElement('style');
    css.id = 'edupal-hide-open-style';
    css.textContent = [
      '.ndfHFb-c4YZDc-Wrql6b,',
      '.ndfHFb-c4YZDc-GSQQnc-LgbsSe,',
      '.ndfHFb-c4YZDc-to915-LbYbvg,',
      '.ndfHFb-c4YZDc-nupQLb,',
      '[aria-label*="Open with" i],',
      '[aria-label*="Open in" i],',
      '[aria-label*="Open original" i],',
      '[aria-label*="Pop-out" i],',
      '[aria-label*="Pop out" i],',
      '[data-tooltip*="Open with" i],',
      '[data-tooltip*="Open in" i],',
      'a[href*="drive.google.com/open"],',
      'a[href*="/open?id="]',
      '{ display: none !important; visibility: hidden !important;',
      '  opacity: 0 !important; pointer-events: none !important; }'
    ].join(' ');
    root.appendChild(css);
  }

  function textOf(el) {
    return ((el.getAttribute('aria-label') || '') + ' ' +
            (el.getAttribute('title') || '') + ' ' +
            (el.getAttribute('data-tooltip') || '') + ' ' +
            (el.textContent || '')).toLowerCase();
  }

  function shouldHide(el) {
    var t = textOf(el);
    return t.indexOf('open with') !== -1 ||
           t.indexOf('open in') !== -1 ||
           t.indexOf('open original') !== -1 ||
           t.indexOf('pop-out') !== -1 ||
           t.indexOf('pop out') !== -1 ||
           ((t.indexOf('open file') !== -1 || t.indexOf('open this file') !== -1) &&
            (t.indexOf('drive') !== -1 || t.indexOf('docs') !== -1 ||
             t.indexOf('link') !== -1));
  }

  function hide(el) {
    if (!el || !el.style) return;
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('opacity', '0', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function hideOpenUi() {
    document.querySelectorAll('button, a, [role="button"]').forEach(function(el) {
      if (shouldHide(el)) hide(el);
    });
    document.querySelectorAll(
      '.ndfHFb-c4YZDc-Wrql6b, [role="dialog"], [role="alertdialog"], [role="status"]'
    ).forEach(function(el) {
      if (el.classList && el.classList.contains('ndfHFb-c4YZDc-Wrql6b')) {
        hide(el);
        return;
      }
      if (shouldHide(el)) hide(el);
    });
  }

  if (!window.__edupalHideOpen) {
    window.__edupalHideOpen = true;
    try {
      var meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=10.0, user-scalable=yes';
      root.appendChild(meta);
    } catch (e) {}
    new MutationObserver(hideOpenUi).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }
  hideOpenUi();
})();
''';

  void _injectViewerCleanup() {
    _controller.runJavaScript(_viewerCleanupJs).ignore();
  }

  bool _isExternalAppUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('intent:') ||
        lower.startsWith('market:') ||
        lower.startsWith('android-app:') ||
        lower.contains('play.google.com/store');
  }

  void _initializeWebView() {
    // Convert the URL to preview format before loading
    final previewUrl = _convertToPreviewUrl(widget.url);
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      // ⭐ ENABLE ZOOM SUPPORT - This is the key addition
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress >= 10) {
              _injectViewerCleanup();
            }
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
            _injectViewerCleanup();
          },
          onPageFinished: (String url) {
            _injectViewerCleanup();
            // Keep the overlay up until the hide CSS is in the page so the
            // Drive "Open" chip never paints for a frame.
            Future.delayed(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              setState(() {
                isLoading = false;
              });
            });
          },
          onWebResourceError: (WebResourceError error) {
            // Ignore sub-resource failures (ads, blocked requests, etc.)
            // so they don't cover a page that already loaded.
            setState(() {
              isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_isExternalAppUrl(request.url)) {
              return NavigationDecision.prevent;
            }
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
      _activeDownloadFileId = fileId;
    });

    // Step 2: Download file using the file ID
    final result = await DownloadService.downloadFile(
      fileId: fileId,
      subject: widget.subject ?? 'Unknown',
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          downloadProgress = progress;
        });
      },
    );

    if (!mounted) return;

    setState(() {
      isDownloading = false;
      _activeDownloadFileId = null;
    });

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

  void _cancelDownload() {
    final fileId = _activeDownloadFileId;
    if (fileId == null) return;
    DownloadService.cancelDownload(fileId);
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
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
            icon: Icon(
              isDownloading ? Icons.close_rounded : Icons.download_rounded,
            ),
            color: isDownloading ? const Color(0xFFEF4444) : null,
            onPressed: isDownloading ? _cancelDownload : _downloadFile,
            tooltip: isDownloading ? 'Cancel download' : 'Download',
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
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _cancelDownload,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFFEF4444),
                        ),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w600,
                          ),
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