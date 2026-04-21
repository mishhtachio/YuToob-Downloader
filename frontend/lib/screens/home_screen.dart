import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/api_service.dart';
import 'download_detail_screen.dart';
import '../widgets/quality_selector.dart';

class HomeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> downloads;
  final Function(Map<String, dynamic>) onAddDownload;

  const HomeScreen({
    super.key,
    required this.downloads,
    required this.onAddDownload,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController controller = TextEditingController();

  Map<String, dynamic>? latestJob;
  Map<String, dynamic>? selectedVideo;
  List results = [];
  bool loading = false;
  String? statusMessage;

  Timer? clipboardTimer;
  String lastClipboardContent = "";
  String? detectedClipboardLink;
  // Persist across widget rebuilds in the same session
  static bool _clipboardNotificationShown = false;
  List lastResults = [];

  @override
  void initState() {
    super.initState();
    startClipboardMonitoring();
  }

  @override
  void dispose() {
    clipboardTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void startClipboardMonitoring() {
    clipboardTimer = Timer.periodic(Duration(seconds: 2), (_) async {
      try {
        final data = await Clipboard.getData('text/plain');
        if (data == null || data.text == null) return;

        final text = data.text!.trim();

        // Only process if content changed and it's a YouTube URL
        if (text != lastClipboardContent && ApiService.isYoutubeUrl(text)) {
          lastClipboardContent = text;
          
          if (!mounted) return;

          // update detected link in the state
          setState(() {
            detectedClipboardLink = text;
          });

          // Show notification only once per app session (persisted across
          // HomeScreen rebuilds). Use a microtask to ensure setState has
          // completed before showing a SnackBar.
          if (!_clipboardNotificationShown) {
            _clipboardNotificationShown = true;
            Future.microtask(() {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("YouTube link ready in clipboard"),
                    duration: Duration(seconds: 2),
                    backgroundColor: Color(0xFFFF2D2D),
                  ),
                );
              }
            });
          }
        }
      } catch (e) {
        // Silently ignore errors reading clipboard
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    if (widget.downloads.isNotEmpty) {
      latestJob = widget.downloads.last;
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> handleInput() async {
    final input = controller.text.trim();
    if (input.isEmpty) return;

    setState(() {
      loading = true;
      selectedVideo = null;
      results = [];
      statusMessage = null;
    });

    try {
      if (ApiService.isYoutubeUrl(input)) {
        final data = await ApiService.fetchInfo(input);

        if (!mounted) return;
        setState(() {
          selectedVideo = data;
        });
      } else {
        final res = await ApiService.search(input);

        if (!mounted) return;
        setState(() {
          results = res;
          lastResults = res;
          if (res.isEmpty) {
            statusMessage = 'No results found for "$input".';
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst("Exception: ", "");

      setState(() {
        statusMessage = message;
      });
    }

    if (!mounted) return;
    setState(() {
      loading = false;
    });
  }

  Future<void> pasteFromClipboard() async {
    // Use detected link if available, otherwise read from clipboard
    String? text = detectedClipboardLink;
    
    if (text == null) {
      final data = await Clipboard.getData('text/plain');
      if (data == null || data.text == null) return;
      text = data.text!.trim();
    }

    if (!ApiService.isYoutubeUrl(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No valid YouTube link in clipboard")),
      );
      return;
    }

    setState(() {
      controller.text = text!;
    });
    
    await handleInput();
  }

  Future<void> startDownload(String url, String title,
      {String quality = "192"}) async {
    print("START DOWNLOAD: $url");

    final jobId = await ApiService.startDownload(
      url,
      quality: quality,
    );

    widget.onAddDownload({
      "job_id": jobId,
      "title": title,
      "progress": 0.0,
      "status": "starting",
      "saved": false,
      "format_type": "mp3",
    });
  }

  Widget fallbackThumb() {
    return Container(
      width: 80,
      height: 50,
      color: Colors.grey[800],
      child: Icon(Icons.image, color: Colors.white54),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(0xFFFF2D2D);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              /// HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.menu, color: Colors.white),
                  Column(
                    children: [
                      Text("YUUTOOB",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3)),
                      Text("DOWNLOADER",
                          style: TextStyle(
                              fontSize: 10,
                              color: accent,
                              letterSpacing: 2))
                    ],
                  ),
                  Icon(Icons.settings, color: Colors.white),
                ],
              ),

              SizedBox(height: 30),

              Text("SEARCH OR PASTE",
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Colors.white54)),

              SizedBox(height: 18),

              /// SEARCH BAR
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20),
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1A1A), Color(0xFF242424)],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.white54),
                    SizedBox(width: 12),

                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => handleInput(),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "Enter YouTube link or search term...",
                          hintStyle: TextStyle(color: Colors.white38),
                        ),
                      ),
                    ),

                    GestureDetector(
                      onTap: handleInput,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text("SEARCH",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.black)),
                      ),
                    )
                  ],
                ),
              ),

              SizedBox(height: 20),

              if (loading) CircularProgressIndicator(),

              if (!loading && statusMessage != null)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 20),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    statusMessage!,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),

              /// SEARCH RESULTS
              if (results.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final v = results[i];

                      final thumbnail = v["thumbnail"];
                      final title = v["title"] ?? "No title";
                      final uploader = v["uploader"] ?? "Unknown";

                      return ListTile(
                        leading: thumbnail != null && thumbnail != ""
                            ? Image.network(
                                thumbnail,
                                width: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    fallbackThumb(),
                              )
                            : fallbackThumb(),

                        title: Text(title,
                            style: TextStyle(color: Colors.white)),

                        subtitle: Text(uploader,
                            style: TextStyle(color: Colors.white54)),

                        onTap: () {
                          print("SELECTED VIDEO: $v");

                          setState(() {
                            selectedVideo = v;
                            results = [];
                            statusMessage = null;
                          });
                        },
                      );
                    },
                  ),
                ),

              /// SELECTED VIDEO VIEW
              if (selectedVideo != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedVideo = null;
                              // Restore search results if they exist
                              if (lastResults.isNotEmpty) {
                                results = lastResults;
                              }
                            });
                          },
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back, color: Colors.white54, size: 20),
                                  SizedBox(width: 4),
                                  Text("BACK", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.network(
                            selectedVideo!["thumbnail"] ?? "",
                            width: double.infinity,
                            height: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              height: 220,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        Text(
                          selectedVideo!["title"] ?? "No title",
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                        SizedBox(height: 14),

                        GestureDetector(
                          onTap: () {
                            final url = selectedVideo!["url"];

                            print("DOWNLOAD URL: $url");

                            if (url == null || url.toString().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Invalid video URL")),
                              );
                              return;
                            }

                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.black,
                              builder: (_) => QualitySelector(
                                onSelect: (quality) {
                                  startDownload(
                                    url,
                                    selectedVideo!["title"] ?? "video",
                                    quality: quality,
                                  );
                                },
                              ),
                            );
                          },
                          child: Container(
                            margin: EdgeInsets.only(top: 12),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                "DOWNLOAD",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),

              /// DEFAULT GRID
              if (selectedVideo == null &&
                  results.isEmpty &&
                  statusMessage == null)
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      GestureDetector(
                        onTap: pasteFromClipboard,
                        child: buildTile(Icons.content_paste, "CLIPBOARD",
                            "Auto-detect link"),
                      ),
                      buildTile(Icons.history, "HISTORY", "24 items saved"),
                      buildTile(Icons.public, "BROWSER", "In-app search"),
                      buildTile(Icons.folder, "FILES", "Manage storage"),
                      if (latestJob != null)
                        buildActivityCard(latestJob!, accent),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTile(IconData icon, String title, String subtitle) {
    final accent = Color(0xFFFF2D2D);

    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent),
          SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.white)),
          Text(subtitle, style: TextStyle(color: Colors.white54))
        ],
      ),
    );
  }

  Widget buildActivityCard(Map job, Color accent) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DownloadDetailScreen(
              job: Map<String, dynamic>.from(job),
            ),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              height: 50,
              width: 50,
              child: CircularProgressIndicator(
                value: job["progress"],
                color: accent,
                backgroundColor: Colors.white10,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                job["title"],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white)
          ],
        ),
      ),
    );
  }
}
