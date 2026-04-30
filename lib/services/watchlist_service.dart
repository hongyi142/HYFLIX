import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content_model.dart';

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
  }

  List<String> get listNames => List.unmodifiable(_listNames);

  void createList(String name) {
    if (name.trim().isEmpty || _listNames.contains(name.trim())) return;
    _listNames.add(name.trim());
    _prefs?.setStringList(_listsKey, _listNames);
    notifyListeners();
  }

  void deleteList(String name) {
    if (name == 'My List') return; // Cannot delete default
    _listNames.remove(name);
    _prefs?.setStringList(_listsKey, _listNames);
    _prefs?.remove('$_listPrefix$name');
    notifyListeners();
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

  void addToList(String listName, ContentModel content) {
    final items = getListItems(listName);
    if (items.any((item) => item.title == content.title)) return; // Already exists
    items.insert(0, content); // Add to top
    _saveList(listName, items);
  }

  void removeFromList(String listName, String title) {
    final items = getListItems(listName);
    items.removeWhere((item) => item.title == title);
    _saveList(listName, items);
  }

  void _saveList(String listName, List<ContentModel> items) {
    final jsonList = items.map((e) => e.toJson()).toList();
    _prefs?.setString('$_listPrefix$listName', json.encode(jsonList));
    notifyListeners();
  }
}
