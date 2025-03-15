import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart';

// Functie om afbeeldingen uit HTML te halen
String extractImageUrl(String htmlContent) {
  var document = parse(htmlContent);
  var imgTag = document.querySelector('img');
  return imgTag?.attributes['src'] ?? "";
}

// Haal RSS-feed op en converteer naar JSON
Future<Response> fetchRssFeed(Request request) async {
  final params = request.url.queryParameters;
  final feedUrl = params['url'];

  if (feedUrl == null) {
    return Response.badRequest(body: jsonEncode({"error": "Geen RSS URL opgegeven"}));
  }

  try {
    final response = await http.get(Uri.parse(feedUrl));

    if (response.statusCode == 200) {
      final feed = RssFeed.parse(response.body);
      List<Map<String, dynamic>> articles = [];

      for (var item in feed.items.take(5)) {
        articles.add({
          "title": item.title ?? "Geen titel",
          "link": item.link ?? "",
          "published": item.pubDate ?? "Geen datum",
          "summary": item.description ?? "Geen samenvatting",
          "image": extractImageUrl(item.description ?? "") // Extract afbeelding
        });
      }

      return Response.ok(jsonEncode({"articles": articles}), headers: {'Content-Type': 'application/json'});
    } else {
      return Response.internalServerError(body: jsonEncode({"error": "Fout bij ophalen van RSS"}));
    }
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({"error": "Serverfout: $e"}));
  }
}

void main() async {
  final router = Router();
  router.get('/rss', fetchRssFeed);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('🚀 Server draait op http://${server.address.host}:${server.port}');
}
