import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RegisteredFace {
  RegisteredFace({required this.name, required this.embedding});

  final String name;
  final List<double> embedding;

  Map<String, dynamic> toJson() => {'name': name, 'embedding': embedding};

  static RegisteredFace fromJson(Map<String, dynamic> json) {
    return RegisteredFace(
      name: (json['name'] as String?) ?? '',
      embedding: ((json['embedding'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }
}

class LocalFaceStore {
  static const String _key = 'registered_faces_v1';

  Future<List<RegisteredFace>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => RegisteredFace.fromJson(m.cast<String, dynamic>()))
          .where((f) => f.name.trim().isNotEmpty && f.embedding.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(RegisteredFace face) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all.add(face);
    await prefs.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

