import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const int kBroadcastPort = 5051;       // server.py isi port pe broadcast karta hai
const String kBroadcastPrefix = 'TAPPY_SERVER:';
const String kMyDeviceName = 'My Phone';

// ---------------------------------------------------------------------------
// Palette — Milk Chocolate is the base surface everywhere, that's what makes
// the neumorphism read correctly (shadows need a flat base to sit on top of).
// ---------------------------------------------------------------------------
const Color kAntiqueWhite = Color(0xFFF7EBDF);
const Color kPaleTaupe = Color(0xFFB7A087);
const Color kMilkChocolate = Color(0xFF825A3C);
const Color kVanDykeBrown = Color(0xFF5C3E28); // swap in the real hex if you have it
const Color kOnline = Color(0xFF8FBF8F); // muted sage green, just for the status dot

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
        scaffoldBackgroundColor: kMilkChocolate,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: kAntiqueWhite,
              displayColor: kAntiqueWhite,
            ),
      ),
      home: NearbyLaptopsScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Neumorphic primitives
// ---------------------------------------------------------------------------
class Neu extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool pressed;
  final double depth;

  const Neu({
    Key? key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(16),
    this.pressed = false,
    this.depth = 6,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lightShadow = BoxShadow(
      color: kPaleTaupe.withOpacity(0.55),
      offset: pressed ? Offset(depth, depth) : Offset(-depth, -depth),
      blurRadius: depth * 2.2,
    );
    final darkShadow = BoxShadow(
      color: kVanDykeBrown.withOpacity(0.85),
      offset: pressed ? Offset(-depth, -depth) : Offset(depth, depth),
      blurRadius: depth * 2.2,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kMilkChocolate,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [darkShadow, lightShadow],
      ),
      child: child,
    );
  }
}

// Circular neumorphic button — used for icon-only actions (back, disconnect,
// connect arrow, dashboard controls). This alone kills the "kid built it" look
// because it replaces every wide text pill with something a control panel
// would actually use.
class NeuIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  const NeuIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.size = 46,
    this.iconSize = 20,
  }) : super(key: key);

  @override
  _NeuIconButtonState createState() => _NeuIconButtonState();
}

class _NeuIconButtonState extends State<NeuIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: Neu(
        radius: widget.size / 2,
        depth: 4,
        padding: EdgeInsets.zero,
        pressed: _down,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.onPressed == null
                ? kPaleTaupe.withOpacity(0.4)
                : kAntiqueWhite,
          ),
        ),
      ),
    );
  }
}

// Square-ish dashboard tile — icon on top, label under it. Used for the
// click/scroll controls so they read as a control grid, not a button list.
class NeuTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const NeuTile({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : super(key: key);

  @override
  _NeuTileState createState() => _NeuTileState();
}

class _NeuTileState extends State<NeuTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onPressed,
        child: Neu(
          radius: 18,
          depth: 5,
          pressed: _down,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: kAntiqueWhite, size: 22),
              SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: kPaleTaupe,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kVanDykeBrown,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(msg, style: TextStyle(color: kAntiqueWhite)),
      ),
    );
  }

  Widget _buildDeviceTile(LaptopInfo info) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Neu(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Neu(
                  radius: 16,
                  depth: 3,
                  padding: const EdgeInsets.all(11),
                  child: Icon(Icons.laptop_mac_rounded, color: kAntiqueWhite, size: 20),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: kOnline,
                      shape: BoxShape.circle,
                      border: Border.all(color: kMilkChocolate, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: kAntiqueWhite,
                      letterSpacing: 0.1,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    info.ip,
                    style: TextStyle(
                      color: kPaleTaupe,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            NeuIconButton(
              icon: Icons.arrow_forward_rounded,
              onPressed: _connecting ? null : () => _connectTo(info.ip, info.name),
              size: 42,
              iconSize: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: kMilkChocolate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nearby Laptops',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: kAntiqueWhite,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          devices.isEmpty
                              ? 'Scanning your network'
                              : '${devices.length} device${devices.length == 1 ? '' : 's'} found',
                          style: TextStyle(
                            fontSize: 13,
                            color: kPaleTaupe,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  NeuIconButton(
                    icon: _showManual ? Icons.close_rounded : Icons.add_link_rounded,
                    onPressed: () => setState(() => _showManual = !_showManual),
                  ),
                ],
              ),
              SizedBox(height: 22),

              if (_showManual)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Neu(
                    radius: 18,
                    pressed: true,
                    depth: 4,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 12),
                        Icon(Icons.dns_rounded, size: 18, color: kPaleTaupe),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _manualIpController,
                            style: TextStyle(color: kAntiqueWhite, fontSize: 14),
                            cursorColor: kAntiqueWhite,
                            decoration: InputDecoration(
                              hintText: 'Enter laptop IP address',
                              hintStyle: TextStyle(color: kPaleTaupe.withOpacity(0.7)),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        NeuIconButton(
                          icon: Icons.arrow_forward_rounded,
                          size: 38,
                          iconSize: 16,
                          onPressed: _connecting
                              ? null
                              : () {
                                  final ip = _manualIpController.text.trim();
                                  if (ip.isNotEmpty) _connectTo(ip, ip);
                                },
                        ),
                        SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),

              Expanded(
                child: devices.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 60),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Neu(
                                radius: 50,
                                depth: 7,
                                padding: const EdgeInsets.all(26),
                                child: SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: CircularProgressIndicator(
                                    color: kAntiqueWhite,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                              SizedBox(height: 24),
                              Text(
                                'Searching for laptops',
                                style: TextStyle(
                                  color: kAntiqueWhite,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 30),
                                child: Text(
                                  'Open Tappy on your laptop and make sure both devices share the same WiFi network.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: kPaleTaupe,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 20),
                        children: devices.map(_buildDeviceTile).toList(),
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
      SnackBar(
        backgroundColor: kVanDykeBrown,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text('Disconnected from laptop.', style: TextStyle(color: kAntiqueWhite)),
      ),
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _disconnectAndLeave,
      child: Scaffold(
        backgroundColor: kMilkChocolate,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Neu(
                          radius: 16,
                          depth: 4,
                          padding: const EdgeInsets.all(11),
                          child: Icon(Icons.laptop_mac_rounded, color: kAntiqueWhite, size: 20),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: kOnline,
                              shape: BoxShape.circle,
                              border: Border.all(color: kMilkChocolate, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.laptopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kAntiqueWhite,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Connected · ${widget.ip}',
                            style: TextStyle(fontSize: 12, color: kPaleTaupe),
                          ),
                        ],
                      ),
                    ),
                    NeuIconButton(
                      icon: Icons.link_off_rounded,
                      onPressed: () async {
                        await _disconnectAndLeave();
                        if (mounted) Navigator.pop(context);
                      },
                      size: 42,
                      iconSize: 18,
                    ),
                  ],
                ),
                SizedBox(height: 20),

                Neu(
                  radius: 18,
                  pressed: true,
                  depth: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 10),
                      Icon(Icons.keyboard_alt_outlined, size: 18, color: kPaleTaupe),
                      SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: TextStyle(color: kAntiqueWhite, fontSize: 14),
                          cursorColor: kAntiqueWhite,
                          decoration: InputDecoration(
                            hintText: 'Type to send to laptop',
                            hintStyle: TextStyle(color: kPaleTaupe.withOpacity(0.7)),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (text) {
                            _sendRequest('type', {'text': text});
                            _textController.clear();
                          },
                        ),
                      ),
                      NeuIconButton(
                        icon: Icons.send_rounded,
                        size: 38,
                        iconSize: 15,
                        onPressed: () {
                          _sendRequest('type', {'text': _textController.text});
                          _textController.clear();
                        },
                      ),
                      SizedBox(width: 4),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                Expanded(
                  child: GestureDetector(
                    onPanUpdate: _handlePanUpdate,
                    child: Neu(
                      radius: 26,
                      pressed: true,
                      depth: 6,
                      padding: const EdgeInsets.all(0),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 18,
                            top: 16,
                            child: Row(
                              children: [
                                Icon(Icons.touch_app_outlined, size: 15, color: kPaleTaupe.withOpacity(0.6)),
                                SizedBox(width: 6),
                                Text(
                                  'TRACKPAD',
                                  style: TextStyle(
                                    color: kPaleTaupe.withOpacity(0.6),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Center(
                            child: Icon(
                              Icons.pan_tool_alt_outlined,
                              color: kPaleTaupe.withOpacity(0.25),
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),

                Row(
                  children: [
                    NeuTile(
                      icon: Icons.mouse_outlined,
                      label: 'LEFT CLICK',
                      onPressed: () => _sendRequest('click', {'button': 'left'}),
                    ),
                    SizedBox(width: 12),
                    NeuTile(
                      icon: Icons.mouse,
                      label: 'RIGHT CLICK',
                      onPressed: () => _sendRequest('click', {'button': 'right'}),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    NeuTile(
                      icon: Icons.keyboard_arrow_up_rounded,
                      label: 'SCROLL UP',
                      onPressed: () => _sendRequest('scroll', {'amount': 100}),
                    ),
                    SizedBox(width: 12),
                    NeuTile(
                      icon: Icons.keyboard_arrow_down_rounded,
                      label: 'SCROLL DOWN',
                      onPressed: () => _sendRequest('scroll', {'amount': -100}),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}