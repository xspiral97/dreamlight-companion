import 'dart:convert';

Map<String, dynamic> mergeCatalogDetails(String? oldJson, String incomingJson) {
  final old = oldJson == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(jsonDecode(oldJson));
  final incoming = Map<String, dynamic>.from(jsonDecode(incomingJson));
  final result = <String, dynamic>{
    ...old,
    ...incoming,
    'fields': {...?(old['fields'] as Map?), ...?(incoming['fields'] as Map?)},
  };
  if (incoming['summary'] == true && old['summary'] == false) {
    result['summary'] = false;
    result['blocks'] = old['blocks'] ?? [];
    result['links'] = old['links'] ?? [];
  }
  return result;
}

Map<String, dynamic> validateCatalogSnapshot(dynamic snapshot) {
  if (snapshot is! Map ||
      snapshot['schemaVersion'] != 2 ||
      snapshot['records'] is! List ||
      (snapshot['records'] as List).isEmpty) {
    throw const FormatException('Unsupported or empty catalog feed');
  }
  final ids = <String>{};
  for (final row in snapshot['records']) {
    if (row is! Map ||
        row['id'] is! String ||
        row['title'] is! String ||
        row['categories'] is! String ||
        row['details'] is! String ||
        !ids.add(row['id'])) {
      throw const FormatException('Invalid catalog record');
    }
    if (jsonDecode(row['categories']) is! List ||
        jsonDecode(row['details']) is! Map) {
      throw const FormatException('Invalid catalog data');
    }
  }
  return Map<String, dynamic>.from(snapshot);
}
