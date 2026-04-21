import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DownloadsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> downloads;

  const DownloadsScreen({super.key, required this.downloads});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "DOWNLOADS",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: downloads.length,
                  itemBuilder: (context, index) {
                    final job = downloads[index];

                    return Container(
                      margin: EdgeInsets.only(bottom: 16),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            height: 90,
                            width: 90,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: job["progress"],
                                  strokeWidth: 6,
                                  backgroundColor:
                                      theme.scaffoldBackgroundColor,
                                  valueColor: AlwaysStoppedAnimation(
                                      theme.colorScheme.primary),
                                ),
                                AnimatedSwitcher(
                                  duration: Duration(milliseconds: 300),
                                  child: Text(
                                    "${(job["progress"] * 100).toStringAsFixed(0)}%",
                                    key: ValueKey(job["progress"]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job["title"],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  job["status"],
                                  style: TextStyle(
                                    color: theme.textTheme.bodySmall!.color,
                                  ),
                                ),
                                if (job["save_status"] != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      job["save_status"] == "saving_to_phone"
                                          ? "Saving to phone..."
                                          : job["save_status"] == "saved_to_phone"
                                              ? "Saved to phone"
                                              : (job["save_error"] ??
                                                  "Phone save failed"),
                                      style: TextStyle(
                                        color: job["save_status"] == "saved_to_phone"
                                            ? Colors.greenAccent
                                            : theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                SizedBox(height: 6),
                                if (job["speed"] != null)
                                  Text(
                                      "${(job["speed"] / 1024).toStringAsFixed(1)} KB/s"),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                ApiService.cancel(job["job_id"]),
                            icon: Icon(Icons.close),
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
