import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const int kBroadcastPort = 5051;       // server.py isi port pe broadcast karta hai
const String kBroadcastPrefix = 'TAPPY_SERVER:';
const String kMyDeviceName = 'My Phone';

void main() {
  runApp(RemoteControlApp());
}

class RemoteControlApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tappy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Color(0xFFDEB7FF),
      ),
      home: NearbyLaptopsScreen(),
    );
  }
}

class LaptopInfo {
  final String ip;
  final String name;
  DateTime lastSeen;
  LaptopInfo(this.ip, this.name, this.lastSeen);
}

class NearbyLaptopsScreen extends StatefulWidget {
  @override
  _NearbyLaptopsScreenState createState() => _NearbyLaptopsScreenState();
}

class _NearbyLaptopsScreenState extends State<NearbyLaptopsScreen> {
  RawDatagramSocket? _socket;
  Timer? _cleanupTimer;
  final Map<String, LaptopInfo> _devices = {};
  bool _connecting = false;
  final TextEditingController _manualIpController = TextEditingController();
  bool _showManual = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _socket?.close();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kBroadcastPort);
      _socket!.broadcastEnabled = true;
      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram == null) return;
          final message = utf8.decode(datagram.data);
          if (message.startsWith(kBroadcastPrefix)) {
            final rest = message.substring(kBroadcastPrefix.length);
            final parts = rest.split('|');
            final ip = parts[0].trim();
            final name = parts.length > 1 ? parts[1].trim() : ip;
            setState(() {
              _devices[ip] = LaptopInfo(ip, name, DateTime.now());
            });
          }
        }
      });
    } catch (e) {
      // Search fail hui to bhi manual entry available rahegi
    }

    // Har 2 sec check karo, jo laptop 6 sec se broadcast nahi bhej raha
    // (matlab app band ho chuki), usse list se hata do.
    _cleanupTimer = Timer.periodic(Duration(seconds: 2), (_) {
      final now = DateTime.now();
      setState(() {
        _devices.removeWhere((k, v) => now.difference(v.lastSeen).inSeconds > 6);
      });
    });
  }

  Future<void> _connectTo(String ip, String name) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final response = await http
          .post(
            Uri.parse('http://$ip:5000/connect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': kMyDeviceName}),
          )
          .timeout(Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final laptopName = body['laptop_name'] ?? name;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RemoteControlScreen(ip: ip, laptopName: laptopName),
          ),
        );
      } else if (response.statusCode == 409) {
        _showMessage('This laptop is already connected to another phone.');
      } else {
        _showMessage('Could not connect. Try again.');
      }
    } catch (e) {
      _showMessage('Could not reach laptop. Make sure Tappy is open there and on the same WiFi.');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildDeviceTile(LaptopInfo info) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: ListTile(
        leading: Icon(Icons.laptop_mac, color: Color(0xFFC296FC)),
        title: Text(info.name, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(info.ip),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFC296FC)),
          onPressed: _connecting ? null : () => _connectTo(info.ip, info.name),
          child: Text('Connect', style: TextStyle(color: Colors.black)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: Text('Nearby Laptops'),
      ),
      body: Column(
        children: [
          SizedBox(height: 12),
          if (devices.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFFC296FC)),
                  SizedBox(height: 16),
                  Text(
                    'Searching for laptops...\nOpen the Tappy app on your laptop and make sure both devices are on the same WiFi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black87),
                  ),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: ListView(
                children: devices.map(_buildDeviceTile).toList(),
              ),
            ),
          ],
          TextButton(
            onPressed: () => setState(() => _showManual = !_showManual),
            child: Text(_showManual ? 'Hide manual connect' : 'Connect manually by IP'),
          ),
          if (_showManual)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualIpController,
                      decoration: InputDecoration(
                        labelText: 'Laptop IP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFC296FC)),
                    onPressed: _connecting
                        ? null
                        : () {
                            final ip = _manualIpController.text.trim();
                            if (ip.isNotEmpty) _connectTo(ip, ip);
                          },
                    child: Text('Go', style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ),
          SizedBox(height: 12),
        ],
      ),
    );
  }
}

class RemoteControlScreen extends StatefulWidget {
  final String ip;
  final String laptopName;
  RemoteControlScreen({required this.ip, required this.laptopName});

  @override
  _RemoteControlScreenState createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _leaving = false;

  Future<void> _sendRequest(String route, Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://${widget.ip}:5000/$route'),
            body: jsonEncode(data),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(Duration(seconds: 3));

      if (response.statusCode == 409 && mounted && !_leaving) {
        _handleDisconnectedByLaptop();
      }
    } catch (e) {
      if (mounted && !_leaving) _handleDisconnectedByLaptop();
    }
  }

  void _handleDisconnectedByLaptop() {
    _leaving = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Disconnected from laptop.')),
    );
    Navigator.pop(context);
  }

  Future<bool> _disconnectAndLeave() async {
    if (_leaving) return true;
    _leaving = true;
    try {
      await http
          .post(Uri.parse('http://${widget.ip}:5000/disconnect'))
          .timeout(Duration(seconds: 2));
    } catch (_) {
      // laptop already band ho chuka ho sakta hai, ignore karo
    }
    return true;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx * 5;
    final dy = details.delta.dy * 5;
    _sendRequest('move', {'dx': dx.toInt(), 'dy': dy.toInt()});
  }

  Widget fancyButton(String text, VoidCallback onPressed) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          decoration: BoxDecoration(
            color: Color(0xFFC296FC),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(0.3),
                offset: Offset(3, 3),
                blurRadius: 5,
              ),
            ],
          ),
          child: Text(text, style: TextStyle(fontSize: 16, color: Colors.black)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _disconnectAndLeave,
      child: Scaffold(
        backgroundColor: Color(0xFFDEB7FF),
        appBar: AppBar(
          backgroundColor: Colors.purple,
          title: Text('Connected to ${widget.laptopName}'),
          actions: [
            IconButton(
              icon: Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: () async {
                await _disconnectAndLeave();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Type something',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (text) {
                  _sendRequest('type', {'text': text});
                  _textController.clear();
                },
              ),
              SizedBox(height: 12),
              Expanded(
                child: GestureDetector(
                  onPanUpdate: _handlePanUpdate,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFF5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: Center(
                      child: Text('Trackpad Area', style: TextStyle(color: Colors.black54)),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  fancyButton('Left Click', () => _sendRequest('click', {'button': 'left'})),
                  fancyButton('Right Click', () => _sendRequest('click', {'button': 'right'})),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  fancyButton('Scroll Up', () => _sendRequest('scroll', {'amount': 100})),
                  fancyButton('Scroll Down', () => _sendRequest('scroll', {'amount': -100})),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
