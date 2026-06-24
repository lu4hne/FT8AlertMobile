import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioManager {
  static Future<Directory> _getAudioDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/ft8_audios');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  static Future<List<File>> getSavedAudios() async {
    try {
      final dir = await _getAudioDirectory();
      final List<FileSystemEntity> entities = await dir.list().toList();
      return entities
          .whereType<File>()
          .where((file) => file.path.endsWith('.wav'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } catch (e) {
      print('Error reading audios: $e');
      return [];
    }
  }

  static Future<File?> downloadAndSaveAudio(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        String? filename;
        if (response.headers.containsKey('content-disposition')) {
          final contentDisposition = response.headers['content-disposition']!;
          final match = RegExp(r'filename="?([^";]+)"?').firstMatch(contentDisposition);
          if (match != null) {
            filename = match.group(1);
          }
        }
        
        // Fallback name if header is missing
        filename ??= 'FT8_Audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        final dir = await _getAudioDirectory();
        final filePath = '${dir.path}/$filename';
        final file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file;
      }
    } catch (e) {
      print('Error downloading audio: $e');
    }
    return null;
  }

  static Future<void> deleteAudio(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting audio: $e');
    }
  }
}
