import 'dart:convert';

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
  TodoService._();

  static final TodoService instance = TodoService._();
  static const _storageKey = 'home_study_todos_v1';

  final List<StudyTodo> _items = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<StudyTodo> get all => List.unmodifiable(_items);

  static String dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _items.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map<String, dynamic>) {
              final todo = StudyTodo.fromJson(entry);
              if (todo.id.isNotEmpty && todo.title.isNotEmpty) {
                _items.add(todo);
              }
            } else if (entry is Map) {
              final todo = StudyTodo.fromJson(
                Map<String, dynamic>.from(entry),
              );
              if (todo.id.isNotEmpty && todo.title.isNotEmpty) {
                _items.add(todo);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading todos: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(DateTime date, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
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
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(done: !_items[index].done);
    await _persist();
  }

  Future<void> updateTitle(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (_items[index].title == trimmed) return;
    _items[index] = _items[index].copyWith(title: trimmed);
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }
}
