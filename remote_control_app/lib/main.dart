import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
        scaffoldBackgroundColor: Color(0xFFDEB7FF), // App background color
      ),
      home: IPEntryScreen(),
    );
  }
}

class IPEntryScreen extends StatefulWidget {
  @override
  _IPEntryScreenState createState() => _IPEntryScreenState();
}

class _IPEntryScreenState extends State<IPEntryScreen> {
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIP();
  }

  Future<void> _loadIP() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('server_ip') ?? '';
  }

  Future<void> _saveAndProceed() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => RemoteControlScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          padding: EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Color(0xFFC296FC),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tappy Remote',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 20),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: 'Enter Laptop IP',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 20),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _saveAndProceed,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                    decoration: BoxDecoration(
                      color: Color(0xFFC296FC),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.shade100,
                          offset: Offset(4, 4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      'Connect',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RemoteControlScreen extends StatefulWidget {
  @override
  _RemoteControlScreenState createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _loadIP();
  }

  Future<void> _loadIP() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('server_ip') ?? '';
    });
  }

  Future<void> _sendRequest(String route, Map<String, dynamic> data) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    final url = Uri.parse('http://$ip:5000/$route');
    try {
      final response = await http.post(
        url,
        body: jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Request failed: $e');
    }
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
          child: Text(
            text,
            style: TextStyle(fontSize: 16, color: Colors.black),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFDEB7FF),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: Text('Tappy Trackpad'),
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
                    color: Color(0xFFFFFFF5), // ✅ Corrected trackpad color (#FFFFF5)
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      'Trackpad Area',
                      style: TextStyle(color: Colors.black54),
                    ),
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
    );
  }
}
