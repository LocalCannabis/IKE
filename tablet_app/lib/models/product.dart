/// Product model for scanning/lookup
class Product {
  final int id;
  final String sku;
  final String? covaSku;
  final String name;
  final String? brand;
  final String? category;
  final String? subcategory;
  final String? dominance;
  final String? format;
  final double? thcMin;
  final double? thcMax;
  final double? cbdMin;
  final double? cbdMax;

  Product({
    required this.id,
    required this.sku,
    this.covaSku,
    required this.name,
    this.brand,
    this.category,
    this.subcategory,
    this.dominance,
    this.format,
    this.thcMin,
    this.thcMax,
    this.cbdMin,
    this.cbdMax,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      sku: json['sku'],
      covaSku: json['cova_sku'],
      name: json['name'],
      brand: json['brand'],
      category: json['category'],
      subcategory: json['subcategory'],
      dominance: json['dominance'],
      format: json['format'],
      thcMin: json['thc_min']?.toDouble(),
      thcMax: json['thc_max']?.toDouble(),
      cbdMin: json['cbd_min']?.toDouble(),
      cbdMax: json['cbd_max']?.toDouble(),
    );
  }

  /// Display-friendly THC range
  String get thcRange {
    if (thcMin == null && thcMax == null) return 'N/A';
    if (thcMin == thcMax) return '${thcMin?.toStringAsFixed(0)}%';
    return '${thcMin?.toStringAsFixed(0)}-${thcMax?.toStringAsFixed(0)}%';
  }

  /// Display-friendly CBD range
  String get cbdRange {
    if (cbdMin == null && cbdMax == null) return 'N/A';
    if (cbdMin == cbdMax) return '${cbdMin?.toStringAsFixed(0)}%';
    return '${cbdMin?.toStringAsFixed(0)}-${cbdMax?.toStringAsFixed(0)}%';
  }
}
