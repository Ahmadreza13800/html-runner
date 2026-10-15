import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeHtmlRunnerApp());
}

class SafeHtmlRunnerApp extends StatelessWidget {
  const SafeHtmlRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTML Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FolderManagementPage(),
    );
  }
}

class StorageService {
  static Future<Directory> getSafeRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final secureRoot = Directory(p.join(appDir.path, 'html_library'));
    if (!await secureRoot.exists()) {
      await secureRoot.create(recursive: true);
    }
    return secureRoot;
  }

  static String? sanitizeFolderName(String input) {
    final clean = input.replaceAll(RegExp(r'[\\/:*?"<>|.]'), '_').trim();
    if (clean.isEmpty) return null;
    return clean;
  }
}

class FolderManagementPage extends StatefulWidget {
  const FolderManagementPage({super.key});

  @override
  State<FolderManagementPage> createState() => _FolderManagementPageState();
}

class _FolderManagementPageState extends State<FolderManagementPage> {
  List<Directory> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFolders();
  }

  Future<void> _fetchFolders() async {
    setState(() => _isLoading = true);
    final root = await StorageService.getSafeRoot();
    final list = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      _folders = list;
      _isLoading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ساخت پوشه جدید'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'نام پوشه را وارد کنید'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('بساز'),
          ),
        ],
      ),
    );

    if (folderName == null) return;
    final sanitized = StorageService.sanitizeFolderName(folderName);
    if (sanitized == null) return;

    final root = await StorageService.getSafeRoot();
    final newDir = Directory(p.join(root.path, sanitized));

    if (await newDir.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این پوشه از قبل وجود دارد')),
      );
      return;
    }

    await newDir.create(recursive: true);
    await _fetchFolders();
  }

  Future<void> _confirmDelete(Directory dir) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پوشه'),
        content: Text('پوشه "${p.basename(dir.path)}" حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله، حذف کن')),
        ],
      ),
    );

    if (confirm == true) {
      await dir.delete(recursive: true);
      await _fetchFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پوشه‌بندی فایل‌های HTML'),
        actions: [
          IconButton(onPressed: _fetchFolders, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('پوشه جدید'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? const Center(child: Text('هیچ پوشه‌ای وجود ندارد.\nیک پوشه جدید بسازید.'))
              : ListView.separated(
                  itemCount: _folders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = _folders[i];
                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber, size: 36),
                      title: Text(p.basename(item.path), style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _confirmDelete(item),
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FileBrowserPage(targetDirectory: item),
                          ),
                        );
                        _fetchFolders();
                      },
                    );
                  },
                ),
    );
  }
}

class FileBrowserPage extends StatefulWidget {
  final Directory targetDirectory;
  const FileBrowserPage({super.key, required this.targetDirectory});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _entities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    setState(() => _loading = true);
    final list = widget.targetDirectory.listSync().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      _entities = list;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _uploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    for (final pickedFile in result.files) {
      if (pickedFile.bytes != null) {
        final safeName = p.basename(pickedFile.name);
        final destinationPath = p.join(widget.targetDirectory.path, safeName);
        final newFile = File(destinationPath);
        await newFile.writeAsBytes(pickedFile.bytes!, flush: true);
      }
    }
    _toast('فایل‌ها با موفقیت اضافه شدند.');
    await _refreshFiles();
  }

  Future<void> _extractZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    try {
      final archive = ZipDecoder().decodeBytes(result.files.single.bytes!);
      final baseFolder = widget.targetDirectory;

      for (final archiveFile in archive) {
        final normalizedName = p.normalize(archiveFile.name);
        final fullDestinationPath = p.join(baseFolder.path, normalizedName);

        if (archiveFile.isFile) {
          final outFile = File(fullDestinationPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(archiveFile.content as List<int>, flush: true);
        } else {
          await Directory(fullDestinationPath).create(recursive: true);
        }
      }

      _toast('فایل‌های ZIP استخراج شدند.');
      await _refreshFiles();
    } catch (e) {
      _toast('خطا در استخراج ZIP: $e');
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    await entity.delete(recursive: true);
    await _refreshFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.targetDirectory.path)),
        actions: [
          IconButton(
            onPressed: _uploadFiles,
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'افزودن فایل HTML/CSS/JS',
          ),
          IconButton(
            onPressed: _extractZip,
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'افزودن فایل ZIP',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entities.isEmpty
              ? const Center(
                  child: Text(
                    'این پوشه خالی است.\nاز دکمه‌های بالا فایل HTML یا ZIP را اضافه کنید.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: _entities.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final entity = _entities[i];
                    final isDir = entity is Directory;
                    final isHtml = entity.path.toLowerCase().endsWith('.html') ||
                        entity.path.toLowerCase().endsWith('.htm');

                    return ListTile(
                      leading: Icon(
                        isDir ? Icons.folder : (isHtml ? Icons.html : Icons.description),
                        color: isHtml ? Colors.deepOrange : (isDir ? Colors.amber : Colors.blueGrey),
                        size: 30,
                      ),
                      title: Text(p.basename(entity.path)),
                      subtitle: Text(isDir ? 'پوشه' : '${(File(entity.path).lengthSync() / 1024).toStringAsFixed(1)} KB'),
                      onTap: () {
                        if (isDir) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FileBrowserPage(targetDirectory: entity as Directory),
                            ),
                          );
                        } else if (isHtml) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WebViewerServerPage(
                                rootDir: widget.targetDirectory,
                                htmlFile: File(entity.path),
                              ),
                            ),
                          );
                        }
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () => _deleteEntity(entity),
                      ),
                    );
                  },
                ),
    );
  }
}

/// صفحه اجرای وب با استفاده از وب‌سرور لوکال (راهکار قطعی رفع صفحه سفید)
class WebViewerServerPage extends StatefulWidget {
  final Directory rootDir;
  final File htmlFile;

  const WebViewerServerPage({
    super.key,
    required this.rootDir,
    required this.htmlFile,
  });

  @override
  State<WebViewerServerPage> createState() => _WebViewerServerPageState();
}

class _WebViewerServerPageState extends State<WebViewerServerPage> {
  HttpServer? _server;
  String? _serverUrl;
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    _startLocalServer();
  }

  /// راه‌اندازی سرور داخلی لوکال برای خواندن فایل‌های پروژه بدون مشکل کرومیوم
  Future<void> _startLocalServer() async {
    try {
      // ایجاد سرور روی localhost با پورت آزاد تصادفی
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      
      _server!.listen((HttpRequest request) async {
        try {
          String requestedPath = request.uri.path;
          if (requestedPath.startsWith('/')) {
            requestedPath = requestedPath.substring(1);
          }
          requestedPath = Uri.decodeComponent(requestedPath);

          // پیدا کردن فایل درخواستی نسبت به پوشه پروژه
          final targetFile = File(p.join(widget.rootDir.path, requestedPath));

          if (await targetFile.exists()) {
            final ext = p.extension(targetFile.path).toLowerCase();
            final contentType = _getContentType(ext);
            request.response.headers.contentType = contentType;
            await request.response.addStream(targetFile.openRead());
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('فایل یافت نشد');
          }
        } catch (e) {
          request.response.statusCode = HttpStatus.internalServerError;
        } finally {
          await request.response.close();
        }
      });

      // محاسبه آدرس نسبی فایل html برای درخواست به سرور
      final relativePath = p.relative(widget.htmlFile.path, from: widget.rootDir.path);
      final encodedPath = Uri.encodeComponent(relativePath).replaceAll('%2F', '/');

      setState(() {
        _serverUrl = 'http://127.0.0.1:${_server!.port}/$encodedPath';
        _serverReady = true;
      });
    } catch (e) {
      debugPrint('Error starting server: $e');
    }
  }

  ContentType _getContentType(String ext) {
    switch (ext) {
      case '.html':
      case '.htm':
        return ContentType.html;
      case '.css':
        return ContentType('text', 'css');
      case '.js':
        return ContentType('application', 'javascript');
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.gif':
        return ContentType('image', 'gif');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.json':
        return ContentType.json;
      default:
        return ContentType.binary;
    }
  }

  @override
  void dispose() {
    _server?.close(force: true); // بستن سرور هنگام خروج از صفحه برای صرفه‌جویی در رم
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.htmlFile.path)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: !_serverReady
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_progress < 1.0)
                  LinearProgressIndicator(value: _progress),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_serverUrl!)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      clearCache: true,
                      supportZoom: true,
                      builtInZoomControls: true,
                      displayZoomControls: false,
                      allowsInlineMediaPlayback: true,
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onProgressChanged: (_, progress) {
                      setState(() => _progress = progress / 100);
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      debugPrint('Web Console: ${consoleMessage.message}');
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
