import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'downloads_screen.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;

  List<Map<String, dynamic>> downloads = [];

  Timer? timer;
  bool isPolling = false;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    final savedDownloads = await StorageService.loadDownloads();
    if (mounted) {
      setState(() {
        downloads = savedDownloads;
      });
    }
  }

  Future<void> _saveDownloads() async {
    await StorageService.saveDownloads(downloads);
  }

  void startPolling() {
    if (isPolling) return;
    isPolling = true;

    timer?.cancel();

    timer = Timer.periodic(Duration(milliseconds: 700), (_) async {
      if (!mounted) return;

      for (var job in downloads) {
        // Skip polling for completed, cancelled, or error jobs
        final currentStatus = job["status"]?.toString().toLowerCase() ?? "";
        if (currentStatus == "completed" || 
            currentStatus == "cancelled" || 
            (currentStatus == "error" && job["error_checked"] == true)) {
          continue;
        }

        try {
          final data =
              await ApiService.getProgress(job["job_id"]);

          if (!mounted) return;

          setState(() {
            job["progress"] =
                (data["progress"] ?? 0) / 100;

            if (data["status"] == "processing") {
              job["progress"] = 0.95;
            }

            job["status"] = data["status"];
            job["speed"] = data["speed"] ?? 0;
            job["eta"] = data["eta"] ?? 0;
            job["downloaded"] = data["downloaded"] ?? 0;
            job["total"] = data["total"] ?? 0;
            job["format_type"] = data["format_type"] ?? job["format_type"] ?? "mp3";
          });

          if (data["status"] == "completed") {
            if (job["saved"] != true && job["save_status"] == null) {
              setState(() {
                job["save_status"] = "saving_to_phone";
              });

              print("TRIGGERING DOWNLOAD FOR ${job["job_id"]}");

              Future.delayed(Duration(seconds: 2), () async {
                try {
                  await ApiService.downloadToPhone(
                    job["job_id"],
                    formatType: job["format_type"] ?? "mp3",
                    title: job["title"],
                  );

                  if (!mounted) return;
                  setState(() {
                    job["saved"] = true;
                    job["save_status"] = "saved_to_phone";
                  });
                  _saveDownloads();
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    job["saved"] = false;
                    job["save_status"] = "phone_save_failed";
                    job["save_error"] =
                        e.toString().replaceFirst("Exception: ", "");
                  });
                  _saveDownloads();
                }
              });
            }
          }
          // Save downloads after each update
          _saveDownloads();
        } catch (e) {
          // Handle 404 errors gracefully - job not found on backend
          if (e.toString().contains("404") || e.toString().contains("not found")) {
            setState(() {
              job["status"] = "error";
              job["error_message"] = "Job not found on server";
              job["error_checked"] = true;
            });
          } else {
            setState(() {
              job["status"] = "error";
              job["error_message"] = e.toString();
              job["error_checked"] = true;
            });
          }
          _saveDownloads();
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    isPolling = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        downloads: downloads,
        onAddDownload: (job) {
          setState(() {
            downloads.add(job);
          });
          _saveDownloads();
          startPolling();
        },
      ),
      DownloadsScreen(downloads: downloads),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: screens[currentIndex],
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              navItem(Icons.search, 0),
              navItem(Icons.download, 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget navItem(IconData icon, int index) {
    final isActive = currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding:
            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.black : Colors.grey,
        ),
      ),
    );
  }
}
