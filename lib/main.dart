import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';

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

  File? singleSharedFile;
  bool sharingEntireFolder = false;

  // === TUNNEL VARIABLES ===
  SSHClient? _sshClient;
  String? publicUrl;
  bool isTunnelStarting = false;

  Future<void> _getIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          localIp = addr.address;
          return;
        }
      }
    }
    localIp = '127.0.0.1';
  }

  // OPTION 1: Share Single File
  Future<void> startSingleFileServer() async {
    await Permission.storage.request();
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    
    if (result != null) {
      singleSharedFile = File(result.files.single.path!);
      sharingEntireFolder = false;
      await _getIp();
      _startHttpServer();
    }
  }

  // OPTION 2: Share Entire Download Folder
  Future<void> startFolderServer() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    
    Directory downloadDir = Directory('/storage/emulated/0/Download');
    if (!downloadDir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download folder not found!')));
      return;
    }
    
    singleSharedFile = null;
    sharingEntireFolder = true;
    await _getIp();
    _startHttpServer();
  }

  void _startHttpServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    setState(() => isServerRunning = true);

    _server!.listen((HttpRequest request) async {
      if (request.uri.path == '/') {
        // 🎨 CLASSY & CLEAN WEB UI (Google Files Style) 🎨
        String html = '''
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ZingShare Files</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; background: #f8f9fa; color: #202124; }
              .app-bar { background: #ffffff; padding: 18px 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; display: flex; align-items: center; }
              .app-bar h2 { margin: 0; font-size: 20px; color: #1a73e8; font-weight: 600; letter-spacing: 0.5px; }
              .list { list-style: none; padding: 0; margin: 0; }
              .item { display: flex; align-items: center; padding: 16px 20px; border-bottom: 1px solid #e8eaed; background: #ffffff; text-decoration: none; color: inherit; transition: background 0.2s; }
              .item:active { background: #f1f3f4; }
              .icon { font-size: 26px; margin-right: 18px; }
              .name { flex-grow: 1; font-size: 16px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
              .action { color: #1a73e8; font-size: 20px; font-weight: bold; }
            </style>
          </head>
          <body>
            <div class="app-bar"><h2>📁 Shared Files</h2></div>
            <ul class="list">
        ''';
        
        List<File> filesToShow = [];
        if (sharingEntireFolder) {
          Directory downloadDir = Directory('/storage/emulated/0/Download');
          List<FileSystemEntity> entities = downloadDir.listSync();
          for (var e in entities) { if (e is File) filesToShow.add(e); }
        } else if (singleSharedFile != null) {
          filesToShow.add(singleSharedFile!);
        }

        for (var file in filesToShow) {
          String fileName = file.path.split('/').last;
          String ext = fileName.split('.').last.toLowerCase();
          
          String icon = "📄";
          if (['mp3', 'wav', 'm4a'].contains(ext)) icon = "🎵";
          if (['mp4', 'mkv', 'webm'].contains(ext)) icon = "🎬";
          if (['jpg', 'jpeg', 'png'].contains(ext)) icon = "🖼️";
          if (['apk'].contains(ext)) icon = "📱";
          if (['zip', 'rar'].contains(ext)) icon = "📦";

          // Ab custom player nahi, seedha link diya hai. Browser khud open karega!
          html += '''
            <a href="/file/${Uri.encodeComponent(fileName)}" class="item">
              <div class="icon">$icon</div>
              <div class="name">$fileName</div>
              <div class="action">↓</div>
            </a>
          ''';
        }
        
        html += '</ul></body></html>';
        request.response..headers.contentType = ContentType.html..write(html)..close();
          
      } else if (request.uri.path.startsWith('/file/')) {
        String fileName = Uri.decodeComponent(request.uri.pathSegments.last);
        File? fileToServe;

        if (sharingEntireFolder) {
          fileToServe = File('/storage/emulated/0/Download/$fileName');
        } else if (singleSharedFile != null && singleSharedFile!.path.endsWith(fileName)) {
          fileToServe = singleSharedFile;
        }

        if (fileToServe != null && fileToServe.existsSync()) {
          String ext = fileName.split('.').last.toLowerCase();
          
          // Agar Media/Image hai, to download ke bajaye browser me Play/Show karega
          if (['mp4', 'mkv', 'webm'].contains(ext)) {
            request.response.headers.contentType = ContentType.parse('video/mp4');
          } else if (['mp3', 'wav', 'm4a'].contains(ext)) {
            request.response.headers.contentType = ContentType.parse('audio/mpeg');
          } else if (['jpg', 'jpeg', 'png'].contains(ext)) {
            request.response.headers.contentType = ContentType.parse('image/jpeg');
          } else {
            // Baki sab (APK, ZIP) direct download honge
            request.response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          }
          
          await fileToServe.openRead().pipe(request.response).catchError((e) => request.response.close());
        } else {
          request.response..statusCode = HttpStatus.notFound..write('File Not Found')..close();
        }
      }
    });
  }

  // === THE MAGIC TUNNEL ENGINE (CONNECTION RESET FIX) ===
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

      final forward = await _sshClient!.forwardRemote(port: 0);
      forward!.connections.listen((incoming) async {
        try {
          final local = await Socket.connect(localIp, port);
          
          // 🚀 FIX: Data pipe ko crash proof bana diya
          incoming.stream.cast<List<int>>().listen(
            (data) { try { local.add(data); } catch(e){} },
            onDone: () => local.close(),
            onError: (e) => local.close(),
          );
          
          local.listen(
            (data) { try { incoming.sink.add(data); } catch(e){} },
            onDone: () => incoming.close(),
            onError: (e) => incoming.close(),
          );
        } catch (e) {
          incoming.close();
        }
      });

      final session = await _sshClient!.shell(pty: const SSHPtyConfig(width: 100, height: 50));
      
      String buffer = '';
      void extractUrl(String data) {
        buffer += data;
        final RegExp urlRegExp = RegExp(r'https:\/\/[a-zA-Z0-9.-]+\.pinggy\.[a-z]+');
        final match = urlRegExp.firstMatch(buffer);
        
        if (match != null && publicUrl == null) {
          setState(() {
            publicUrl = match.group(0);
            isTunnelStarting = false;
          });
        }
      }

      session.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) => extractUrl(data.toString()));
      session.stderr.cast<List<int>>().transform(utf8.decoder).listen((data) => extractUrl(data.toString()));

      Future.delayed(const Duration(seconds: 25), () {
        if (mounted && isTunnelStarting) {
          setState(() {
            isTunnelStarting = false;
            _sshClient?.close();
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network is slow. Please try again!')));
        }
      });

    } catch (e) {
      if (mounted) {
        setState(() => isTunnelStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tunnel Error: $e')));
      }
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
      singleSharedFile = null;
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
              
              if (isServerRunning) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF38BDF8), width: 2)),
                  child: Column(
                    children: [
                      Text(sharingEntireFolder ? 'Sharing Entire Folder 📁' : 'Sharing Single File 📄', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 16, fontWeight: FontWeight.bold)),
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
                        const Text('Extracting Public Link...', style: TextStyle(color: Colors.white70)),
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
              ] else ...[
                const Text('What do you want to share?', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 30),
                
                // NAYA FEATURE: Single File Select Karne Ka Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
                  onPressed: startSingleFileServer,
                  icon: const Icon(Icons.insert_drive_file, color: Colors.white),
                  label: const Text('Select a Single File', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 15),
                const Text('--- OR ---', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), side: const BorderSide(color: Color(0xFF38BDF8))),
                  onPressed: startFolderServer,
                  icon: const Icon(Icons.folder, color: Color(0xFF38BDF8)),
                  label: const Text('Share "Download" Folder', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
