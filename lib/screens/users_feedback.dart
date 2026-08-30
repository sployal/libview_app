import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/support_service.dart';
import '../ui/adaptive_layout.dart';
import 'system_admin_dashboard.dart';

class UsersFeedbackScreen extends StatefulWidget {
  const UsersFeedbackScreen({super.key});

  @override
  State<UsersFeedbackScreen> createState() => _UsersFeedbackScreenState();
}

class _UsersFeedbackScreenState extends State<UsersFeedbackScreen> {
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  bool _hasAccess = false;
  bool _checkingAccess = true;

  @override
  void initState() {
    super.initState();
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    final allowed = await SystemAdminDashboard.isCurrentUserSystemAdmin();
    if (!mounted) return;
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have access to user feedback.'),
            backgroundColor: _danger,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }
    setState(() {
      _hasAccess = true;
      _checkingAccess = false;
    });
  }

  Future<void> _markAsRead(SupportMessage message) async {
    try {
      await SupportService.instance.markAsRead(message.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not mark as read: $e'),
          backgroundColor: _danger,
        ),
      );
    }
  }

  Future<void> _deleteMessage(SupportMessage message) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete message?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: titleColor,
          ),
        ),
        content: Text(
          'This will remove the message permanently.',
          style: TextStyle(fontSize: 15, color: muted, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: _danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupportService.instance.deleteMessage(message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete message: $e'),
          backgroundColor: _danger,
        ),
      );
    }
  }

  void _openScreenshot(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final primaryText =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final divider = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final pagePad = AdaptiveLayout.pagePadding(context);
    final tablet = AdaptiveLayout.isTablet(context);

    Widget body;
    if (_checkingAccess || !_hasAccess) {
      body = Center(
        child: CupertinoActivityIndicator(
          color: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF6B7280),
        ),
      );
    } else {
      body = StreamBuilder<List<SupportMessage>>(
        stream: SupportService.instance.watchMessages(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load messages: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return Center(
              child: CupertinoActivityIndicator(
                color: isDark
                    ? const Color(0xFFF9FAFB)
                    : const Color(0xFF6B7280),
              ),
            );
          }

          final messages = snapshot.data!;
          if (messages.isEmpty) {
            return Center(
              child: Text(
                'No feedback yet',
                style: TextStyle(fontSize: 16, color: secondaryText),
              ),
            );
          }

          return ListView.separated(
            padding: pagePad.copyWith(
              top: 8,
              bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final message = messages[index];
              return _FeedbackCard(
                message: message,
                card: card,
                primaryText: primaryText,
                secondaryText: secondaryText,
                divider: divider,
                isDark: isDark,
                onMarkRead: () => _markAsRead(message),
                onDelete: () => _deleteMessage(message),
                onOpenScreenshot: message.screenshotUrl == null
                    ? null
                    : () => _openScreenshot(message.screenshotUrl!),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: primaryText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: primaryText),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'User Feedback',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: tablet ? 22 : 20,
          ),
        ),
      ),
      body: body,
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.message,
    required this.card,
    required this.primaryText,
    required this.secondaryText,
    required this.divider,
    required this.isDark,
    required this.onMarkRead,
    required this.onDelete,
    this.onOpenScreenshot,
  });

  final SupportMessage message;
  final Color card;
  final Color primaryText;
  final Color secondaryText;
  final Color divider;
  final bool isDark;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback? onOpenScreenshot;

  @override
  Widget build(BuildContext context) {
    final created = message.createdAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: message.isRead
              ? divider
              : const Color(0xFF6366F1).withOpacity(isDark ? 0.45 : 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.heading,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: message.isRead
                      ? const Color(0xFF10B981).withOpacity(isDark ? 0.18 : 0.12)
                      : const Color(0xFFF59E0B).withOpacity(isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message.isRead ? 'Read' : 'Unread',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: message.isRead
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${message.userName} · ${message.userEmail}',
            style: TextStyle(
              fontSize: 12,
              color: secondaryText,
            ),
          ),
          if (created != null) ...[
            const SizedBox(height: 2),
            Text(
              timeago.format(created),
              style: TextStyle(
                fontSize: 12,
                color: secondaryText.withOpacity(0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            message.description,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: primaryText.withOpacity(0.88),
            ),
          ),
          if (message.screenshotUrl != null &&
              message.screenshotUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onOpenScreenshot,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  message.screenshotUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!message.isRead)
                TextButton.icon(
                  onPressed: onMarkRead,
                  icon: const Icon(
                    CupertinoIcons.envelope_open,
                    size: 18,
                    color: Color(0xFF6366F1),
                  ),
                  label: const Text(
                    'Mark as read',
                    style: TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: Color(0xFFEF4444),
                ),
                label: const Text(
                  'Delete',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
