import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/support_service.dart';
import 'system_admin_dashboard.dart';

class UsersFeedbackScreen extends StatefulWidget {
  const UsersFeedbackScreen({super.key});

  @override
  State<UsersFeedbackScreen> createState() => _UsersFeedbackScreenState();
}

class _UsersFeedbackScreenState extends State<UsersFeedbackScreen> {
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
            backgroundColor: Color(0xFFEF4444),
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
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _deleteMessage(SupportMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete message?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('This will remove the message permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
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
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete message: $e'),
          backgroundColor: const Color(0xFFEF4444),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'User Feedback',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _checkingAccess || !_hasAccess
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : StreamBuilder<List<SupportMessage>>(
              stream: SupportService.instance.watchMessages(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load messages: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  );
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No feedback yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _FeedbackCard(
                      message: message,
                      onMarkRead: () => _markAsRead(message),
                      onDelete: () => _deleteMessage(message),
                      onOpenScreenshot: message.screenshotUrl == null
                          ? null
                          : () => _openScreenshot(message.screenshotUrl!),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.message,
    required this.onMarkRead,
    required this.onDelete,
    this.onOpenScreenshot,
  });

  final SupportMessage message;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback? onOpenScreenshot;

  @override
  Widget build(BuildContext context) {
    final created = message.createdAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: message.isRead
              ? Colors.transparent
              : const Color(0xFF6366F1).withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.heading,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: message.isRead
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : const Color(0xFFF59E0B).withOpacity(0.12),
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
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          if (created != null) ...[
            const SizedBox(height: 2),
            Text(
              timeago.format(created),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            message.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Color(0xFF374151),
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
                  icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                  label: const Text('Mark as read'),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                label: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
