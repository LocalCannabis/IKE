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

  // Session state (simplified workflow)
  CountSession? _activeSession;  // The one active session for the store
  List<CountSession> _sessions = [];  // History of sessions
  CountPass? _activePass;  // Legacy support
  
  // Recent scan for display
  ScanResult? _lastScan;

  // Location state
  List<InventoryLocation> _locations = [];
  
  // Categories for scope selection
  List<String> _categories = ['Flower', 'Pre-Rolls', 'Inhalable Extracts', 'Edibles', 'Topicals', 'Beverages', 'Accessories'];

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
  ScanResult? get lastScan => _lastScan;
  List<InventoryLocation> get locations => _locations;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiService get api => _api;
  
  /// Whether there's an active session to join
  bool get hasActiveSession => _activeSession != null;

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

          // Restore selected store or auto-select first
          if (savedStoreId != null) {
            _selectedStore = _stores.firstWhere(
              (s) => s.id == savedStoreId,
              orElse: () => _stores.first,
            );
          } else if (_stores.isNotEmpty) {
            // Auto-select first store if none saved
            _selectedStore = _stores.first;
          }
          
          if (_selectedStore != null) {
            await _loadLocations();
            await checkForActiveSession();
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
    await checkForActiveSession();
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

  // ============ SIMPLIFIED WORKFLOW ============

  /// Check for an active session (should be called on app load)
  Future<void> checkForActiveSession() async {
    if (_selectedStore == null) return;

    try {
      _activeSession = await _api.getActiveSession(_selectedStore!.id);
      _error = null;
    } catch (e) {
      _activeSession = null;
    }
    notifyListeners();
  }

  /// Start a new count session with scope
  Future<CountSession?> startSession({
    required String scopeType,  // 'location' | 'category' | 'full'
    int? scopeLocationId,
    String? scopeCategory,
    String? notes,
  }) async {
    if (_selectedStore == null) return null;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _api.createSessionWithScope(
        storeId: _selectedStore!.id,
        scopeType: scopeType,
        scopeLocationId: scopeLocationId,
        scopeCategory: scopeCategory,
        notes: notes,
      );
      _activeSession = session;
      _lastScan = null;
      notifyListeners();
      return session;
    } on ActiveSessionExistsException catch (e) {
      // Another session exists - join it instead
      _activeSession = e.existingSession;
      _error = 'Joined existing session';
      notifyListeners();
      return e.existingSession;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Join the active session (refresh it from server)
  Future<void> joinActiveSession() async {
    if (_activeSession == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _activeSession = await _api.getSession(_activeSession!.id);
      _lastScan = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Scan a barcode (simplified workflow - goes directly to session)
  Future<ScanResult?> scan(String barcode) async {
    if (_activeSession == null) return null;

    try {
      final result = await _api.scanToSession(
        sessionId: _activeSession!.id,
        barcode: barcode,
      );
      _lastScan = result;
      // Update local session stats
      _activeSession = CountSession(
        id: _activeSession!.id,
        storeId: _activeSession!.storeId,
        status: _activeSession!.status,
        createdAt: _activeSession!.createdAt,
        closedAt: _activeSession!.closedAt,
        expectedSnapshotAt: _activeSession!.expectedSnapshotAt,
        notes: _activeSession!.notes,
        createdBy: _activeSession!.createdBy,
        scopeType: _activeSession!.scopeType,
        scopeLocationId: _activeSession!.scopeLocationId,
        scopeLocation: _activeSession!.scopeLocation,
        scopeCategory: _activeSession!.scopeCategory,
        passCount: _activeSession!.passCount,
        submittedPassCount: _activeSession!.submittedPassCount,
        lineCount: result.totalItems,
        totalCounted: result.totalItems,
        uniqueSkus: result.uniqueSkus,
        passes: _activeSession!.passes,
        lines: _activeSession!.lines,
      );
      _error = null;
      notifyListeners();
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Undo the last scan
  Future<bool> undoLastScan() async {
    if (_activeSession == null || _lastScan == null) return false;

    try {
      await _api.deleteSessionLine(_activeSession!.id, _lastScan!.lineId);
      _lastScan = null;
      // Refresh session to get updated counts
      _activeSession = await _api.getSession(_activeSession!.id);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Submit the current session
  Future<bool> submitSession() async {
    if (_activeSession == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      await _api.submitSession(_activeSession!.id);
      _activeSession = null;
      _lastScan = null;
      _error = null;
      await loadSessions();  // Refresh history
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear the last scan display
  void clearLastScan() {
    _lastScan = null;
    notifyListeners();
  }

  // ============ LEGACY WORKFLOW (backward compatibility) ============

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

  /// Create a new count session (legacy - no scope)
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
    } on ActiveSessionExistsException catch (e) {
      _activeSession = e.existingSession;
      _error = 'Joined existing session';
      notifyListeners();
      return e.existingSession;
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
