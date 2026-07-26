import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final query = 'lord of the mysteries';
  final tmdbApiKey = '0eca402bce9c731c02509d4671c72d6f';
  
  final uri = Uri.https('api.themoviedb.org', '/3/search/multi', {
    'api_key': tmdbApiKey,
    'query': query,
    'language': 'en-US',
    'include_adult': 'false',
  });

  final res = await http.get(uri);
  if (res.statusCode != 200) {
    print('Error: ${res.statusCode}');
    return;
  }

  final body = json.decode(res.body) as Map<String, dynamic>;
  final results = (body['results'] as List<dynamic>? ?? []);
  
  for (var r in results) {
    print('Type: ${r['media_type']}, Title: ${r['title'] ?? r['name']}, Original Title: ${r['original_title'] ?? r['original_name']}, Poster: ${r['poster_path']}');
  }
}
