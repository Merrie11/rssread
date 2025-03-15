import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart';

// ✅ Functie om een RSS-feed te vinden als een gewone website wordt ingevoerd
Future<String?> findRssFeed(String websiteUrl) async {
  try {
    if (!websiteUrl.startsWith("http")) {
      websiteUrl = "https://$websiteUrl";
    }

    final response = await http.get(Uri.parse(websiteUrl));

    if (response.statusCode == 200) {
      var document = parse(response.body);
      var links = document.getElementsByTagName('link');

      for (var link in links) {
        var rel = link.attributes['rel'] ?? "";
        var type = link.attributes['type'] ?? "";

        if (rel.contains("alternate") && type.contains("rss")) {
          String? feedUrl = link.attributes['href'];

          // Fix voor relatieve URL's (zoals "/rss.xml" -> "https://nos.nl/rss.xml")
          if (feedUrl != null && !feedUrl.startsWith("http")) {
            Uri baseUri = Uri.parse(websiteUrl);
            feedUrl = Uri.parse(baseUri.origin + feedUrl).toString();
          }

          print("✅ RSS-feed gevonden: $feedUrl"); // Debug message
          return feedUrl;
        }
      }

      // 🔥 Extra check: Sommige websites zetten feeds in hun robots.txt
      var robotsUrl = Uri.parse("$websiteUrl/robots.txt");
      var robotsResponse = await http.get(robotsUrl);
      if (robotsResponse.statusCode == 200) {
        var robotsText = robotsResponse.body;
        RegExp regex = RegExp(r"(https?:\/\/[^\s]+\.xml)", caseSensitive: false);
        var matches = regex.allMatches(robotsText);

        for (var match in matches) {
          print("✅ RSS-feed gevonden in robots.txt: ${match.group(0)}");
          return match.group(0);
        }
      }
    }
  } catch (e) {
    print("❌ Fout bij het vinden van RSS-feed: $e");
  }
  return null;
}

// ✅ Functie om afbeeldingen uit HTML te halen
String extractImageUrl(RssItem item) {
  if (item.media?.thumbnails?.isNotEmpty ?? false) {
    return item.media!.thumbnails!.first.url!;
  }
  if (item.enclosure?.url != null) {
    return item.enclosure!.url!;
  }

  String? htmlContent = item.content?.value ?? item.description;
  if (htmlContent != null) {
    var document = parse(htmlContent);
    var imgTag = document.querySelector('img');
    if (imgTag != null && imgTag.attributes.containsKey('src')) {
      return imgTag.attributes['src']!;
    }
  }
  return "";
}

// ✅ Haal RSS-feed op en converteer naar JSON
Future<Response> fetchRssFeed(Request request) async {
  final params = request.url.queryParameters;
  String? feedUrl = params['url'];

  if (feedUrl == null) {
    return Response.badRequest(body: jsonEncode({"error": "Geen URL opgegeven"}));
  }

  // 🚀 Controleer of het een website is en zoek automatisch een RSS-feed
  if (!feedUrl.endsWith(".xml") && !feedUrl.contains("rss")) {
    print("🔍 Probeer RSS-feed te vinden voor $feedUrl...");
    String? detectedFeed = await findRssFeed(feedUrl);
    
    if (detectedFeed != null) {
      print("✅ RSS-feed gevonden: $detectedFeed");
      feedUrl = detectedFeed;
    } else {
      return Response.badRequest(body: jsonEncode({"error": "Geen RSS-feed gevonden voor deze website"}));
    }
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
          "image": extractImageUrl(item)
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

// ✅ Start de server
void main() async {
  final router = Router();
  router.get('/rss', fetchRssFeed);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('🚀 Server draait op http://${server.address.host}:${server.port}');
}

