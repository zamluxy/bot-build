import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'dart:ui';

// Sesuaikan import ini dengan lokasi file asli lo
import 'login_page.dart';
import 'device_dashboard.dart';
import 'spyware.dart';

class DashboardPage extends StatefulWidget {
  final String username;
  final String password;
  final String role;
  final String sessionKey;

  const DashboardPage({
    super.key,
    required this.username,
    required this.password,
    required this.role,
    required this.sessionKey,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isMuted = true;

  // Cyber Theme Colors
  final Color primaryRed = const Color(0xFFFF1744);
  final Color darkBg = const Color(0xFF050505);
  final Color cardBg = const Color(0xFF121212);
  final Color textGray = const Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _setupVideo();
  }

  void _setupVideo() {
    _videoController = VideoPlayerController.asset('assets/videos/bnb.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isVideoInitialized = true);
          _videoController?.setLooping(true);
          _videoController?.setVolume(0);
          _videoController?.play();
        }
      }).catchError((e) => debugPrint("Video Error: $e"));
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  // Fungsi navigasi yang dipanggil oleh tombol mana pun
  void _navigateTo(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // List halaman utama
    final List<Widget> _pages = [
      _buildHomeTab(),           // Index 0
      const DeviceDashboardPage(), // Index 1 (Control Panel)
      SpywarePage(               // Index 2
        sessionKey: widget.sessionKey,
        username: widget.username,
      ),
      _buildProfileTab(),        // Index 3
    ];

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          // Content Area
          SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
          
          // Floating Bottom Navigation
          _buildFloatingNav(),
        ],
      ),
    );
  }

  // --- TAB 0: HOME ---
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildTopBar(),
          const SizedBox(height: 25),
          _buildHeroVideoCard(), // Video tetap ada di sini
          const SizedBox(height: 30),
          const Text("SYSTEM MODULES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 15),
          _buildModuleGrid(),
          const SizedBox(height: 120), // Spacer agar tidak tertutup nav
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("VORTAXS", style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 12)),
            Text("VORTAXS", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          ],
        ),
        IconButton(
          onPressed: () => _navigateTo(3),
          icon: const Icon(Icons.account_circle, color: Colors.white, size: 32),
        )
      ],
    );
  }

  Widget _buildHeroVideoCard() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: primaryRed.withOpacity(0.1), blurRadius: 20)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            // Video Background
            if (_isVideoInitialized) 
              SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: VideoPlayer(_videoController!)))
            else 
              Container(color: cardBg),
            
            // Masking
            Container(color: Colors.black.withOpacity(0.5)),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: primaryRed, borderRadius: BorderRadius.circular(20)),
                        child: Text(widget.role, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isMuted = !_isMuted;
                            _videoController?.setVolume(_isMuted ? 0 : 1.0);
                          });
                        },
                        icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70),
                      )
                    ],
                  ),
                  const Text("Logged in as:", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(widget.username, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      children: [
        _moduleItem(Icons.terminal, "RAT CONTROL", "Manage Devices", primaryRed, 1),
        _moduleItem(Icons.visibility, "SPYWARE", "Monitor Logs", Colors.purpleAccent, 2),
        _moduleItem(Icons.gps_fixed, "TRACKER", "Live GPS", Colors.blueAccent, 1),
        _moduleItem(Icons.settings, "SETTINGS", "Configuration", Colors.tealAccent, 3),
      ],
    );
  }

  Widget _moduleItem(IconData icon, String title, String sub, Color color, int target) {
    return GestureDetector(
      onTap: () => _navigateTo(target),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(25), border: Border.all(color: color.withOpacity(0.1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const Spacer(),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(sub, style: TextStyle(color: textGray, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: PROFILE ---
  Widget _buildProfileTab() {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const CircleAvatar(radius: 60, backgroundColor: Color(0xFF1A1A1A), child: Icon(Icons.person, size: 60, color: Colors.white)),
          const SizedBox(height: 20),
          Text(widget.username, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("Session: ${widget.sessionKey.substring(0, 8)}...", style: TextStyle(color: textGray)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage())),
              child: const Text("TERMINATE SESSION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // --- FLOATING NAV ---
  Widget _buildFloatingNav() {
    return Positioned(
      bottom: 25,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 75,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navBtn(Icons.grid_view_rounded, 0),
                _navBtn(Icons.terminal_rounded, 1),
                _navBtn(Icons.remove_red_eye_rounded, 2),
                _navBtn(Icons.person_rounded, 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBtn(IconData icon, int index) {
    bool active = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _navigateTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? primaryRed : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: active ? [BoxShadow(color: primaryRed.withOpacity(0.5), blurRadius: 15)] : [],
        ),
        child: Icon(icon, color: active ? Colors.white : Colors.white30, size: 24),
      ),
    );
  }
}
