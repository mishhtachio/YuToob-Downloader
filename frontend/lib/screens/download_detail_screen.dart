import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({required this.progress, required this.color, this.strokeWidth = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // full background circle
    canvas.drawArc(rect, 0, 2 * math.pi, false, bgPaint);

    // foreground arc starting at top (-90 degrees)
    final start = -math.pi / 2;
    final sweep = (progress.clamp(0.0, 1.0)) * 2 * math.pi;
    canvas.drawArc(rect, start, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class DownloadDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const DownloadDetailScreen({super.key, required this.job});

  @override
  State<DownloadDetailScreen> createState() =>
      _DownloadDetailScreenState();
}

class _DownloadDetailScreenState extends State<DownloadDetailScreen> {
  late Map<String, dynamic> jobState;
  Timer? timer;

  bool highQuality = true;
  bool stayAwake = false;

  @override
  void initState() {
    super.initState();
    jobState = Map.from(widget.job);
    startPolling();
  }

  void startPolling() {
    timer = Timer.periodic(Duration(milliseconds: 500), (_) async {
      final data =
          await ApiService.getProgress(jobState["job_id"]);

      if (!mounted) return;

      setState(() {
        jobState["progress"] =
            (data["progress"] ?? 0) / 100;

        if (data["status"] == "processing") {
          jobState["progress"] = 0.95;
        }

        jobState["status"] = data["status"];
        jobState["speed"] = data["speed"] ?? 0;
        jobState["eta"] = data["eta"] ?? 0;
      });

      if (data["status"] == "completed" ||
          data["status"] == "error" ||
          data["status"] == "cancelled") {
        timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(0xFFFF2D2D);
    final progress = jobState["progress"] ?? 0.0;
    final speedMbps = ((jobState["speed"] ?? 0) / (1024 * 1024)).toDouble();
    final screenWidth = MediaQuery.of(context).size.width;
    final progressSize = math.min(320.0, math.max(260.0, screenWidth - 72));
    final innerSize = progressSize - 56;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.menu),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "NOTHING DOWNLOAD",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(letterSpacing: 2, fontSize: 12),
                          ),
                        ),
                      ),
                      Icon(Icons.grid_view_rounded, size: 18),
                    ],
                  ),

                  SizedBox(height: 24),

                  SizedBox(
                    height: progressSize,
                    width: progressSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size(progressSize, progressSize),
                          painter: _RingPainter(
                            progress: progress,
                            color: accent,
                            strokeWidth: 16,
                          ),
                        ),
                        Container(
                          height: innerSize,
                          width: innerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF101010),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "${(progress * 100).toInt()}",
                                  style: TextStyle(
                                    fontSize: 82,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "PERCENT",
                                style: TextStyle(
                                  letterSpacing: 2,
                                  color: accent,
                                  fontSize: 10,
                                ),
                              ),
                              SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 6,
                                    width: 6,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      jobState["status"] ?? "DOWNLOADING",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  )
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  Container(
                    padding: EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jobState["title"] ?? "",
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${speedMbps.toStringAsFixed(1)} MB/s",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text("CURRENT SPEED",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white54))
                                ],
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "${jobState["eta"] ?? 0}s",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 20,
                                        color: accent,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text("TIME REMAINING",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white54))
                                ],
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(child: buildSmallButton(Icons.pause, "PAUSE")),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            ApiService.cancel(jobState["job_id"]);
                          },
                          child: buildPrimaryButton(),
                        ),
                      ),
                      Expanded(child: buildSmallButton(Icons.share, "SHARE")),
                    ],
                  ),

                  SizedBox(height: 16),

                  buildToggle("HIGH QUALITY", "4K UHD Enabled",
                      highQuality, (v) => setState(() => highQuality = v)),

                  SizedBox(height: 10),

                  buildToggle("STAY AWAKE", "Screen stays on",
                      stayAwake, (v) => setState(() => stayAwake = v)),

                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSmallButton(IconData icon, String label) {
    return Container(
      height: 60,
      margin: EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Color(0xFF1E1E1E),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10))
        ],
      ),
    );
  }

  Widget buildPrimaryButton() {
    return Container(
      height: 60,
      margin: EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Color(0xFFFF2D2D),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.close, color: Colors.black),
          SizedBox(height: 4),
          Text("CANCEL",
              style: TextStyle(fontSize: 10, color: Colors.black))
        ],
      ),
    );
  }

  Widget buildToggle(String t, String s, bool val, Function(bool) onChanged) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Color(0xFF1E1E1E),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: 4),
                Text(
                  s,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                )
              ],
            ),
          ),
          SizedBox(width: 12),
          Switch(
            value: val,
            onChanged: onChanged,
            activeThumbColor: Color(0xFFFF2D2D),
          )
        ],
      ),
    );
  }
}
