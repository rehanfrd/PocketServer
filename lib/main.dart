import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const ServerApp());
}

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Server',
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

  Future<void> startServer() async {
    // Permission lena
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    
    // Download folder ka rasta
    Directory downloadDir = Directory('/storage/emulated/0/Download');
    if (!downloadDir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download folder not found!')));
      return;
    }

    // IP nikalna
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          localIp = addr.address;
          break;
        }
      }
    }

    // Server Start karna
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    setState(() => isServerRunning = true);

    _server!.listen((HttpRequest request) {
      if (request.uri.path == '/') {
        String html = '''
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <h2 style="font-family:sans-serif; color:#333;">🚀 Pocket Server (Downloads)</h2>
          <ul>
        ''';
        
        List<FileSystemEntity> files = downloadDir.listSync();
        for (var file in files) {
          if (file is File) {
            String fileName = file.path.split('/').last;
            html += '<li><a href="/download/$fileName" style="font-size:18px;">$fileName</a></li><br>';
          }
        }
        
        html += '</ul>';
        request.response
          ..headers.contentType = ContentType.html
          ..write(html)
          ..close();
      } else if (request.uri.path.startsWith('/download/')) {
        String fileName = request.uri.pathSegments.last;
        File fileToDownload = File('${downloadDir.path}/$fileName');
        
        if (fileToDownload.existsSync()) {
          request.response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          fileToDownload.openRead().pipe(request.response).catchError((e) => request.response.close());
        } else {
          request.response..statusCode = HttpStatus.notFound..write('File Not Found')..close();
        }
      }
    });
  }

  void stopServer() {
    _server?.close(force: true);
    setState(() {
      isServerRunning = false;
      _server = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pocket Server 🚀', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_sync_rounded, size: 80, color: Color(0xFF38BDF8)),
              const SizedBox(height: 20),
              const Text('Share your entire "Download" folder instantly!', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 30),
              
              if (isServerRunning)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF38BDF8))),
                  child: Column(
                    children: [
                      const Text('Server is Running! 🟢', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      SelectableText('http://$localIp:$port', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: stopServer,
                        child: const Text('Stop Server', style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
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
