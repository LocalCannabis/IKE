/// User model matching backend User schema
class User {
  final int id;
  final String email;
  final String name;
  final String role;
  final bool isActive;
  final int? defaultStoreId;
  final DateTime? lastLogin;
  final UserPermissions permissions;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.isActive,
    this.defaultStoreId,
    this.lastLogin,
    required this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      role: json['role'] ?? 'staff',
      isActive: json['is_active'] ?? true,
      defaultStoreId: json['default_store_id'],
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'])
          : null,
      permissions: UserPermissions.fromJson(json['permissions'] ?? {}),
    );
  }

  bool get canCount => permissions.canCount;
  bool get canReconcile => permissions.canReconcile;
  bool get canAdmin => permissions.canAdmin;
}

class UserPermissions {
  final bool canCount;
  final bool canReconcile;
  final bool canAdmin;

  UserPermissions({
    required this.canCount,
    required this.canReconcile,
    required this.canAdmin,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      canCount: json['can_count'] ?? true,
      canReconcile: json['can_reconcile'] ?? false,
      canAdmin: json['can_admin'] ?? false,
    );
  }
}
