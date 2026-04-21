import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _downloadsKey = 'downloads_history';
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<List<Map<String, dynamic>>> loadDownloads() async {
    try {
      final jsonString = _prefs.getString(_downloadsKey);
      if (jsonString == null) {
        return [];
      }

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      print('Error loading downloads: $e');
      return [];
    }
  }

  static Future<void> saveDownloads(
      List<Map<String, dynamic>> downloads) async {
    try {
      final jsonString = jsonEncode(downloads);
      await _prefs.setString(_downloadsKey, jsonString);
    } catch (e) {
      print('Error saving downloads: $e');
    }
  }

  static Future<void> clearDownloads() async {
    try {
      await _prefs.remove(_downloadsKey);
    } catch (e) {
      print('Error clearing downloads: $e');
    }
  }
}
