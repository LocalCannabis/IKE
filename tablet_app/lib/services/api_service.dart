import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../config.dart';

/// API service for communicating with the Flask backend
class ApiService {
  // Use centralized config
  static const String baseUrl = AppConfig.baseUrl;

  String? _accessToken;

  /// Set the access token after login
  void setToken(String token) {
    _accessToken = token;
  }

  /// Clear the access token on logout
  void clearToken() {
    _accessToken = null;
  }

  /// Get headers with optional auth
  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  // ============ AUTH ============

  /// Google OAuth login - sends ID token to backend for verification
  Future<AuthResult> googleLogin(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': idToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _accessToken = data['access_token'];
      return AuthResult(
        user: User.fromJson(data['user']),
        token: data['access_token'],
        created: false, // Google login doesn't create dev accounts
      );
    } else if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      throw ApiException(data['error'] ?? 'Domain not allowed', response.statusCode);
    } else if (response.statusCode == 401) {
      throw ApiException('Invalid Google token', response.statusCode);
    } else {
      throw ApiException('Google login failed', response.statusCode);
    }
  }

  /// Dev login - simple email-based login for development
  Future<AuthResult> devLogin(String email, {String? name}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/dev-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        if (name != null) 'name': name,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _accessToken = data['access_token'];
      return AuthResult(
        user: User.fromJson(data['user']),
        token: data['access_token'],
        created: data['created'] ?? false,
      );
    } else {
      throw ApiException('Login failed', response.statusCode);
    }
  }

  /// Get current user info
  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to get user', response.statusCode);
    }
  }

  /// List all stores
  Future<List<Store>> getStores() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/stores'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((s) => Store.fromJson(s)).toList();
    } else {
      throw ApiException('Failed to get stores', response.statusCode);
    }
  }

  // ============ LOCATIONS ============

  /// Get inventory locations for a store
  Future<List<InventoryLocation>> getLocations(int storeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/count/locations?store_id=$storeId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> locations = data['locations'];
      return locations.map((l) => InventoryLocation.fromJson(l)).toList();
    } else {
      throw ApiException('Failed to get locations', response.statusCode);
    }
  }

  // ============ PRODUCTS ============

  /// Lookup product by barcode/SKU
  Future<ProductLookupResult> lookupProduct(
      String barcode, int storeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/products/lookup?barcode=$barcode&store_id=$storeId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ProductLookupResult(
        product: Product.fromJson(data['product']),
        inventory: data['inventory'],
      );
    } else if (response.statusCode == 404) {
      throw ApiException('Product not found', 404);
    } else {
      throw ApiException('Product lookup failed', response.statusCode);
    }
  }

  // ============ COUNT SESSIONS ============

  /// List count sessions for a store
  Future<List<CountSession>> getSessions({
    int? storeId,
    String? status,
  }) async {
    final params = <String, String>{};
    if (storeId != null) params['store_id'] = storeId.toString();
    if (status != null) params['status'] = status;

    final uri = Uri.parse('$baseUrl/count/sessions')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> sessions = data['sessions'];
      return sessions.map((s) => CountSession.fromJson(s)).toList();
    } else {
      throw ApiException('Failed to get sessions', response.statusCode);
    }
  }

  /// Get single session with passes
  Future<CountSession> getSession(String sessionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/count/sessions/$sessionId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return CountSession.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to get session', response.statusCode);
    }
  }

  /// Create a new count session
  Future<CountSession> createSession({
    required int storeId,
    String? name,
    String? description,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/sessions'),
      headers: _headers,
      body: jsonEncode({
        'store_id': storeId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return CountSession.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 409) {
      // Active session already exists
      final data = jsonDecode(response.body);
      throw ActiveSessionExistsException(
        data['message'] ?? 'Active session already exists',
        CountSession.fromJson(data['session']),
      );
    } else {
      throw ApiException('Failed to create session', response.statusCode);
    }
  }

  /// Get the active session for a store (simplified workflow)
  Future<CountSession?> getActiveSession(int storeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/count/sessions/active?store_id=$storeId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['active'] == true) {
        return CountSession.fromJson(data['session']);
      }
    }
    return null;
  }

  /// Create a new count session with scope (simplified workflow)
  Future<CountSession> createSessionWithScope({
    required int storeId,
    required String scopeType,  // 'location' | 'category' | 'full'
    int? scopeLocationId,
    String? scopeCategory,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/sessions'),
      headers: _headers,
      body: jsonEncode({
        'store_id': storeId,
        'scope_type': scopeType,
        if (scopeLocationId != null) 'scope_location_id': scopeLocationId,
        if (scopeCategory != null) 'scope_category': scopeCategory,
        if (notes != null) 'notes': notes,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return CountSession.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 409) {
      final data = jsonDecode(response.body);
      throw ActiveSessionExistsException(
        data['message'] ?? 'Active session already exists',
        CountSession.fromJson(data['session']),
      );
    } else {
      throw ApiException('Failed to create session', response.statusCode);
    }
  }

  /// Submit a session (simplified workflow - mark as complete)
  Future<CountSession> submitSession(String sessionId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/sessions/$sessionId/submit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return CountSession.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to submit session', response.statusCode);
    }
  }

  /// Scan a product directly to session (simplified workflow)
  Future<ScanResult> scanToSession({
    required String sessionId,
    required String barcode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/sessions/$sessionId/scan'),
      headers: _headers,
      body: jsonEncode({'barcode': barcode}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ScanResult(
        success: true,
        product: ScanProduct.fromJson(data['product']),
        lineId: data['line_id'],
        lotNo: data['lot_no'],
        packDate: data['pack_date'],
        totalItems: data['session_stats']['total_items'],
        uniqueSkus: data['session_stats']['unique_skus'],
      );
    } else {
      // Extract error message
      String errorMessage = 'Product not found';
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['error'] != null) {
          errorMessage = errorData['error'];
          if (errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        }
      } catch (_) {}
      throw ApiException(errorMessage, response.statusCode);
    }
  }

  /// Delete a line from a session (undo a scan)
  Future<void> deleteSessionLine(String sessionId, String lineId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/count/sessions/$sessionId/lines/$lineId'),
      headers: _headers,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException('Failed to delete line', response.statusCode);
    }
  }

  // ============ COUNT PASSES (Legacy) ============

  /// Start a new count pass
  Future<CountPass> createPass({
    required String sessionId,
    required int locationId,
    String? category,
    String? subcategory,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/sessions/$sessionId/passes'),
      headers: _headers,
      body: jsonEncode({
        'location_id': locationId,
        if (category != null) 'category': category,
        if (subcategory != null) 'subcategory': subcategory,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return CountPass.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to create pass', response.statusCode);
    }
  }

  /// Get pass with lines
  Future<CountPass> getPass(String passId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/count/passes/$passId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return CountPass.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to get pass', response.statusCode);
    }
  }

  /// Submit a pass (mark as complete)
  Future<CountPass> submitPass(String passId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/passes/$passId/submit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return CountPass.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to submit pass', response.statusCode);
    }
  }

  // ============ COUNT LINES ============

  /// Add a count line (scan a product)
  Future<AddLineResult> addLine({
    required String passId,
    required String barcode,
    int quantity = 1,
    String? packageId,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/count/passes/$passId/lines'),
      headers: _headers,
      body: jsonEncode({
        'barcode': barcode,
        'quantity': quantity,
        if (packageId != null) 'package_id': packageId,
        if (notes != null) 'notes': notes,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AddLineResult(
        line: CountLine.fromJson(data['line']),
        incremented: data['incremented'] ?? false,
        previousQty: data['previous_qty'],
        product: data['product'] != null
            ? CountLineProduct.fromJson(data['product'])
            : null,
      );
    } else {
      // Try to extract error message from response body
      String errorMessage = 'Failed to add line';
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['error'] != null) {
          errorMessage = errorData['error'];
          if (errorData['hint'] != null) {
            errorMessage += ': ${errorData['hint']}';
          }
          if (errorData['barcode'] != null) {
            errorMessage += ' (scanned: ${errorData['barcode']})';
          }
        }
      } catch (_) {}
      throw ApiException(errorMessage, response.statusCode);
    }
  }

  /// Update a count line quantity
  Future<CountLine> updateLine(String lineId, int quantity) async {
    final response = await http.put(
      Uri.parse('$baseUrl/count/lines/$lineId'),
      headers: _headers,
      body: jsonEncode({'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      return CountLine.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException('Failed to update line', response.statusCode);
    }
  }

  /// Delete a count line
  Future<void> deleteLine(String lineId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/count/lines/$lineId'),
      headers: _headers,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException('Failed to delete line', response.statusCode);
    }
  }

  // ============ UPSTOCK ============

  /// Start a new upstock run
  Future<UpstockRunResult> startUpstockRun({
    required int storeId,
    required String locationId,
    String? notes,
    DateTime? windowEndAt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/upstock/runs/start'),
      headers: _headers,
      body: jsonEncode({
        'store_id': storeId,
        'location_id': locationId,
        if (notes != null) 'notes': notes,
        if (windowEndAt != null) 'window_end_at': windowEndAt.toIso8601String(),
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return UpstockRunResult(
        run: UpstockRun.fromJson(data['run']),
        stats: UpstockRunStats.fromJson(data['stats']),
      );
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Failed to start upstock run';
      throw ApiException(error, response.statusCode);
    }
  }

  /// Get list of upstock runs
  Future<List<UpstockRun>> getUpstockRuns({
    required int storeId,
    String? locationId,
    String? status,
    int limit = 50,
  }) async {
    final params = {
      'store_id': storeId.toString(),
      if (locationId != null) 'location_id': locationId,
      if (status != null) 'status': status,
      'limit': limit.toString(),
    };

    final uri = Uri.parse('$baseUrl/upstock/runs').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['runs'] as List)
          .map((r) => UpstockRun.fromJson(r))
          .toList();
    } else {
      throw ApiException('Failed to get upstock runs', response.statusCode);
    }
  }

  /// Get upstock run detail with all lines
  Future<UpstockRunResult> getUpstockRun(String runId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/upstock/runs/$runId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UpstockRunResult(
        run: UpstockRun.fromJson(data['run']),
        stats: UpstockRunStats.fromJson(data['stats']),
      );
    } else {
      throw ApiException('Failed to get upstock run', response.statusCode);
    }
  }

  /// Update an upstock run line
  Future<UpstockRunLine> updateUpstockLine({
    required String runId,
    required String sku,
    int? pulledQty,
    String? status,
    String? exceptionReason,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/upstock/runs/$runId/lines/$sku'),
      headers: _headers,
      body: jsonEncode({
        if (pulledQty != null) 'pulled_qty': pulledQty,
        if (status != null) 'status': status,
        if (exceptionReason != null) 'exception_reason': exceptionReason,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UpstockRunLine.fromJson(data['line']);
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Failed to update line';
      throw ApiException(error, response.statusCode);
    }
  }

  /// Complete an upstock run
  Future<UpstockRunResult> completeUpstockRun(String runId, {bool validateAllResolved = false}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/upstock/runs/$runId/complete'),
      headers: _headers,
      body: jsonEncode({
        'validate_all_resolved': validateAllResolved,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UpstockRunResult(
        run: UpstockRun.fromJson(data['run']),
        stats: UpstockRunStats.fromJson(data['stats']),
      );
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Failed to complete run';
      throw ApiException(error, response.statusCode);
    }
  }

  /// Abandon an upstock run
  Future<UpstockRun> abandonUpstockRun(String runId, {String? reason}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/upstock/runs/$runId/abandon'),
      headers: _headers,
      body: jsonEncode({
        if (reason != null) 'reason': reason,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UpstockRun.fromJson(data['run']);
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Failed to abandon run';
      throw ApiException(error, response.statusCode);
    }
  }

  // ============ SALES SYNC ============

  /// Get sales sync status for a store
  Future<Map<String, dynamic>> getSalesSyncStatus({required int storeId}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/upstock/sync/status?store_id=$storeId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw ApiException('Failed to get sync status', response.statusCode);
    }
  }

  /// Trigger sales sync from cova_sales to inventory_movements
  Future<Map<String, dynamic>> syncSales({
    required int storeId,
    String? fromDate,
    String? toDate,
    bool force = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/upstock/sync/sales'),
      headers: _headers,
      body: jsonEncode({
        'store_id': storeId,
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        'force': force,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Failed to sync sales';
      throw ApiException(error, response.statusCode);
    }
  }

  // ============ HEALTH ============

  /// Check API health
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

// ============ RESULT CLASSES ============

class AuthResult {
  final User user;
  final String token;
  final bool created;

  AuthResult({
    required this.user,
    required this.token,
    required this.created,
  });
}

class ProductLookupResult {
  final Product product;
  final dynamic inventory;

  ProductLookupResult({
    required this.product,
    this.inventory,
  });
}

class AddLineResult {
  final CountLine line;
  final bool incremented;
  final int? previousQty;
  final CountLineProduct? product;

  AddLineResult({
    required this.line,
    required this.incremented,
    this.previousQty,
    this.product,
  });
}

class UpstockRunResult {
  final UpstockRun run;
  final UpstockRunStats stats;

  UpstockRunResult({
    required this.run,
    required this.stats,
  });
}

// ============ EXCEPTIONS ============

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

/// Thrown when trying to create a session but one already exists
class ActiveSessionExistsException implements Exception {
  final String message;
  final CountSession existingSession;

  ActiveSessionExistsException(this.message, this.existingSession);

  @override
  String toString() => 'ActiveSessionExistsException: $message';
}

// ============ SCAN RESULT (Simplified workflow) ============

class ScanResult {
  final bool success;
  final ScanProduct product;
  final String lineId;
  final String? lotNo;
  final String? packDate;
  final int totalItems;
  final int uniqueSkus;

  ScanResult({
    required this.success,
    required this.product,
    required this.lineId,
    this.lotNo,
    this.packDate,
    required this.totalItems,
    required this.uniqueSkus,
  });
}

class ScanProduct {
  final int id;
  final String name;
  final String? brand;
  final String? category;
  final String? subcategory;
  final String sku;

  ScanProduct({
    required this.id,
    required this.name,
    this.brand,
    this.category,
    this.subcategory,
    required this.sku,
  });

  factory ScanProduct.fromJson(Map<String, dynamic> json) {
    return ScanProduct(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      category: json['category'],
      subcategory: json['subcategory'],
      sku: json['sku'],
    );
  }
}
