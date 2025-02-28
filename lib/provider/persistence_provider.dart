import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localsend_app/constants.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/stored_security_context.dart';
import 'package:localsend_app/model/receive_history_entry.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/provider/window_dimensions_provider.dart';
import 'package:localsend_app/util/alias_generator.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/security_helper.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('PersistenceService');

// Version of the storage
const _version = 'ls_version';

// Security keys (generated on first app start)
const _securityContext = 'ls_security_context';

// Received file history
const _receiveHistory = 'ls_receive_history';

// App Window Offset and Size info
const _windowOffsetX = 'ls_window_offset_x';
const _windowOffsetY = 'ls_window_offset_y';
const _windowWidth = 'ls_window_width';
const _windowHeight = 'ls_window_height';
const _saveWindowPlacement = 'ls_save_window_placement';

// Settings
const _showToken = 'ls_show_token';
const _aliasKey = 'ls_alias';
const _themeKey = 'ls_theme'; // now called brightness
const _colorKey = 'ls_color';
const _localeKey = 'ls_locale';
const _portKey = 'ls_port';
const _multicastGroupKey = 'ls_multicast_group';
const _destinationKey = 'ls_destination';
const _saveToGallery = 'ls_save_to_gallery';
const _quickSave = 'ls_quick_save';
const _minimizeToTray = 'ls_minimize_to_tray';
const _launchAtStartup = 'ls_launch_at_startup';
const _autoStartLaunchMinimized = 'ls_auto_start_launch_minimized';
const _https = 'ls_https';
const _sendMode = 'ls_send_mode';

final persistenceProvider = Provider<PersistenceService>((ref) {
  throw Exception('persistenceProvider not initialized');
});

/// This service abstracts the persistence layer.
class PersistenceService {
  final SharedPreferences _prefs;

  PersistenceService._(this._prefs);

  static Future<PersistenceService> initialize() async {
    SharedPreferences prefs;

    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      if (checkPlatform([TargetPlatform.windows])) {
        _logger.info('Could not initialize SharedPreferences, trying to delete corrupted settings file');
        final settingsDir = await path.getApplicationSupportDirectory();
        final prefsFile = p.join(settingsDir.path, 'shared_preferences.json');
        File(prefsFile).deleteSync();
        prefs = await SharedPreferences.getInstance();
      } else {
        throw Exception('Could not initialize SharedPreferences');
      }
    }

    // Locale configuration upon persistence initialisation to prevent unlocalised Alias generation
    final persistedLocale = prefs.getString(_localeKey);
    if (persistedLocale == null) {
      LocaleSettings.useDeviceLocale();
    } else {
      LocaleSettings.setLocaleRaw(persistedLocale);
    }

    if (prefs.getInt(_version) == null) {
      await prefs.setInt(_version, 1);
    }

    if (prefs.getString(_showToken) == null) {
      await prefs.setString(_showToken, const Uuid().v4());
    }

    if (prefs.getString(_aliasKey) == null) {
      await prefs.setString(_aliasKey, generateRandomAlias());
    }

    if (prefs.getString(_securityContext) == null) {
      await prefs.setString(_securityContext, jsonEncode(generateSecurityContext()));
    }

    if (prefs.getString(_colorKey) == null) {
      await prefs.setString(_colorKey, checkPlatform([TargetPlatform.android]) ? ColorMode.system.name : ColorMode.localsend.name);
    }

    return PersistenceService._(prefs);
  }

  StoredSecurityContext getSecurityContext() {
    final contextRaw = _prefs.getString(_securityContext)!;
    return StoredSecurityContext.fromJson(jsonDecode(contextRaw));
  }

  Future<void> setSecurityContext(StoredSecurityContext context) async {
    await _prefs.setString(_securityContext, jsonEncode(context));
  }

  List<ReceiveHistoryEntry> getReceiveHistory() {
    final historyRaw = _prefs.getStringList(_receiveHistory) ?? [];
    return historyRaw.map((entry) => ReceiveHistoryEntry.fromJson(jsonDecode(entry))).toList();
  }

  Future<void> setReceiveHistory(List<ReceiveHistoryEntry> entries) async {
    final historyRaw = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await _prefs.setStringList(_receiveHistory, historyRaw);
  }

  String getShowToken() {
    return _prefs.getString(_showToken)!;
  }

  String getAlias() {
    return _prefs.getString(_aliasKey) ?? generateRandomAlias();
  }

  Future<void> setAlias(String alias) async {
    await _prefs.setString(_aliasKey, alias);
  }

  ThemeMode getTheme() {
    final value = _prefs.getString(_themeKey);
    if (value == null) {
      return ThemeMode.system;
    }
    return ThemeMode.values.firstWhereOrNull((theme) => theme.name == value) ?? ThemeMode.system;
  }

  Future<void> setTheme(ThemeMode theme) async {
    await _prefs.setString(_themeKey, theme.name);
  }

  ColorMode getColorMode() {
    final value = _prefs.getString(_colorKey);
    if (value == null) {
      return ColorMode.system;
    }
    return ColorMode.values.firstWhereOrNull((color) => color.name == value) ?? ColorMode.system;
  }

  Future<void> setColorMode(ColorMode color) async {
    await _prefs.setString(_colorKey, color.name);
  }

  AppLocale? getLocale() {
    final value = _prefs.getString(_localeKey);
    if (value == null) {
      return null;
    }
    return AppLocale.values.firstWhereOrNull((locale) => locale.languageTag == value);
  }

  Future<void> setLocale(AppLocale? locale) async {
    if (locale == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, locale.languageTag);
    }
  }

  int getPort() {
    return _prefs.getInt(_portKey) ?? defaultPort;
  }

  Future<void> setPort(int port) async {
    await _prefs.setInt(_portKey, port);
  }

  String getMulticastGroup() {
    return _prefs.getString(_multicastGroupKey) ?? defaultMulticastGroup;
  }

  Future<void> setMulticastGroup(String group) async {
    await _prefs.setString(_multicastGroupKey, group);
  }

  String? getDestination() {
    return _prefs.getString(_destinationKey);
  }

  Future<void> setDestination(String? destination) async {
    if (destination == null) {
      await _prefs.remove(_destinationKey);
    } else {
      await _prefs.setString(_destinationKey, destination);
    }
  }

  bool isSaveToGallery() {
    return _prefs.getBool(_saveToGallery) ?? true;
  }

  Future<void> setSaveToGallery(bool saveToGallery) async {
    await _prefs.setBool(_saveToGallery, saveToGallery);
  }

  bool isQuickSave() {
    return _prefs.getBool(_quickSave) ?? false;
  }

  Future<void> setQuickSave(bool quickSave) async {
    await _prefs.setBool(_quickSave, quickSave);
  }

  bool isMinimizeToTray() {
    return _prefs.getBool(_minimizeToTray) ?? false;
  }

  Future<void> setMinimizeToTray(bool minimizeToTray) async {
    await _prefs.setBool(_minimizeToTray, minimizeToTray);
  }

  bool isLaunchAtStartup() {
    return _prefs.getBool(_launchAtStartup) ?? false;
  }

  Future<void> setLaunchAtStartup(bool launchAtStartup) async {
    await _prefs.setBool(_launchAtStartup, launchAtStartup);
  }

  bool isAutoStartLaunchMinimized() {
    return _prefs.getBool(_autoStartLaunchMinimized) ?? true;
  }

  Future<void> setAutoStartLaunchMinimized(bool launchMinimized) async {
    await _prefs.setBool(_autoStartLaunchMinimized, launchMinimized);
  }

  bool isHttps() {
    return _prefs.getBool(_https) ?? true;
  }

  Future<void> setHttps(bool https) async {
    await _prefs.setBool(_https, https);
  }

  SendMode getSendMode() {
    return SendMode.values.firstWhereOrNull((m) => m.name == _prefs.getString(_sendMode)) ?? SendMode.single;
  }

  Future<void> setSendMode(SendMode mode) async {
    await _prefs.setString(_sendMode, mode.name);
  }

  Future<void> setWindowOffsetX(double x) async {
    await _prefs.setDouble(_windowOffsetX, x);
  }

  Future<void> setWindowOffsetY(double y) async {
    await _prefs.setDouble(_windowOffsetY, y);
  }

  Future<void> setWindowHeight(double height) async {
    await _prefs.setDouble(_windowHeight, height);
  }

  Future<void> setWindowWidth(double width) async {
    await _prefs.setDouble(_windowWidth, width);
  }

  WindowDimensions getWindowLastDimensions() {
    Size? size;
    Offset? position;
    final offsetX = _prefs.getDouble(_windowOffsetX);
    final offsetY = _prefs.getDouble(_windowOffsetY);
    final width = _prefs.getDouble(_windowWidth);
    final height = _prefs.getDouble(_windowHeight);
    if (width != null && height != null) size = Size(width, height);
    if (offsetX != null && offsetY != null) position = Offset(offsetX, offsetY);

    final dimensions = {'size': size, 'position': position};
    return dimensions;
  }

  Future<void> setSaveWindowPlacement(bool savePlacement) async {
    await _prefs.setBool(_saveWindowPlacement, savePlacement);
  }

  bool getSaveWindowPlacement() {
    if (!checkPlatformIsNotWaylandDesktop()) return false;
    return _prefs.getBool(_saveWindowPlacement) ?? true;
  }
}
