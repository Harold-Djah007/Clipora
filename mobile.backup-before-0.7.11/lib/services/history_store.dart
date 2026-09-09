import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_models.dart';

class HistoryStore {
  static const _key = 'threadvault_history_v1';

  Future<List<DownloadRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return DownloadRecord.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DownloadRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, DownloadRecord.encodeList(records.take(500).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
