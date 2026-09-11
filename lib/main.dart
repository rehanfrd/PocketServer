import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  File? selectedFile;
  HttpServer? _server;
  bool isServerRunning = false;
  String localIp = "";
  int port = 8080;

  Future<void> pickFile() async {
    // Storage permission maangna
    await Permission.storage.request();
    
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> startServer() async {
    if (selectedFile == null) return;
    
    // Phone ka Local IP address nikalna
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
        request.response
          ..headers.contentType = ContentType.html
          ..write('''
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <h2 style="font-family:sans-serif; color:#333;">🚀 Pocket Server</h2>
            <p>File is ready to download!</p>
            <a href="/download" style="background:#38BDF8; color:white; padding:10px 20px; text-decoration:none; border-radius:10px; display:inline-block;">Download File</a>
          ''')
          ..close();
      } else if (request.uri.path == '/download') {
        selectedFile!.openRead().pipe(request.response).catchError((e) {
          request.response.close();
        });
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found')
          ..close();
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
              Icon(Icons.cloud_upload_rounded, size: 80, color: selectedFile != null ? const Color(0xFF4ADE80) : Colors.white54),
              const SizedBox(height: 20),
              Text(selectedFile != null ? 'Selected: ${selectedFile!.path.split('/').last}' : 'No File Selected', style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: isServerRunning ? null : pickFile,
                icon: const Icon(Icons.folder, color: Colors.white),
                label: const Text('Select File', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
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
                  onPressed: selectedFile == null ? null : startServer,
                  child: const Text('Start Server', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
