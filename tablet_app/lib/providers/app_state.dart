import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Main application state provider
class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();

  // Auth state
  User? _currentUser;
  String? _accessToken;
  bool _isLoggedIn = false;

  // Store state
  List<Store> _stores = [];
  Store? _selectedStore;

  // Session state
  List<CountSession> _sessions = [];
  CountSession? _activeSession;
  CountPass? _activePass;

  // Location state
  List<InventoryLocation> _locations = [];

  // Loading states
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  List<Store> get stores => _stores;
  Store? get selectedStore => _selectedStore;
  List<CountSession> get sessions => _sessions;
  CountSession? get activeSession => _activeSession;
  CountPass? get activePass => _activePass;
  List<InventoryLocation> get locations => _locations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiService get api => _api;

  /// Initialize - check for saved session
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('access_token');
      final savedStoreId = prefs.getInt('selected_store_id');

      if (savedToken != null) {
        _api.setToken(savedToken);
        _accessToken = savedToken;

        // Try to get current user
        try {
          _currentUser = await _api.getCurrentUser();
          _isLoggedIn = true;

          // Load stores
          _stores = await _api.getStores();

          // Restore selected store
          if (savedStoreId != null) {
            _selectedStore = _stores.firstWhere(
              (s) => s.id == savedStoreId,
              orElse: () => _stores.first,
            );
            await _loadLocations();
          }
        } catch (e) {
          // Token expired or invalid
          await logout();
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with email (dev mode)
  Future<bool> login(String email, {String? name}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.devLogin(email, name: name);
      _currentUser = result.user;
      _accessToken = result.token;
      _isLoggedIn = true;

      // Save token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', result.token);

      // Load stores
      _stores = await _api.getStores();
      if (_stores.isNotEmpty) {
        await selectStore(_stores.first);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with Google ID token
  Future<bool> googleLogin(String idToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.googleLogin(idToken);
      _currentUser = result.user;
      _accessToken = result.token;
      _isLoggedIn = true;

      // Save token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', result.token);

      // Load stores
      _stores = await _api.getStores();
      if (_stores.isNotEmpty) {
        await selectStore(_stores.first);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    _api.clearToken();
    _currentUser = null;
    _accessToken = null;
    _isLoggedIn = false;
    _stores = [];
    _selectedStore = null;
    _sessions = [];
    _activeSession = null;
    _activePass = null;
    _locations = [];

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('selected_store_id');

    notifyListeners();
  }

  /// Select a store
  Future<void> selectStore(Store store) async {
    _selectedStore = store;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_store_id', store.id);

    await _loadLocations();
    await loadSessions();

    notifyListeners();
  }

  /// Load locations for current store
  Future<void> _loadLocations() async {
    if (_selectedStore == null) return;

    try {
      _locations = await _api.getLocations(_selectedStore!.id);
    } catch (e) {
      _error = e.toString();
    }
  }

  /// Load sessions for current store
  Future<void> loadSessions() async {
    if (_selectedStore == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _sessions = await _api.getSessions(storeId: _selectedStore!.id);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new count session
  Future<CountSession?> createSession({String? name, String? description}) async {
    if (_selectedStore == null) return null;

    _isLoading = true;
    notifyListeners();

    try {
      final session = await _api.createSession(
        storeId: _selectedStore!.id,
        name: name,
        description: description,
      );
      _sessions.insert(0, session);
      _activeSession = session;
      _error = null;
      notifyListeners();
      return session;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set active session
  Future<void> setActiveSession(CountSession session) async {
    _isLoading = true;
    notifyListeners();

    try {
      _activeSession = await _api.getSession(session.id);
      _activePass = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh active session
  Future<void> refreshActiveSession() async {
    if (_activeSession == null) return;

    try {
      _activeSession = await _api.getSession(_activeSession!.id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Create a new count pass
  Future<CountPass?> createPass(int locationId) async {
    if (_activeSession == null) return null;

    _isLoading = true;
    notifyListeners();

    try {
      final pass = await _api.createPass(
        sessionId: _activeSession!.id,
        locationId: locationId,
      );
      _activePass = pass;
      await refreshActiveSession();
      _error = null;
      return pass;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set active pass
  Future<void> setActivePass(CountPass pass) async {
    _isLoading = true;
    notifyListeners();

    try {
      _activePass = await _api.getPass(pass.id);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh active pass
  Future<void> refreshActivePass() async {
    if (_activePass == null) return;

    try {
      _activePass = await _api.getPass(_activePass!.id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Add a scan to active pass
  Future<AddLineResult?> addScan(String barcode, {int quantity = 1}) async {
    if (_activePass == null) return null;

    try {
      final result = await _api.addLine(
        passId: _activePass!.id,
        barcode: barcode,
        quantity: quantity,
      );
      await refreshActivePass();
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Submit active pass
  Future<bool> submitActivePass() async {
    if (_activePass == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      _activePass = await _api.submitPass(_activePass!.id);
      await refreshActiveSession();
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear active pass (go back to session view)
  void clearActivePass() {
    _activePass = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
