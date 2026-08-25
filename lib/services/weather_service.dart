import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'upload_service.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.country,
    required this.lat,
    required this.lon,
    required this.tempC,
    required this.condition,
    required this.icon,
  });

  final String city;
  final String country;
  final double lat;
  final double lon;
  final int tempC;
  final String condition;
  final String icon;

  Map<String, dynamic> toJson() => {
        'city': city,
        'country': country,
        'lat': lat,
        'lon': lon,
        'tempC': tempC,
        'condition': condition,
        'icon': icon,
      };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    return WeatherSnapshot(
      city: json['city']?.toString() ?? WeatherService.defaultCity,
      country: json['country']?.toString() ?? WeatherService.defaultCountry,
      lat: (json['lat'] as num?)?.toDouble() ?? WeatherService.defaultLat,
      lon: (json['lon'] as num?)?.toDouble() ?? WeatherService.defaultLon,
      tempC: (json['tempC'] as num?)?.round() ?? 0,
      condition: json['condition']?.toString() ?? 'Unknown',
      icon: json['icon']?.toString() ?? '01d',
    );
  }
}

class WeatherPlace {
  const WeatherPlace({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    this.state,
  });

  final String name;
  final String country;
  final String? state;
  final double lat;
  final double lon;

  String get subtitle {
    final parts = <String>[
      if (state != null && state!.isNotEmpty) state!,
      if (country.isNotEmpty) country,
    ];
    return parts.join(', ');
  }
}

class SavedWeatherLocation {
  const SavedWeatherLocation({
    required this.city,
    required this.country,
    required this.lat,
    required this.lon,
    required this.isCustom,
  });

  final String city;
  final String country;
  final double lat;
  final double lon;
  final bool isCustom;

  String get label => '$city, $country';
}

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  static const defaultCity = 'Chuka';
  static const defaultCountry = 'KE';
  static const defaultLat = -0.3335;
  static const defaultLon = 37.6469;

  static const _legacyDefaultCity = 'Nairobi';
  static const _legacyDefaultLat = -1.286389;
  static const _legacyDefaultLon = 36.817223;

  static const _cityKey = 'weather_city';
  static const _countryKey = 'weather_country';
  static const _latKey = 'weather_lat';
  static const _lonKey = 'weather_lon';
  static const _snapshotKey = 'weather_snapshot_json';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  SavedWeatherLocation? _memoryLocation;
  WeatherSnapshot? _memorySnapshot;

  WeatherSnapshot? get memorySnapshot => _memorySnapshot;

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to load weather.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not get auth token. Please sign in again.');
    }
    return token;
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  SavedWeatherLocation get _defaultLocation => const SavedWeatherLocation(
        city: defaultCity,
        country: defaultCountry,
        lat: defaultLat,
        lon: defaultLon,
        isCustom: false,
      );

  Future<WeatherSnapshot?> cachedWeather() async {
    if (_memorySnapshot != null) return _memorySnapshot;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      _memorySnapshot =
          WeatherSnapshot.fromJson(Map<String, dynamic>.from(json));
      if (_isLegacySnapshot(_memorySnapshot!)) {
        _memorySnapshot = null;
        await prefs.remove(_snapshotKey);
        return null;
      }
      return _memorySnapshot;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheSnapshot(WeatherSnapshot weather) async {
    _memorySnapshot = weather;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(weather.toJson()));
  }

  Future<SavedWeatherLocation> savedLocation() async {
    if (_memoryLocation != null && _memoryLocation!.isCustom) {
      return _memoryLocation!;
    }

    final prefs = await SharedPreferences.getInstance();
    final local = _fromPrefs(prefs);
    if (local != null && !_isLegacyAppDefault(local)) {
      _memoryLocation = local;
      unawaited(_syncLocationToFirebaseIfMissing(local));
      return local;
    }

    final remote = await _loadLocationFromFirebase();
    if (remote != null && !_isLegacyAppDefault(remote)) {
      await _writePrefs(remote);
      _memoryLocation = remote;
      return remote;
    }

    _memoryLocation = _defaultLocation;
    return _defaultLocation;
  }

  bool _isLegacyAppDefault(SavedWeatherLocation location) {
    return _isLegacyCoords(
      city: location.city,
      lat: location.lat,
      lon: location.lon,
    );
  }

  bool _isLegacySnapshot(WeatherSnapshot snapshot) {
    return _isLegacyCoords(
      city: snapshot.city,
      lat: snapshot.lat,
      lon: snapshot.lon,
    );
  }

  bool _isLegacyCoords({
    required String city,
    required double lat,
    required double lon,
  }) {
    return city.trim().toLowerCase() == _legacyDefaultCity.toLowerCase() &&
        (lat - _legacyDefaultLat).abs() < 0.02 &&
        (lon - _legacyDefaultLon).abs() < 0.02;
  }

  SavedWeatherLocation? _fromPrefs(SharedPreferences prefs) {
    final city = prefs.getString(_cityKey);
    final lat = prefs.getDouble(_latKey);
    final lon = prefs.getDouble(_lonKey);
    if (city == null || city.isEmpty || lat == null || lon == null) {
      return null;
    }
    return SavedWeatherLocation(
      city: city,
      country: prefs.getString(_countryKey) ?? defaultCountry,
      lat: lat,
      lon: lon,
      isCustom: true,
    );
  }

  Future<void> _syncLocationToFirebaseIfMissing(
    SavedWeatherLocation local,
  ) async {
    final remote = await _loadLocationFromFirebase();
    if (remote != null) return;
    try {
      await _writeFirebase(local);
    } catch (e) {
      debugPrint('Error syncing weather location to Firebase: $e');
    }
  }

  Future<SavedWeatherLocation?> _loadLocationFromFirebase() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(uid)
          .get();
      final data = doc.data()?['weather_location'];
      if (data is! Map) return null;
      final city = data['city']?.toString().trim() ?? '';
      final lat = (data['lat'] as num?)?.toDouble();
      final lon = (data['lon'] as num?)?.toDouble();
      if (city.isEmpty || lat == null || lon == null) return null;
      return SavedWeatherLocation(
        city: city,
        country: data['country']?.toString() ?? defaultCountry,
        lat: lat,
        lon: lon,
        isCustom: true,
      );
    } catch (e) {
      debugPrint('Error loading weather location from Firebase: $e');
      return null;
    }
  }

  Future<void> _writePrefs(SavedWeatherLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, location.city);
    await prefs.setString(_countryKey, location.country);
    await prefs.setDouble(_latKey, location.lat);
    await prefs.setDouble(_lonKey, location.lon);
  }

  Future<void> _writeFirebase(SavedWeatherLocation location) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('profiles').doc(uid).set({
      'weather_location': {
        'city': location.city,
        'country': location.country,
        'lat': location.lat,
        'lon': location.lon,
        'updated_at': FieldValue.serverTimestamp(),
      },
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveLocation({
    required String city,
    required String country,
    required double lat,
    required double lon,
  }) async {
    final location = SavedWeatherLocation(
      city: city,
      country: country,
      lat: lat,
      lon: lon,
      isCustom: true,
    );
    _memoryLocation = location;
    await _writePrefs(location);
    try {
      await _writeFirebase(location);
    } catch (e) {
      debugPrint('Error saving weather location to Firebase: $e');
    }
  }

  Future<WeatherSnapshot> currentWeather({
    double? lat,
    double? lon,
  }) async {
    final saved = await savedLocation();
    final token = await _idToken();
    try {
      final response = await _dio.get(
        '/weather',
        queryParameters: {
          'lat': lat ?? saved.lat,
          'lon': lon ?? saved.lon,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      var weather = WeatherSnapshot.fromJson(data);
      if (saved.isCustom) {
        weather = WeatherSnapshot(
          city: saved.city,
          country: saved.country,
          lat: weather.lat,
          lon: weather.lon,
          tempC: weather.tempC,
          condition: weather.condition,
          icon: weather.icon,
        );
      }
      await _cacheSnapshot(weather);
      return weather;
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, 'Could not load weather right now.'));
    }
  }

  Future<List<WeatherPlace>> searchLocations(String query) async {
    final token = await _idToken();
    try {
      final response = await _dio.get(
        '/weather/locations',
        queryParameters: {'q': query.trim()},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final list = response.data?['locations'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((item) => WeatherPlace(
                name: item['name']?.toString() ?? '',
                country: item['country']?.toString() ?? '',
                state: item['state']?.toString(),
                lat: (item['lat'] as num?)?.toDouble() ?? 0,
                lon: (item['lon'] as num?)?.toDouble() ?? 0,
              ))
          .where((place) => place.name.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, 'Could not search locations right now.'));
    }
  }

  String _dioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return fallback;
  }
}
