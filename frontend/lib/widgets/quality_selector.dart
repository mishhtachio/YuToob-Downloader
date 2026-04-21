import 'package:flutter/material.dart';

class QualitySelector extends StatefulWidget {
  final Function(String quality) onSelect;

  const QualitySelector({super.key, required this.onSelect});

  @override
  State<QualitySelector> createState() => _QualitySelectorState();
}

class _QualitySelectorState extends State<QualitySelector> {
  String selected = "192";

  @override
  Widget build(BuildContext context) {
    final accent = Color(0xFFFF2D2D);

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          Text("SELECT QUALITY",
              style: TextStyle(letterSpacing: 2)),

          SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ["128", "192", "320"].map((q) {
              final isSelected = selected == q;

              return GestureDetector(
                onTap: () => setState(() => selected = q),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? accent : Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text("$q KBPS"),
                ),
              );
            }).toList(),
          ),

          SizedBox(height: 20),

          ElevatedButton(
            onPressed: () {
              widget.onSelect(selected);
              Navigator.pop(context);
            },
            child: Text("START DOWNLOAD"),
          )
        ],
      ),
    );
  }
}