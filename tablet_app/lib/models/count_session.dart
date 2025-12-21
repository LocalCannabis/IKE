import 'product.dart';
import 'store.dart';

/// Count session - container for a full inventory count
class CountSession {
  final String id;
  final int storeId;
  final String status;
  final DateTime createdAt;
  final DateTime? closedAt;
  final DateTime? expectedSnapshotAt;
  final String? notes;
  final CountSessionCreator createdBy;
  final int passCount;
  final int submittedPassCount;
  final List<CountPass>? passes;

  CountSession({
    required this.id,
    required this.storeId,
    required this.status,
    required this.createdAt,
    this.closedAt,
    this.expectedSnapshotAt,
    this.notes,
    required this.createdBy,
    required this.passCount,
    required this.submittedPassCount,
    this.passes,
  });

  factory CountSession.fromJson(Map<String, dynamic> json) {
    return CountSession(
      id: json['id'],
      storeId: json['store_id'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      closedAt:
          json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
      expectedSnapshotAt: json['expected_snapshot_at'] != null
          ? DateTime.parse(json['expected_snapshot_at'])
          : null,
      notes: json['notes'],
      createdBy: CountSessionCreator.fromJson(json['created_by']),
      passCount: json['pass_count'] ?? 0,
      submittedPassCount: json['submitted_pass_count'] ?? 0,
      passes: json['passes'] != null
          ? (json['passes'] as List).map((p) => CountPass.fromJson(p)).toList()
          : null,
    );
  }

  bool get isActive => status == 'draft' || status == 'in_progress';
  bool get canAddPasses => status == 'draft' || status == 'in_progress';
}

class CountSessionCreator {
  final int id;
  final String name;

  CountSessionCreator({required this.id, required this.name});

  factory CountSessionCreator.fromJson(Map<String, dynamic> json) {
    return CountSessionCreator(
      id: json['id'],
      name: json['name'],
    );
  }
}

/// Count pass - focused counting window for a location
class CountPass {
  final String id;
  final String sessionId;
  final InventoryLocation location;
  final String? category;
  final String? subcategory;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final CountSessionCreator startedBy;
  final String status;
  final String scanMode;
  final String? deviceId;
  final int lineCount;
  final int totalCounted;
  final List<CountLine>? lines;

  CountPass({
    required this.id,
    required this.sessionId,
    required this.location,
    this.category,
    this.subcategory,
    required this.startedAt,
    this.submittedAt,
    required this.startedBy,
    required this.status,
    required this.scanMode,
    this.deviceId,
    required this.lineCount,
    required this.totalCounted,
    this.lines,
  });

  factory CountPass.fromJson(Map<String, dynamic> json) {
    return CountPass(
      id: json['id'],
      sessionId: json['session_id'],
      location: InventoryLocation.fromJson(json['location']),
      category: json['category'],
      subcategory: json['subcategory'],
      startedAt: DateTime.parse(json['started_at']),
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'])
          : null,
      startedBy: CountSessionCreator.fromJson(json['started_by']),
      status: json['status'],
      scanMode: json['scan_mode'] ?? 'scanner',
      deviceId: json['device_id'],
      lineCount: json['line_count'] ?? 0,
      totalCounted: json['total_counted'] ?? 0,
      lines: json['lines'] != null
          ? (json['lines'] as List).map((l) => CountLine.fromJson(l)).toList()
          : null,
    );
  }

  bool get isInProgress => status == 'in_progress';
  bool get isSubmitted => status == 'submitted';
}

/// Count line - individual item count within a pass
class CountLine {
  final String id;
  final String countPassId;
  final int productId;
  final String sku;
  final String? barcode;
  final String? packageId;
  final int countedQty;
  final String unit;
  final DateTime capturedAt;
  final String confidence;
  final String? notes;
  final CountLineProduct? product;

  CountLine({
    required this.id,
    required this.countPassId,
    required this.productId,
    required this.sku,
    this.barcode,
    this.packageId,
    required this.countedQty,
    required this.unit,
    required this.capturedAt,
    required this.confidence,
    this.notes,
    this.product,
  });

  factory CountLine.fromJson(Map<String, dynamic> json) {
    return CountLine(
      id: json['id'],
      countPassId: json['count_pass_id'],
      productId: json['product_id'],
      sku: json['sku'],
      barcode: json['barcode'],
      packageId: json['package_id'],
      countedQty: json['counted_qty'],
      unit: json['unit'] ?? 'each',
      capturedAt: DateTime.parse(json['captured_at']),
      confidence: json['confidence'] ?? 'scanned',
      notes: json['notes'],
      product: json['product'] != null
          ? CountLineProduct.fromJson(json['product'])
          : null,
    );
  }
}

/// Simplified product info embedded in count line
class CountLineProduct {
  final int id;
  final String name;
  final String? brand;
  final String? category;
  final String? subcategory;

  CountLineProduct({
    required this.id,
    required this.name,
    this.brand,
    this.category,
    this.subcategory,
  });

  factory CountLineProduct.fromJson(Map<String, dynamic> json) {
    return CountLineProduct(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      category: json['category'],
      subcategory: json['subcategory'],
    );
  }
}
