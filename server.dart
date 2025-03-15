import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart';

// ✅ Bekende RSS-feeds database
Map<String, List<String>> knownRssFeeds = {
  "nos.nl": ["https://feeds.nos.nl/nosnieuwsalgemeen"],
  "bbc.com": ["https://feeds.bbci.co.uk/news/rss.xml", "https://feeds.bbci.co.uk/sport/rss.xml"],
  "cnn.com": ["http://rss.cnn.com/rss/edition.rss"],
  "nu.nl": ["https://www.nu.nl/rss/Algemeen"],
  "techcrunch.com": ["https://feeds.feedburner.com/TechCrunch/"],
  "verge.com": ["https://www.theverge.com/rss/index.xml"],
  "reddit.com": ["https://www.reddit.com/.rss"],
  "nasa.gov": ["https://www.nasa.gov/rss/dyn/breaking_news.rss"],
  "wired.com": ["https://www.wired.com/feed/rss"],
  "github.com": ["https://github.com/trending/rss"],
};

// ✅ Zoek automatisch een RSS-feed als een gebruiker alleen een domeinnaam invult
Future<String?> findRssFeed(String websiteUrl) async {
  try {
    if (!websiteUrl.startsWith("http")) {
      websiteUrl = "https://$websiteUrl";
    }

    // Check of de site al in de database staat
    Uri parsedUrl = Uri.parse(websiteUrl);
    String? knownFeed = knownRssFeeds[parsedUrl.host]?.first;
    if (knownFeed != null) {
      print("✅ Gebruik bekende RSS-feed voor $websiteUrl: $knownFeed");
      return knownFeed;
    }

    // Zoek een RSS-feed in de HTML <link> tags
    final response = await http.get(Uri.parse(websiteUrl));
    if (response.statusCode == 200) {
      var document = parse(response.body);
      var links = document.getElementsByTagName('link');

      for (var link in links) {
        var rel = link.attributes['rel'] ?? "";
        var type = link.attributes['type'] ?? "";

        if (rel.contains("alternate") && type.contains("rss")) {
          String? feedUrl = link.attributes['href'];

          // Fix relatieve URL's
          if (feedUrl != null && !feedUrl.startsWith("http")) {
            Uri baseUri = Uri.parse(websiteUrl);
            feedUrl = Uri.parse(baseUri.origin + feedUrl).toString();
          }

          print("✅ RSS-feed gevonden: $feedUrl");
          return feedUrl;
        }
      }
    }
  } catch (e) {
    print("❌ Fout bij het vinden van RSS-feed: $e");
  }

  return null;
}

// ✅ Haal een afbeelding op uit de RSS-feed
String extractImageUrl(RssItem item) {
  if (item.media?.thumbnails?.isNotEmpty ?? false) {
    return item.media!.thumbnails!.first.url!;
  }
  if (item.enclosure?.url != null) {
    return item.enclosure!.url!;
  }

  // Zoek afbeelding in description/content
  String? htmlContent = item.content?.value ?? item.description;
  if (htmlContent != null) {
    var document = parse(htmlContent);
    var imgTag = document.querySelector('img');
    if (imgTag != null && imgTag.attributes.containsKey('src')) {
      return imgTag.attributes['src']!;
    }
  }

  return "https://via.placeholder.com/300x200?text=No+Image";
}

// ✅ Haal RSS-feed op en converteer naar JSON
Future<Response> fetchRssFeed(Request request) async {
  final params = request.url.queryParameters;
  String? feedUrl = params['url'];

  if (feedUrl == null) {
    return Response.badRequest(body: jsonEncode({"error": "Geen URL opgegeven"}));
  }

  // 🚀 Zoek automatisch een RSS-feed als de gebruiker alleen een website intypt
  if (!feedUrl.endsWith(".xml") && !feedUrl.contains("rss")) {
    print("🔍 Probeer RSS-feed te vinden voor $feedUrl...");
    feedUrl = await findRssFeed(feedUrl);
    if (feedUrl == null) {
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
          "image": extractImageUrl(item),
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

// ✅ Endpoint om de lijst met bekende feeds te sturen naar FlutterFlow
Future<Response> getKnownFeeds(Request request) async {
  return Response.ok(
    jsonEncode(knownRssFeeds),
    headers: {'Content-Type': 'application/json'},
  );
}

// ✅ Start de server
void main() async {
  final router = Router();
  router.get('/rss', fetchRssFeed);
  router.get('/known-feeds', getKnownFeeds);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('🚀 Server draait op http://${server.address.host}:${server.port}');
}

