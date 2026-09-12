import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  bool sharingEntirePhone = false;

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

  // 🚀 FEATURE 1: IN-BUILT CUSTOM FILE EXPLORER 🚀
  Future<void> startSingleFileServer() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    
    File? pickedFile = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InAppFilePicker()),
    );

    if (pickedFile != null) {
      singleSharedFile = pickedFile;
      sharingEntirePhone = false;
      await _getIp();
      _startHttpServer();
    }
  }

  // 🚀 FEATURE 2: SHARE ENTIRE PHONE 🚀
  Future<void> startPhoneServer() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    
    singleSharedFile = null;
    sharingEntirePhone = true;
    await _getIp();
    _startHttpServer();
  }

  void _startHttpServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    setState(() => isServerRunning = true);

    _server!.listen((HttpRequest request) async {
      String requestPath = Uri.decodeComponent(request.uri.path);
      
      // === WEB UI HTML TEMPLATE ===
      String startHtml(String title) => '''
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>$title</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; margin: 0; background: #f8f9fa; color: #202124; }
            .app-bar { background: #ffffff; padding: 18px 20px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; display: flex; align-items: center; }
            .app-bar h2 { margin: 0; font-size: 20px; color: #1a73e8; font-weight: 600; }
            .list { list-style: none; padding: 0; margin: 0; }
            .item { display: flex; align-items: center; padding: 16px 20px; border-bottom: 1px solid #e8eaed; background: #ffffff; text-decoration: none; color: inherit; }
            .item:hover { background: #f1f3f4; }
            .icon { font-size: 26px; margin-right: 18px; }
            .name { flex-grow: 1; font-size: 16px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
            .action { color: #1a73e8; font-size: 20px; font-weight: bold; }
          </style>
        </head>
        <body>
          <div class="app-bar"><h2>$title</h2></div>
          <ul class="list">
      ''';

      if (sharingEntirePhone) {
        String basePath = '/storage/emulated/0';
        String fullPath = requestPath == '/' ? basePath : '$basePath$requestPath';
        
        if (FileSystemEntity.isDirectorySync(fullPath)) {
          Directory dir = Directory(fullPath);
          String html = startHtml(requestPath == '/' ? '📱 My Phone Storage' : '📁 ${requestPath.split('/').last}');
          
          if (requestPath != '/') {
            String parentPath = requestPath.substring(0, requestPath.lastIndexOf('/'));
            if (parentPath.isEmpty) parentPath = '/';
            html += '<a href="$parentPath" class="item"><div class="icon">🔙</div><div class="name">... Go Back</div></a>';
          }
          
          List<FileSystemEntity> entities = dir.listSync()..sort((a, b) {
            bool aIsDir = a is Directory;
            bool bIsDir = b is Directory;
            if (aIsDir && !bIsDir) return -1;
            if (!aIsDir && bIsDir) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });

          for (var e in entities) {
            String name = e.path.split('/').last;
            if (name.startsWith('.')) continue;
            
            String linkPath = requestPath == '/' ? '/$name' : '$requestPath/$name';
            
            if (e is Directory) {
              html += '<a href="${Uri.encodeComponent(linkPath).replaceAll('%2F', '/')}" class="item"><div class="icon">📁</div><div class="name">$name</div><div class="action">></div></a>';
            } else {
              String ext = name.split('.').last.toLowerCase();
              String icon = "📄";
              if (['mp3', 'wav', 'm4a'].contains(ext)) icon = "🎵";
              if (['mp4', 'mkv', 'webm'].contains(ext)) icon = "🎬";
              if (['jpg', 'jpeg', 'png'].contains(ext)) icon = "🖼️";
              if (['apk'].contains(ext)) icon = "📱";
              html += '<a href="${Uri.encodeComponent(linkPath).replaceAll('%2F', '/')}" class="item"><div class="icon">$icon</div><div class="name">$name</div><div class="action">↓</div></a>';
            }
          }
          html += '</ul></body></html>';
          request.response..headers.contentType = ContentType.html..write(html)..close();
          
        } else if (FileSystemEntity.isFileSync(fullPath)) {
          File file = File(fullPath);
          String ext = fullPath.split('.').last.toLowerCase();
          if (['mp4', 'mkv'].contains(ext)) request.response.headers.contentType = ContentType.parse('video/mp4');
          else if (['mp3', 'wav'].contains(ext)) request.response.headers.contentType = ContentType.parse('audio/mpeg');
          else if (['jpg', 'png'].contains(ext)) request.response.headers.contentType = ContentType.parse('image/jpeg');
          else request.response.headers.add('Content-Disposition', 'attachment; filename="${fullPath.split('/').last}"');
          
          await file.openRead().pipe(request.response).catchError((e) => request.response.close());
        } else {
          request.response..statusCode = HttpStatus.notFound..write('Not Found')..close();
        }
        
      } else {
        if (requestPath == '/') {
          String html = startHtml('📄 Shared File');
          String fileName = singleSharedFile!.path.split('/').last;
          html += '<a href="/download" class="item"><div class="icon">📄</div><div class="name">$fileName</div><div class="action">↓</div></a>';
          html += '</ul></body></html>';
          request.response..headers.contentType = ContentType.html..write(html)..close();
        } else if (requestPath == '/download') {
          String fileName = singleSharedFile!.path.split('/').last;
          request.response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          await singleSharedFile!.openRead().pipe(request.response).catchError((e) => request.response.close());
        }
      }
    });
  }

  void stopServer() {
    _server?.close(force: true);
    setState(() {
      isServerRunning = false;
      _server = null;
      singleSharedFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    String serverUrl = 'http://$localIp:$port';

    return Scaffold(
      appBar: AppBar(title: const Text('ZingShare 🚀', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_rounded, size: 90, color: Color(0xFF38BDF8)),
              const SizedBox(height: 20),
              
              if (isServerRunning) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        sharingEntirePhone ? 'Sharing Entire Phone 📱' : 'Sharing Single File 📄',
                        style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      
                      // 📷 QR CODE FOR SCANNING
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: serverUrl,
                          version: QrVersions.auto,
                          size: 180.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 15),

                      const Text('Scan QR or open this link:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 5),
                      SelectableText(
                        serverUrl,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 15),

                      // 📋 COPY LINK BUTTON
                      ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: serverUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link Copied to Clipboard!')),
                          );
                        },
                        icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                        label: const Text('Copy Local Link', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                      ),
                      const SizedBox(height: 20),
                      
                      // 🛑 STOP SERVER BUTTON
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        ),
                        onPressed: stopServer,
                        child: const Text('Stop Server', style: TextStyle(color: Colors.white, fontSize: 16)),
                      )
                    ],
                  ),
                )
              ] else ...[
                const Text('What do you want to share locally?', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 30),
                
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                  onPressed: startSingleFileServer,
                  icon: const Icon(Icons.insert_drive_file, color: Colors.white),
                  label: const Text('Select a Single File', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 15),
                const Text('--- OR ---', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                  onPressed: startPhoneServer,
                  icon: const Icon(Icons.phone_android, color: Color(0xFF38BDF8)),
                  label: const Text('Share Entire Phone Storage', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class InAppFilePicker extends StatefulWidget {
  const InAppFilePicker({super.key});
  @override
  State<InAppFilePicker> createState() => _InAppFilePickerState();
}

class _InAppFilePickerState extends State<InAppFilePicker> {
  String currentPath = '/storage/emulated/0';
  List<FileSystemEntity> items = [];

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  void loadFiles() {
    try {
      Directory dir = Directory(currentPath);
      setState(() {
        items = dir.listSync()..sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      });
    } catch (e) {
      items = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select File', style: TextStyle(fontSize: 18)),
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (currentPath == '/storage/emulated/0') {
              Navigator.pop(context);
            } else {
              setState(() {
                currentPath = Directory(currentPath).parent.path;
                loadFiles();
              });
            }
          },
        ),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          FileSystemEntity item = items[index];
          String name = item.path.split('/').last;
          if (name.startsWith('.')) return const SizedBox();

          bool isDir = item is Directory;
          return ListTile(
            leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file, color: isDir ? const Color(0xFF38BDF8) : Colors.white70),
            title: Text(name, style: const TextStyle(color: Colors.white)),
            onTap: () {
              if (isDir) {
                setState(() {
                  currentPath = item.path;
                  loadFiles();
                });
              } else {
                Navigator.pop(context, File(item.path));
              }
            },
          );
        },
      ),
    );
  }
}
