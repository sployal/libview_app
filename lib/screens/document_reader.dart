import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/download_service.dart';
import '../services/phone_document_service.dart';

class DocumentReaderScreen extends StatefulWidget {
  final String fileName;
  final String? path;
  final String? uri;
  final Future<void> Function() openExternally;

  const DocumentReaderScreen({
    super.key,
    required this.fileName,
    this.path,
    this.uri,
    required this.openExternally,
  });

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'ico',
    'wbmp',
  };

  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static bool isImage(String fileName) =>
      _imageExtensions.contains(extensionOf(fileName));

  static bool isPdf(String fileName) => extensionOf(fileName) == 'pdf';

  static bool canOpenInApp(String fileName) =>
      isImage(fileName) || isPdf(fileName);

  static Future<void> open(
    BuildContext context, {
    required String fileName,
    String? path,
    String? uri,
    required Future<void> Function() openExternally,
  }) async {
    if (!canOpenInApp(fileName)) {
      await openExternally();
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentReaderScreen(
          fileName: fileName,
          path: path,
          uri: uri,
          openExternally: openExternally,
        ),
      ),
    );
  }

  @override
  State<DocumentReaderScreen> createState() => _DocumentReaderScreenState();
}

class _DocumentReaderScreenState extends State<DocumentReaderScreen> {
  String? _localPath;
  String? _error;
  bool _loading = true;
  int _page = 0;
  int _pageCount = 0;

  bool get _isPdf => DocumentReaderScreen.isPdf(widget.fileName);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final allowed =
          await DownloadService.requestStoragePermission(forOpening: true);
      if (!allowed) {
        throw Exception('Storage permission is needed to open this file');
      }
      final path = await PhoneDocumentService.instance.copyToReadablePath(
        fileName: widget.fileName,
        path: widget.path,
        uri: widget.uri,
      );
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openInOtherApp() async {
    try {
      await widget.openExternally();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final nested =
        Navigator.of(context) != Navigator.of(context, rootNavigator: true);
    final bottomInset = nested
        ? kBottomNavigationBarHeight +
            MediaQuery.viewPaddingOf(context).bottom
        : MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
        foregroundColor: titleColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: titleColor,
          ),
        ),
        actions: [
          if (_isPdf && _pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${_page + 1} / $_pageCount',
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Open in another app',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openInOtherApp,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: _buildBody(titleColor, muted, isDark),
      ),
    );
  }

  Widget _buildBody(Color titleColor, Color muted, bool isDark) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }

    if (_error != null || _localPath == null) {
      return _ErrorState(
        message: _error ?? 'Could not open this file',
        muted: muted,
        titleColor: titleColor,
        onOpenExternally: _openInOtherApp,
      );
    }

    if (_isPdf) {
      return SfPdfViewer.file(
        File(_localPath!),
        pageLayoutMode: PdfPageLayoutMode.continuous,
        scrollDirection: PdfScrollDirection.vertical,
        pageSpacing: 8,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        enableDoubleTapZooming: true,
        onDocumentLoaded: (details) {
          if (!mounted) return;
          setState(() {
            _pageCount = details.document.pages.count;
            _page = 0;
          });
        },
        onPageChanged: (details) {
          if (!mounted) return;
          setState(() => _page = details.newPageNumber - 1);
        },
        onDocumentLoadFailed: (details) {
          if (!mounted) return;
          setState(() {
            _error = details.description.isNotEmpty
                ? details.description
                : details.error;
          });
        },
      );
    }

    return ColoredBox(
      color: isDark ? Colors.black : const Color(0xFF0F172A),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 8,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Image.file(
                File(_localPath!),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _ErrorState(
                  message: 'This image could not be displayed',
                  muted: muted,
                  titleColor: Colors.white,
                  onOpenExternally: _openInOtherApp,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Color muted;
  final Color titleColor;
  final VoidCallback onOpenExternally;

  const _ErrorState({
    required this.message,
    required this.muted,
    required this.titleColor,
    required this.onOpenExternally,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: titleColor, fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenExternally,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open in another app'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
