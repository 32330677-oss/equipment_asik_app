/// Small, null-safe readers for JSON maps coming from the API
/// (MySQL DECIMAL values arrive as strings, ids as ints).
typedef Json = Map<String, dynamic>;

Json asJson(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Json> asJsonList(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Json>[];

extension JsonRead on Map<String, dynamic> {
  /// 016: the machine's type with its fixed number inside its vendor, e.g. "Excavator #3" (the plain type before a number exists).
  String get machineType => strOrNull('machine_label') ?? str('type_name');

  /// 016: "EQ-0012 · Excavator #3" (just the code when the machine has no number yet).
  String get machineName {
    final label = strOrNull('machine_label');
    return label == null ? str('equipment_code') : '${str('equipment_code')} · $label';
  }

  String str(String key, [String fallback = '']) {
    final v = this[key];
    return v == null ? fallback : v.toString();
  }

  String? strOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  int intv(String key, [int fallback = 0]) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? fallback;
  }

  int? intOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  double dbl(String key, [double fallback = 0]) {
    final v = this[key];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fallback;
  }

  double? dblOrNull(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  bool flag(String key) {
    final v = this[key];
    return v == true || v == 1 || v == '1' || v == 'true';
  }

  Json obj(String key) => asJson(this[key]);

  Json? objOrNull(String key) => this[key] is Map ? asJson(this[key]) : null;

  List<Json> list(String key) => asJsonList(this[key]);
}
