/// Store model
class Store {
  final int id;
  final String name;
  final String code;
  final String? address;
  final bool isActive;

  Store({
    required this.id,
    required this.name,
    required this.code,
    this.address,
    required this.isActive,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'],
      name: json['name'],
      code: json['code'],
      address: json['address'],
      isActive: json['is_active'] ?? true,
    );
  }
}

/// Inventory location within a store
class InventoryLocation {
  final int id;
  final int storeId;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;

  InventoryLocation({
    required this.id,
    required this.storeId,
    required this.code,
    required this.name,
    this.description,
    required this.isActive,
    required this.sortOrder,
  });

  factory InventoryLocation.fromJson(Map<String, dynamic> json) {
    return InventoryLocation(
      id: json['id'],
      storeId: json['store_id'],
      code: json['code'],
      name: json['name'],
      description: json['description'],
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
    );
  }
}
