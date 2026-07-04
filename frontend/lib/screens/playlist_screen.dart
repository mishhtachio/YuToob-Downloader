import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/quality_selector.dart';

class PlaylistScreen extends StatefulWidget {
  final String playlistUrl;
  final Color accentColor;
  final Function(Map<String, dynamic>) onAddDownload;
  final String? initialTitle;
  final String? initialThumbnail;
  final String? initialUploader;

  const PlaylistScreen({
    super.key,
    required this.playlistUrl,
    required this.accentColor,
    required this.onAddDownload,
    this.initialTitle,
    this.initialThumbnail,
    this.initialUploader,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  Map<String, dynamic>? playlistData;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPlaylist();
  }

  Future<void> _fetchPlaylist() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final data = await ApiService.fetchPlaylistInfo(widget.playlistUrl);
      if (!mounted) return;
      setState(() {
        playlistData = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst("Exception: ", "");
        loading = false;
      });
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return "--:--";
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Future<void> _downloadIndividualTrack(Map<String, dynamic> track) async {
    final url = track["url"];
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid track URL")),
      );
      return;
    }

    final isWifiOnly = StorageService.getWifiOnly();
    if (isWifiOnly) {
      final isWifi = await ApiService.isWifiConnected();
      if (!isWifi) {
        _showWifiWarning();
        return;
      }
    }

    int? duration;
    if (track["duration"] != null) {
      if (track["duration"] is int) {
        duration = track["duration"] as int;
      } else if (track["duration"] is double) {
        duration = (track["duration"] as double).toInt();
      } else {
        duration = int.tryParse(track["duration"].toString());
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QualitySelector(
        title: track["title"],
        thumbnailUrl: track["thumbnail"],
        uploader: track["uploader"],
        duration: duration,
        onSelect: (quality) async {
          try {
            final jobId = await ApiService.startDownload(
              url,
              quality: quality,
              concurrentThreads: StorageService.getConcurrentThreads(),
            );

            widget.onAddDownload({
              "job_id": jobId,
              "title": track["title"] ?? "Track",
              "progress": 0.0,
              "status": "starting",
              "saved": false,
              "format_type": "mp3",
              "thumbnail": track["thumbnail"] ?? "",
              "uploader": track["uploader"] ?? "Unknown",
            });

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Started download: ${track["title"]}"),
                backgroundColor: widget.accentColor,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Failed to start download: ${ApiService.formatErrorMessage(e)}"),
                backgroundColor: widget.accentColor,
              ),
            );
          }
        },
      ),
    );
  }

  void _showWifiWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("WiFi Only Enabled", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: const Text(
          "Your settings restrict downloads to WiFi networks only. Please connect to a WiFi network or disable this option in settings.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAll() async {
    if (playlistData == null) return;

    final isWifiOnly = StorageService.getWifiOnly();
    if (isWifiOnly) {
      final isWifi = await ApiService.isWifiConnected();
      if (!isWifi) {
        _showWifiWarning();
        return;
      }
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QualitySelector(
        title: playlistData!["title"],
        thumbnailUrl: playlistData!["thumbnail"],
        uploader: playlistData!["uploader"],
        onSelect: (quality) async {
          try {
            // Show start toast
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Requesting download for ${playlistData!["video_count"]} tracks..."),
                duration: const Duration(seconds: 2),
              ),
            );

            final result = await ApiService.downloadPlaylist(
              widget.playlistUrl,
              quality: quality,
              concurrentThreads: StorageService.getConcurrentThreads(),
            );

            final String playlistId = result["playlist_id"];
            final String playlistTitle = result["playlist_title"];
            final List jobIds = result["job_ids"] ?? [];

            for (var job in jobIds) {
              final jobId = job["job_id"];
              final title = job["title"];
              final thumbnail = job["thumbnail"];
              final uploader = job["uploader"];

              widget.onAddDownload({
                "job_id": jobId,
                "title": title,
                "progress": 0.0,
                "status": "starting",
                "saved": false,
                "format_type": "mp3",
                "thumbnail": thumbnail ?? "",
                "uploader": uploader ?? "Unknown",
                "playlist_id": playlistId,
                "playlist_title": playlistTitle,
              });
            }

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Successfully added ${jobIds.length} tracks to downloads!"),
                backgroundColor: widget.accentColor,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Failed to download playlist: ${ApiService.formatErrorMessage(e)}"),
                backgroundColor: widget.accentColor,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = playlistData?["title"] ?? widget.initialTitle ?? "Loading Playlist...";
    final thumbnail = playlistData?["thumbnail"] ?? widget.initialThumbnail ?? "";
    final uploader = playlistData?["uploader"] ?? widget.initialUploader ?? "YouTube Playlist";
    final count = playlistData?["video_count"] ?? 0;
    final entries = (playlistData?["entries"] as List?) ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back Button and Header Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "PLAYLIST",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            if (loading && playlistData == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: widget.accentColor),
                      const SizedBox(height: 16),
                      const Text(
                        "Extracting playlist information...",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (errorMessage != null && playlistData == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _fetchPlaylist,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text("RETRY"),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              // Playlist Header Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 100,
                        height: 70,
                        color: Colors.white.withOpacity(0.04),
                        child: thumbnail.isNotEmpty
                            ? Image.network(
                                thumbnail,
                                width: 100,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.playlist_play_rounded, color: Colors.white30, size: 36),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.playlist_play_rounded, color: Colors.white30, size: 36),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            uploader,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "$count ${count == 1 ? 'video' : 'videos'}",
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Action buttons (DOWNLOAD ALL)
              if (entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                  ).child(
                    onPressed: _downloadAll,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.download_for_offline_rounded, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "DOWNLOAD ALL ($count TRACKS)",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Tracks label
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "TRACKS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white38,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Tracks List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (context, idx) {
                    final track = entries[idx];
                    final trackThumb = track["thumbnail"] ?? "";
                    final trackTitle = track["title"] ?? "No Title";
                    final trackUploader = track["uploader"] ?? "Unknown";
                    final durationText = _formatDuration(track["duration"]);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101012),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.03),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 60,
                            height: 40,
                            color: Colors.white.withOpacity(0.04),
                            child: trackThumb.isNotEmpty
                                ? Image.network(
                                    trackThumb,
                                    width: 60,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.music_note_rounded, color: Colors.white30, size: 20),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.music_note_rounded, color: Colors.white30, size: 20),
                                  ),
                          ),
                        ),
                        title: Text(
                          trackTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                trackUploader,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              durationText,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.download_rounded, color: widget.accentColor, size: 20),
                          onPressed: () => _downloadIndividualTrack(track),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on ButtonStyle {
  Widget child({required VoidCallback? onPressed, required Widget child}) {
    return ElevatedButton(
      style: this,
      onPressed: onPressed,
      child: child,
    );
  }
}
