import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class StreakInfo {
  const StreakInfo({
    required this.currentStreak,
    required this.longestStreak,
  });

  const StreakInfo.empty()
      : currentStreak = 0,
        longestStreak = 0;

  final int currentStreak;
  final int longestStreak;
}

class StreakService {
  StreakService._();

  static final StreakService instance = StreakService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreakInfo _cached = const StreakInfo.empty();

  /// Last known streak, available immediately without waiting on the network.
  StreakInfo get cachedStreak => _cached;

  DocumentReference<Map<String, dynamic>>? _userStreakRef() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore.collection('streaks').doc(user.uid);
  }

  static String dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static String _yesterdayKey(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return dateKey(today.subtract(const Duration(days: 1)));
  }

  /// Records that the user opened the app today and returns updated streak values.
  Future<StreakInfo> recordDailyOpen() async {
    final docRef = _userStreakRef();
    if (docRef == null) return const StreakInfo.empty();

    final now = DateTime.now();
    final today = dateKey(now);
    final yesterday = _yesterdayKey(now);

    try {
      final result = await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final data = snapshot.data();

        var currentStreak = (data?['currentStreak'] as num?)?.toInt() ?? 0;
        var longestStreak = (data?['longestStreak'] as num?)?.toInt() ?? 0;
        final lastOpenDate = data?['lastOpenDate'] as String?;

        if (lastOpenDate == today) {
          return StreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
          );
        }

        if (lastOpenDate == yesterday) {
          currentStreak += 1;
        } else {
          currentStreak = 1;
        }

        if (currentStreak > longestStreak) {
          longestStreak = currentStreak;
        }

        transaction.set(
          docRef,
          {
            'currentStreak': currentStreak,
            'longestStreak': longestStreak,
            'lastOpenDate': today,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return StreakInfo(
          currentStreak: currentStreak,
          longestStreak: longestStreak,
        );
      });
      return _cache(result);
    } catch (e) {
      debugPrint('Error recording streak: $e');
      return _cached;
    }
  }

  StreakInfo _cache(StreakInfo info) {
    _cached = info;
    return info;
  }

  Future<StreakInfo> getStreak() async {
    final docRef = _userStreakRef();
    if (docRef == null) return const StreakInfo.empty();

    try {
      final snapshot = await docRef.get();
      final data = snapshot.data();
      if (data == null) return const StreakInfo.empty();

      var currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
      final longestStreak = (data['longestStreak'] as num?)?.toInt() ?? 0;
      final lastOpenDate = data['lastOpenDate'] as String?;

      final now = DateTime.now();
      final today = dateKey(now);
      final yesterday = _yesterdayKey(now);

      // Streak is still active if they opened today or yesterday.
      if (lastOpenDate != today && lastOpenDate != yesterday) {
        currentStreak = 0;
      }

      return _cache(StreakInfo(
        currentStreak: currentStreak,
        longestStreak: longestStreak,
      ));
    } catch (e) {
      debugPrint('Error loading streak: $e');
      return _cached;
    }
  }
}
