import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content_model.dart';
import 'auth_service.dart';
import 'user_service.dart';

class WatchlistService extends ChangeNotifier {
  static final WatchlistService _instance = WatchlistService._internal();
  factory WatchlistService() => _instance;
  WatchlistService._internal();

  static const String _listsKey = 'watchlist_names';
  static const String _listPrefix = 'watchlist_data_';

  SharedPreferences? _prefs;

  List<String> _listNames = ['My List'];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final names = _prefs?.getStringList(_listsKey);
    if (names != null && names.isNotEmpty) {
      _listNames = names;
    } else {
      _prefs?.setStringList(_listsKey, _listNames);
    }
    // Sync from Firebase if logged in
    if (AuthService.isLoggedIn) {
      await syncFromCloud();
    }
  }

  /// Pull watchlists from Firebase and merge with local data.
  Future<void> syncFromCloud() async {
    try {
      final cloudLists = await UserService.getWatchlists();
      if (cloudLists.isEmpty) return;

      // Merge cloud lists into local
      for (final entry in cloudLists.entries) {
        final listName = entry.key;
        final cloudItems = entry.value;

        if (!_listNames.contains(listName)) {
          _listNames.add(listName);
        }

        // Cloud items take precedence — replace local list
        _prefs?.setString('$_listPrefix$listName', json.encode(cloudItems));
      }

      // Save updated list names locally
      _prefs?.setStringList(_listsKey, _listNames);
      notifyListeners();
    } catch (e) {
      debugPrint('[WatchlistService] syncFromCloud error: $e');
    }
  }

  List<String> get listNames => List.unmodifiable(_listNames);

  void createList(String name) {
    if (name.trim().isEmpty || _listNames.contains(name.trim())) return;
    _listNames.add(name.trim());
    _prefs?.setStringList(_listsKey, _listNames);
    notifyListeners();
    // No need to push to Firebase — empty lists are created implicitly when items are added
  }

  Future<void> deleteList(String name) async {
    if (name == 'My List') return; // Cannot delete default
    _listNames.remove(name);
    _prefs?.setStringList(_listsKey, _listNames);
    _prefs?.remove('$_listPrefix$name');
    notifyListeners();
    // Delete from Firebase
    if (AuthService.isLoggedIn) {
      try {
        await UserService.deleteWatchlist(name);
      } catch (e) {
        debugPrint('[WatchlistService] deleteList cloud error: $e');
      }
    }
  }

  List<ContentModel> getListItems(String listName) {
    final jsonStr = _prefs?.getString('$_listPrefix$listName');
    if (jsonStr == null) return [];
    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((e) => ContentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  bool isListed(String listName, String title) {
    final items = getListItems(listName);
    return items.any((item) => item.title == title);
  }

  Future<void> addToList(String listName, ContentModel content) async {
    final items = getListItems(listName);
    if (items.any((item) => item.title == content.title)) return; // Already exists
    items.insert(0, content); // Add to top
    _saveList(listName, items);
    // Push to Firebase
    if (AuthService.isLoggedIn) {
      try {
        await UserService.addToList(listName, content.toJson());
      } catch (e) {
        debugPrint('[WatchlistService] addToList cloud error: $e');
      }
    }
  }

  Future<void> removeFromList(String listName, String title) async {
    final items = getListItems(listName);
    items.removeWhere((item) => item.title == title);
    _saveList(listName, items);
    // Remove from Firebase
    if (AuthService.isLoggedIn) {
      try {
        await UserService.removeFromList(listName, title);
      } catch (e) {
        debugPrint('[WatchlistService] removeFromList cloud error: $e');
      }
    }
  }

  void _saveList(String listName, List<ContentModel> items) {
    final jsonList = items.map((e) => e.toJson()).toList();
    _prefs?.setString('$_listPrefix$listName', json.encode(jsonList));
    notifyListeners();
  }
}
