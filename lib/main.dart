import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dartssh2/dartssh2.dart';

void main() {
  runApp(const ServerApp());
}

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZingShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF38BDF8)),
      ),
      home: const ServerScreen(),
    );
  }
}

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  HttpServer? _server;
  bool isServerRunning = false;
  String localIp = "";
  int port = 8080;

  // === TUNNEL VARIABLES ===
  SSHClient? _sshClient;
  String? publicUrl;
  bool isTunnelStarting = false;

  Future<void> startServer() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    
    Directory downloadDir = Directory('/storage/emulated/0/Download');
    if (!downloadDir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download folder not found!')));
      return;
    }

    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          localIp = addr.address;
          break;
        }
      }
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    setState(() => isServerRunning = true);

    _server!.listen((HttpRequest request) {
      if (request.uri.path == '/') {
        String html = '''
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ZingShare Server</title>
            <style>
              body { background-color: #0F172A; color: white; font-family: 'Segoe UI', sans-serif; margin: 0; padding: 20px; }
              .header { text-align: center; margin-bottom: 30px; }
              .header h2 { color: #38BDF8; font-size: 28px; margin: 0; }
              .header p { color: #94A3B8; font-size: 14px; }
              .container { max-width: 700px; margin: 0 auto; }
              .file-card { background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 16px; padding: 15px; margin-bottom: 15px; backdrop-filter: blur(10px); display: flex; flex-direction: column; gap: 12px; }
              .file-header { display: flex; justify-content: space-between; align-items: center; }
              .file-name { font-size: 16px; font-weight: 600; word-break: break-all; color: #E2E8F0; display: flex; align-items: center; gap: 8px; }
              .download-btn { background: #38BDF8; color: #0F172A; padding: 8px 16px; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 14px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
              audio, video { width: 100%; border-radius: 8px; outline: none; background: #1E293B; }
              audio::-webkit-media-controls-panel, video::-webkit-media-controls-panel { background-color: #38BDF8; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h2>🚀 ZingShare Server</h2>
                <p>Fast • Secure • Local File Sharing</p>
              </div>
        ''';
        
        List<FileSystemEntity> files = downloadDir.listSync();
        for (var file in files) {
          if (file is File) {
            String fileName = file.path.split('/').last;
            String ext = fileName.split('.').last.toLowerCase();
            
            String icon = "📄";
            if (ext == 'mp3' || ext == 'wav') icon = "🎵";
            if (ext == 'mp4' || ext == 'mkv') icon = "🎬";
            if (ext == 'apk') icon = "📱";
            if (ext == 'zip' || ext == 'rar') icon = "📦";
            if (ext == 'jpg' || ext == 'png' || ext == 'jpeg') icon = "🖼️";

            html += '<div class="file-card"><div class="file-header"><span class="file-name">$icon $fileName</span><a href="/download/$fileName" class="download-btn">⬇ Download</a></div>';
            
            if (ext == 'mp3' || ext == 'wav' || ext == 'm4a') {
               html += '<audio controls preload="none"><source src="/stream/$fileName" type="audio/mpeg"></audio>';
            } else if (ext == 'mp4' || ext == 'webm') {
               html += '<video controls preload="none" height="220"><source src="/stream/$fileName" type="video/mp4"></video>';
            }
            html += '</div>';
          }
        }
        html += '</div></body></html>';
        request.response..headers.contentType = ContentType.html..write(html)..close();
          
      } else if (request.uri.path.startsWith('/download/')) {
        String fileName = request.uri.pathSegments.last;
        File file = File('${downloadDir.path}/$fileName');
        if (file.existsSync()) {
          request.response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          file.openRead().pipe(request.response).catchError((e) => request.response.close());
        } else {
          request.response..statusCode = HttpStatus.notFound..write('Not Found')..close();
        }
      } else if (request.uri.path.startsWith('/stream/')) {
        String fileName = request.uri.pathSegments.last;
        File file = File('${downloadDir.path}/$fileName');
        if (file.existsSync()) {
          String ext = fileName.split('.').last.toLowerCase();
          if (ext == 'mp3') request.response.headers.contentType = ContentType.parse('audio/mpeg');
          if (ext == 'mp4') request.response.headers.contentType = ContentType.parse('video/mp4');
          file.openRead().pipe(request.response).catchError((e) => request.response.close());
        } else {
          request.response..statusCode = HttpStatus.notFound..write('Not Found')..close();
        }
      }
    });
  }

  Future<void> startPublicTunnel() async {
    setState(() {
      isTunnelStarting = true;
      publicUrl = null;
    });

    try {
      final socket = await SSHSocket.connect('a.pinggy.io', 443);
      _sshClient = SSHClient(
        socket,
        username: 'pinggy',
        onPasswordRequest: () => '',
      );

      final session = await _sshClient!.shell();
      
      void extractUrl(String data) {
        final RegExp urlRegExp = RegExp(r'https:\/\/[a-zA-Z0-9-]+\.a\.free\.pinggy\.link');
        final match = urlRegExp.firstMatch(data);
        if (match != null && publicUrl == null) {
          setState(() {
            publicUrl = match.group(0);
            isTunnelStarting = false;
          });
        }
      }

      session.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) => extractUrl(data.toString()));
      session.stderr.cast<List<int>>().transform(utf8.decoder).listen((data) => extractUrl(data.toString()));

      // 🛠️ NULL SAFETY FIX HERE: forward!.connections 🛠️
      final forward = await _sshClient!.forwardRemote(port: 0);
      forward!.connections.listen((incoming) async {
        try {
          final local = await Socket.connect('127.0.0.1', port);
          incoming.stream.cast<List<int>>().listen(local.add, onDone: local.close);
          local.listen(incoming.sink.add, onDone: incoming.close);
        } catch (e) {
          incoming.close();
        }
      });

    } catch (e) {
      setState(() => isTunnelStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tunnel Error: $e')));
    }
  }

  void stopServer() {
    _server?.close(force: true);
    _sshClient?.close();
    setState(() {
      isServerRunning = false;
      publicUrl = null;
      _server = null;
      _sshClient = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZingShare 🚀', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cast_connected_rounded, size: 90, color: Color(0xFF38BDF8)),
              const SizedBox(height: 20),
              const Text('Your Premium File Server is ready.', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 30),
              
              if (isServerRunning) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF38BDF8), width: 2)),
                  child: Column(
                    children: [
                      const Text('Local Server Online! 🟢', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      SelectableText('http://$localIp:$port', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 25),
                      
                      if (publicUrl != null) ...[
                        const Text('🌍 Public Link Generated:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 5),
                        SelectableText(publicUrl!, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: publicUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link Copied!')));
                          },
                          icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                          label: const Text('Copy Link', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                        ),
                      ] else if (isTunnelStarting) ...[
                        const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                        const SizedBox(height: 10),
                        const Text('Generating Public Link...', style: TextStyle(color: Colors.white70)),
                      ] else ...[
                        ElevatedButton.icon(
                          onPressed: startPublicTunnel,
                          icon: const Icon(Icons.public, color: Colors.white),
                          label: const Text('Go Public (Worldwide)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF818CF8), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        ),
                      ],
                      
                      const SizedBox(height: 25),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
                        onPressed: stopServer,
                        child: const Text('Stop Everything', style: TextStyle(color: Colors.white, fontSize: 16)),
                      )
                    ],
                  ),
                )
              ] else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                  onPressed: startServer,
                  child: const Text('Start Server', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
