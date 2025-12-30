/// App configuration
/// 
/// Change [baseUrl] to point to your backend server.
/// - JFK backend (consolidated): Port 5000
/// - IKE backend (legacy): Port 5000 (deprecated)
class AppConfig {
  // JFK consolidated backend URL - change IP as needed
  static const String baseUrl = 'http://192.168.0.31:5000/api';
  
  // Alternative configs for different environments:
  // static const String baseUrl = 'http://localhost:5001/api';  // Local dev
  // static const String baseUrl = 'https://api.yoursite.com/api';  // Production
  
  // Request timeouts
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 10);
}
