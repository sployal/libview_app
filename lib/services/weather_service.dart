import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  static const defaultCity = 'Nairobi';
  static const defaultCountry = 'KE';
  static const defaultLat = -1.286389;
  static const defaultLon = 36.817223;

  static const _cityKey = 'weather_city';
  static const _countryKey = 'weather_country';
  static const _latKey = 'weather_lat';
  static const _lonKey = 'weather_lon';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

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

  Future<({String city, String country, double lat, double lon})>
      savedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      city: prefs.getString(_cityKey) ?? defaultCity,
      country: prefs.getString(_countryKey) ?? defaultCountry,
      lat: prefs.getDouble(_latKey) ?? defaultLat,
      lon: prefs.getDouble(_lonKey) ?? defaultLon,
    );
  }

  Future<void> saveLocation({
    required String city,
    required String country,
    required double lat,
    required double lon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, city);
    await prefs.setString(_countryKey, country);
    await prefs.setDouble(_latKey, lat);
    await prefs.setDouble(_lonKey, lon);
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
      return WeatherSnapshot.fromJson(data);
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
