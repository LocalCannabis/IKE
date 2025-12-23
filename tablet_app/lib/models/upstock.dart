/// Upstock data models for the tablet app.

class UpstockRun {
  final String id;
  final int storeId;
  final String locationId;
  final DateTime windowStartAt;
  final DateTime windowEndAt;
  final String status; // in_progress, completed, abandoned
  final String? createdByUserId;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? notes;
  final List<UpstockRunLine> lines;

  UpstockRun({
    required this.id,
    required this.storeId,
    required this.locationId,
    required this.windowStartAt,
    required this.windowEndAt,
    required this.status,
    this.createdByUserId,
    required this.createdAt,
    this.completedAt,
    this.notes,
    this.lines = const [],
  });

  factory UpstockRun.fromJson(Map<String, dynamic> json) {
    return UpstockRun(
      id: json['id'] as String,
      storeId: json['store_id'] as int,
      locationId: json['location_id'] as String,
      windowStartAt: DateTime.parse(json['window_start_at'] as String),
      windowEndAt: DateTime.parse(json['window_end_at'] as String),
      status: json['status'] as String,
      createdByUserId: json['created_by_user_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      notes: json['notes'] as String?,
      lines: (json['lines'] as List<dynamic>?)
              ?.map((l) => UpstockRunLine.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'location_id': locationId,
      'window_start_at': windowStartAt.toIso8601String(),
      'window_end_at': windowEndAt.toIso8601String(),
      'status': status,
      'created_by_user_id': createdByUserId,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'notes': notes,
    };
  }

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isAbandoned => status == 'abandoned';

  /// Group lines by cabinet for UI display
  Map<String, List<UpstockRunLine>> get linesByCategory {
    final grouped = <String, List<UpstockRunLine>>{};
    for (final line in lines) {
      final cabinet = line.cabinet ?? 'Other';
      grouped.putIfAbsent(cabinet, () => []).add(line);
    }
    return grouped;
  }
}

class UpstockRunLine {
  final String id;
  final String runId;
  final String sku;
  final String? productName;
  final String? brand;
  final String? category;
  final String? subcategory;
  final String? cabinet;
  final String? itemSize;
  final int soldQty;
  final int suggestedPullQty;
  final int? pulledQty;
  final String status; // pending, done, skipped, exception
  final int? bohQty;
  final String? exceptionReason;
  final DateTime? updatedAt;
  final String? updatedByUserId;

  UpstockRunLine({
    required this.id,
    required this.runId,
    required this.sku,
    this.productName,
    this.brand,
    this.category,
    this.subcategory,
    this.cabinet,
    this.itemSize,
    required this.soldQty,
    required this.suggestedPullQty,
    this.pulledQty,
    required this.status,
    this.bohQty,
    this.exceptionReason,
    this.updatedAt,
    this.updatedByUserId,
  });

  factory UpstockRunLine.fromJson(Map<String, dynamic> json) {
    return UpstockRunLine(
      id: json['id'] as String,
      runId: json['run_id'] as String,
      sku: json['sku'] as String,
      productName: json['product_name'] as String?,
      brand: json['brand'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      cabinet: json['cabinet'] as String?,
      itemSize: json['item_size'] as String?,
      soldQty: json['sold_qty'] as int,
      suggestedPullQty: json['suggested_pull_qty'] as int,
      pulledQty: json['pulled_qty'] as int?,
      status: json['status'] as String,
      bohQty: json['boh_qty'] as int?,
      exceptionReason: json['exception_reason'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      updatedByUserId: json['updated_by_user_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'run_id': runId,
      'sku': sku,
      'product_name': productName,
      'brand': brand,
      'category': category,
      'subcategory': subcategory,
      'cabinet': cabinet,
      'item_size': itemSize,
      'sold_qty': soldQty,
      'suggested_pull_qty': suggestedPullQty,
      'pulled_qty': pulledQty,
      'status': status,
      'boh_qty': bohQty,
      'exception_reason': exceptionReason,
      'updated_at': updatedAt?.toIso8601String(),
      'updated_by_user_id': updatedByUserId,
    };
  }

  bool get isPending => status == 'pending';
  bool get isDone => status == 'done';
  bool get isSkipped => status == 'skipped';
  bool get isException => status == 'exception';
  bool get isResolved => !isPending;

  /// Display name combining product name, brand, and size
  String get displayName {
    final parts = <String>[];
    if (productName != null) parts.add(productName!);
    if (brand != null && !productName.toString().contains(brand!)) {
      parts.insert(0, brand!);
    }
    if (itemSize != null) parts.add('($itemSize)');
    return parts.isNotEmpty ? parts.join(' ') : sku;
  }
}

class UpstockRunStats {
  final int total;
  final int done;
  final int pending;
  final int skipped;
  final int exceptions;
  final double completionRate;

  UpstockRunStats({
    required this.total,
    required this.done,
    required this.pending,
    required this.skipped,
    required this.exceptions,
    required this.completionRate,
  });

  factory UpstockRunStats.fromJson(Map<String, dynamic> json) {
    return UpstockRunStats(
      total: json['total'] as int,
      done: json['done'] as int,
      pending: json['pending'] as int,
      skipped: json['skipped'] as int,
      exceptions: json['exceptions'] as int,
      completionRate: (json['completion_rate'] as num).toDouble(),
    );
  }
}

class UpstockBaseline {
  final int id;
  final int storeId;
  final String locationId;
  final String sku;
  final int parQty;
  final String? cabinet;
  final String? subcategory;
  final DateTime? updatedAt;
  final String? updatedByUserId;

  UpstockBaseline({
    required this.id,
    required this.storeId,
    required this.locationId,
    required this.sku,
    required this.parQty,
    this.cabinet,
    this.subcategory,
    this.updatedAt,
    this.updatedByUserId,
  });

  factory UpstockBaseline.fromJson(Map<String, dynamic> json) {
    return UpstockBaseline(
      id: json['id'] as int,
      storeId: json['store_id'] as int,
      locationId: json['location_id'] as String,
      sku: json['sku'] as String,
      parQty: json['par_qty'] as int,
      cabinet: json['cabinet'] as String?,
      subcategory: json['subcategory'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      updatedByUserId: json['updated_by_user_id'] as String?,
    );
  }
}
