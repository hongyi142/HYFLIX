import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final res = await http.get(Uri.parse('https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/'));
  final body = json.decode(res.body);
  print(json.encode(body['class']));
}
