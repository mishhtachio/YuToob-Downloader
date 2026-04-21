import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _configuredBaseUrl =
      String.fromEnvironment("API_BASE_URL", defaultValue: "");
  static const String _fallbackLanBaseUrl = "http://192.168.137.1:8000";
  static const Duration _requestTimeout = Duration(seconds: 12);
  static const MethodChannel _fileChannel = MethodChannel("yt_downloader/files");

  static String? _activeBaseUrl;

  static bool isYoutubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return false;
    }

    return host == "youtu.be" ||
        host == "youtube.com" ||
        host == "www.youtube.com" ||
        host == "m.youtube.com" ||
        host == "music.youtube.com" ||
        host.endsWith(".youtube.com");
  }

  static bool looksLikeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return false;
    }

    return trimmed.startsWith("www.") ||
        trimmed.contains("://") ||
        uri.hasScheme ||
        uri.host.isNotEmpty;
  }

  static bool isMissingRemoteJobError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains("invalid job_id") ||
        normalized.contains("progress fetch failed (404)") ||
        normalized.contains("download start failed (404)") ||
        normalized.contains("file not ready (409)");
  }

  static String formatErrorMessage(
    Object error, {
    String fallbackMessage = "Something went wrong.",
  }) {
    if (error is TimeoutException) {
      return "The request took too long. Check your network and try again.";
    }

    if (error is MissingPluginException) {
      return "Phone saving is unavailable until the app is fully rebuilt and reinstalled.";
    }

    if (error is PlatformException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    final raw = error.toString().trim();
    final cleaned = raw
        .replaceFirst(RegExp(r"^Exception:\s*"), "")
        .replaceFirst(RegExp(r"^PlatformException\([^)]+\):\s*"), "")
        .trim();

    if (cleaned.isEmpty) {
      return fallbackMessage;
    }

    final normalized = cleaned.toLowerCase();
    if (normalized.contains("socketexception") ||
        normalized.contains("connection refused") ||
        normalized.contains("failed host lookup") ||
        normalized.contains("xmlhttprequest error") ||
        normalized.contains("network is unreachable")) {
      return "Could not reach the API server. Check your connection and make sure the backend is running.";
    }

    return cleaned;
  }

  static List<String> get _baseUrlCandidates {
    final urls = <String>[];

    void addUrl(String url) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || urls.contains(trimmed)) {
        return;
      }
      urls.add(trimmed);
    }

    addUrl(_configuredBaseUrl);

    if (kIsWeb) {
      addUrl("http://localhost:8000");
      addUrl("http://127.0.0.1:8000");
      addUrl(_fallbackLanBaseUrl);
      return urls;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      addUrl("http://10.0.2.2:8000");
    }

    addUrl("http://127.0.0.1:8000");
    addUrl("http://localhost:8000");
    addUrl(_fallbackLanBaseUrl);

    return urls;
  }

  static Future<http.Response> _request(
    Future<http.Response> Function(String baseUrl) send,
  ) async {
    final candidates = <String>[
      ?_activeBaseUrl,
      ..._baseUrlCandidates.where((url) => url != _activeBaseUrl),
    ];

    Object? lastError;

    for (final baseUrl in candidates) {
      try {
        final response = await send(baseUrl).timeout(_requestTimeout);
        _activeBaseUrl = baseUrl;
        return response;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      "Could not reach the API server. Check your network, make sure the "
      "backend is running, or pass "
      "--dart-define=API_BASE_URL=http://YOUR_HOST:8000"
      "${lastError == null ? "" : " (${formatErrorMessage(lastError)})"}",
    );
  }

  static String _extractError(http.Response response, String fallbackMessage) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (body["error"] != null) {
          return body["error"].toString();
        }
        if (body["detail"] != null) {
          return body["detail"].toString();
        }
      }
    } catch (_) {
      // Ignore JSON parsing errors and fall back to a generic message.
    }

    return "$fallbackMessage (${response.statusCode})";
  }

  static Future<Map<String, dynamic>> fetchInfo(String url) async {
    final response = await _request(
      (baseUrl) => http.get(
        Uri.parse("$baseUrl/info").replace(
          queryParameters: {"url": url},
        ),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response, "Failed to fetch info"));
    }

    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> search(String query) async {
    final response = await _request(
      (baseUrl) => http.get(
        Uri.parse("$baseUrl/search").replace(
          queryParameters: {"query": query},
        ),
      ),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data["results"] == null) {
      throw Exception(_extractError(response, "Search failed"));
    }

    return data["results"];
  }

  static Future<String> startDownload(
    String url, {
    String format = "mp3",
    String quality = "192",
  }) async {
    final response = await _request(
      (baseUrl) => http.post(
        Uri.parse("$baseUrl/download"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "url": url,
          "format_type": format,
          "quality": quality,
        }),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response, "Download start failed"));
    }

    return jsonDecode(response.body)["job_id"];
  }

  static Future<void> downloadToPhone(
    String jobId, {
    String formatType = "mp3",
    String? title,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw Exception("Saving to public downloads is only configured on Android.");
    }

    final baseUrl = _activeBaseUrl ?? _baseUrlCandidates.first;
    final url = "$baseUrl/file/$jobId";
    final extension = formatType == "mp4" ? "mp4" : "mp3";
    final mimeType = formatType == "mp4" ? "video/mp4" : "audio/mpeg";
    final fileName = "${_safeFileName(title)}.$extension";

    try {
      await _fileChannel.invokeMethod("saveUrlToDownloads", {
        "url": url,
        "fileName": fileName,
        "mimeType": mimeType,
      });
    } on PlatformException catch (error) {
      throw Exception(
        formatErrorMessage(
          error,
          fallbackMessage: "Could not save the file to your phone.",
        ),
      );
    } on MissingPluginException catch (error) {
      throw Exception(
        formatErrorMessage(
          error,
          fallbackMessage: "Phone saving is unavailable in this build.",
        ),
      );
    }
  }

  static String _safeFileName(String? title) {
    final raw = (title ?? "").trim();
    if (raw.isEmpty) {
      return "video";
    }

    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();

    if (cleaned.isEmpty) {
      return "video";
    }

    return cleaned.length <= 100 ? cleaned : cleaned.substring(0, 100).trim();
  }

  static Future<Map<String, dynamic>> getProgress(String jobId) async {
    final response = await _request(
      (baseUrl) => http.get(
        Uri.parse("$baseUrl/progress/$jobId"),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response, "Progress fetch failed"));
    }

    return jsonDecode(response.body);
  }

  static Future<void> cancel(String jobId) async {
    final response = await _request(
      (baseUrl) => http.post(
        Uri.parse("$baseUrl/cancel/$jobId"),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response, "Cancel failed"));
    }
  }
}
