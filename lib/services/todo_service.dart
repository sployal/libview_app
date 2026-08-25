import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyTodo {
  const StudyTodo({
    required this.id,
    required this.title,
    required this.dateKey,
    required this.done,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final String dateKey;
  final bool done;
  final int createdAtMs;

  StudyTodo copyWith({String? title, bool? done}) {
    return StudyTodo(
      id: id,
      title: title ?? this.title,
      dateKey: dateKey,
      done: done ?? this.done,
      createdAtMs: createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateKey': dateKey,
        'done': done,
        'createdAtMs': createdAtMs,
      };

  factory StudyTodo.fromJson(Map<String, dynamic> json) {
    return StudyTodo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      dateKey: json['dateKey'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class TodoService extends ChangeNotifier {
  TodoService._() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      load();
    });
  }

  static final TodoService instance = TodoService._();
  static const _legacyStorageKey = 'home_study_todos_v1';
  static const _legacyMigratedKey = 'home_study_todos_v1_migrated';

  final List<StudyTodo> _items = [];
  bool _loaded = false;
  String? _uid;
  int _loadGeneration = 0;

  bool get isLoaded => _loaded;
  List<StudyTodo> get all => List.unmodifiable(_items);

  static String dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static String _storageKey(String uid) => 'home_study_todos_v1_$uid';

  List<StudyTodo> forDate(DateTime date) {
    final key = dateKey(date);
    final dayItems = _items.where((item) => item.dateKey == key).toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return a.createdAtMs.compareTo(b.createdAtMs);
      });
    return dayItems;
  }

  bool hasTodos(DateTime date) =>
      _items.any((item) => item.dateKey == dateKey(date));

  bool hasOpenTodos(DateTime date) => _items.any(
        (item) => item.dateKey == dateKey(date) && !item.done,
      );

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _uid = null;
      _items.clear();
      _loaded = true;
      notifyListeners();
      return;
    }

    _uid = uid;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _loadGeneration) return;

    var items = _decodeTodos(prefs.getString(_storageKey(uid)));
    final alreadyMigrated = prefs.getBool(_legacyMigratedKey) ?? false;
    if (items.isEmpty && !alreadyMigrated) {
      items = _decodeTodos(prefs.getString(_legacyStorageKey));
    }

    _items
      ..clear()
      ..addAll(items);
    _loaded = true;
    notifyListeners();

    final remote = await _loadRemote(uid);
    if (generation != _loadGeneration) return;

    if (remote != null) {
      _items
        ..clear()
        ..addAll(remote);
    } else if (_items.isNotEmpty) {
      try {
        await _writeRemote(uid, _items);
      } catch (e) {
        debugPrint('Error saving todos: $e');
      }
    }

    await _writeLocal(uid, _items);
    if (!alreadyMigrated) {
      await prefs.remove(_legacyStorageKey);
      await prefs.setBool(_legacyMigratedKey, true);
    }
    notifyListeners();
  }

  Future<void> add(DateTime date, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || _uid == null) return;
    _items.add(
      StudyTodo(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        title: trimmed,
        dateKey: dateKey(date),
        done: false,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _persist();
  }

  Future<void> toggle(String id) async {
    if (_uid == null) return;
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(done: !_items[index].done);
    await _persist();
  }

  Future<void> updateTitle(String id, String title) async {
    if (_uid == null) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (_items[index].title == trimmed) return;
    _items[index] = _items[index].copyWith(title: trimmed);
    await _persist();
  }

  Future<void> remove(String id) async {
    if (_uid == null) return;
    _items.removeWhere((item) => item.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _writeLocal(uid, _items);
    try {
      await _writeRemote(uid, _items);
    } catch (e) {
      debugPrint('Error saving todos: $e');
    }
    notifyListeners();
  }

  Future<void> _writeLocal(String uid, List<StudyTodo> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(uid),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  DocumentReference<Map<String, dynamic>> _remoteRef(String uid) {
    return FirebaseFirestore.instance.collection('study_todos').doc(uid);
  }

  Future<void> _writeRemote(String uid, List<StudyTodo> items) async {
    await _remoteRef(uid).set({
      'items': items.map((item) => item.toJson()).toList(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<StudyTodo>?> _loadRemote(String uid) async {
    try {
      final doc = await _remoteRef(uid).get();
      if (!doc.exists) return null;
      final data = doc.data()?['items'];
      if (data is! List) return const <StudyTodo>[];
      return _parseList(data);
    } catch (e) {
      debugPrint('Error loading todos: $e');
      return null;
    }
  }

  List<StudyTodo> _decodeTodos(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return _parseList(decoded);
    } catch (e) {
      debugPrint('Error decoding todos: $e');
      return [];
    }
  }

  List<StudyTodo> _parseList(List<dynamic> decoded) {
    final items = <StudyTodo>[];
    for (final entry in decoded) {
      Map<String, dynamic>? json;
      if (entry is Map<String, dynamic>) {
        json = entry;
      } else if (entry is Map) {
        json = Map<String, dynamic>.from(entry);
      }
      if (json == null) continue;
      final todo = StudyTodo.fromJson(json);
      if (todo.id.isNotEmpty && todo.title.isNotEmpty) {
        items.add(todo);
      }
    }
    return items;
  }
}
