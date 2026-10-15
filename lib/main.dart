import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // برای بعضی دستگاه‌ها بهتر است WebView قبل از اجرا آماده شود
  await InAppWebViewController.setWebContentsDebuggingEnabled(true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTML Folder Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const FolderListPage(),
    );
  }
}

/// مسیر ریشه‌ی کتابخانه HTML داخل فضای اپ
Future<Directory> getHtmlLibraryRoot() async {
  final dir = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(dir.path, 'html_library'));
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return root;
}

class FolderListPage extends StatefulWidget {
  const FolderListPage({super.key});

  @override
  State<FolderListPage> createState() => _FolderListPageState();
}

class _FolderListPageState extends State<FolderListPage> {
  List<Directory> folders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => loading = true);
    final root = await getHtmlLibraryRoot();
    final items = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      folders = items;
      loading = false;
    });
  }

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ساخت پوشه جدید'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'مثلاً: پروژه‌ها',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('بساز'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final root = await getHtmlLibraryRoot();
    final newDir = Directory(p.join(root.path, name));
    if (await newDir.exists()) {
      _toast('این پوشه از قبل وجود دارد');
      return;
    }
    await newDir.create(recursive: true);
    await _loadFolders();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _deleteFolder(Directory dir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پوشه'),
        content: Text('پوشه "${p.basename(dir.path)}" حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('نه'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بله، حذف کن'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await dir.delete(recursive: true);
    await _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پوشه‌ها'),
        actions: [
          IconButton(
            onPressed: _loadFolders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFolderDialog,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('پوشه جدید'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : folders.isEmpty
              ? const Center(child: Text('هیچ پوشه‌ای ساخته نشده.'))
              : ListView.separated(
                  itemCount: folders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final dir = folders[i];
                    final name = p.basename(dir.path);
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(name),
                      subtitle: Text(dir.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FolderDetailPage(folderDir: dir),
                          ),
                        );
                        _loadFolders();
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteFolder(dir),
                      ),
                    );
                  },
                ),
    );
  }
}

class FolderDetailPage extends StatefulWidget {
  final Directory folderDir;
  const FolderDetailPage({super.key, required this.folderDir});

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  List<FileSystemEntity> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => loading = true);
    final list = widget.folderDir.listSync().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      items = list;
      loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Import یک ZIP پروژه HTML داخل همین پوشه
  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true, // داده را در حافظه می‌گیرد تا extract کنیم
    );
    if (result == null) return;

    final fileBytes = result.files.single.bytes;
    final fileName = result.files.single.name;

    if (fileBytes == null) {
      _toast('خواندن فایل ممکن نشد.');
      return;
    }

    // یک زیرپوشه با نام zip ایجاد می‌کنیم تا پروژه‌ها قاطی نشوند
    final projectName = p.basenameWithoutExtension(fileName);
    final targetDir = Directory(p.join(widget.folderDir.path, projectName));
    if (await targetDir.exists()) {
      _toast('پروژه "$projectName" از قبل وجود دارد.');
      return;
    }
    await targetDir.create(recursive: true);

    try {
      final archive = ZipDecoder().decodeBytes(fileBytes);

      for (final entry in archive) {
        final entryPath = entry.name;

        // جلوگیری از ZipSlip (امنیت مسیرها)
        final normalized = p.normalize(entryPath);
        if (normalized.startsWith('..') || p.isAbsolute(normalized)) {
          continue;
        }

        final outPath = p.join(targetDir.path, normalized);

        if (entry.isFile) {
          final data = entry.content as List<int>;
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data, flush: true);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      _toast('Import انجام شد.');
      await _loadItems();
    } catch (e) {
      _toast('خطا در باز کردن ZIP: $e');
      // اگر خطا شد پروژه نیمه‌کاره را پاک می‌کنیم
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    }
  }

  /// پیدا کردن فایل ورودی: اول index.html، اگر نبود، اولین فایل html
  File? _findEntryHtmlFile(Directory projectDir) {
    final index = File(p.join(projectDir.path, 'index.html'));
    if (index.existsSync()) return index;

    final all = projectDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.html'))
        .toList();

    if (all.isEmpty) return null;

    // ترجیح: نزدیک‌ترین فایل به ریشه
    all.sort((a, b) => a.path.split(Platform.pathSeparator).length
        .compareTo(b.path.split(Platform.pathSeparator).length));
    return all.first;
  }

  Future<void> _openProject(Directory projectDir) async {
    final entry = _findEntryHtmlFile(projectDir);
    if (entry == null) {
      _toast('هیچ فایل HTML داخل این پروژه پیدا نشد.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HtmlRunnerPage(entryFile: entry),
      ),
    );
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف'),
        content: Text('"$name" حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('نه')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
        ],
      ),
    );

    if (ok != true) return;
    await entity.delete(recursive: true);
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final folderName = p.basename(widget.folderDir.path);

    return Scaffold(
      appBar: AppBar(
        title: Text('پوشه: $folderName'),
        actions: [
          IconButton(
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _importZip,
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Import ZIP',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'چیزی داخل این پوشه نیست.\nاز بالا (Import ZIP) یک پروژه HTML وارد کن.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final entity = items[i];
                    final name = p.basename(entity.path);
                    final isDir = FileSystemEntity.isDirectorySync(entity.path);

                    return ListTile(
                      leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined),
                      title: Text(name),
                      subtitle: Text(entity.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: isDir
                          ? () => _openProject(Directory(entity.path))
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteEntity(entity),
                      ),
                    );
                  },
                ),
    );
  }
}

class HtmlRunnerPage extends StatefulWidget {
  final File entryFile;
  const HtmlRunnerPage({super.key, required this.entryFile});

  @override
  State<HtmlRunnerPage> createState() => _HtmlRunnerPageState();
}

class _HtmlRunnerPageState extends State<HtmlRunnerPage> {
  InAppWebViewController? controller;
  double progress = 0;

  @override
  Widget build(BuildContext context) {
    final title = p.basename(widget.entryFile.path);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 1)
            LinearProgressIndicator(value: progress),
          Expanded(
            child: InAppWebView(
              initialFile: widget.entryFile.path,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                // اگر پروژه‌ها منابع آنلاین دارند این را روشن نگه داریم
                blockNetworkLoads: false,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                mediaPlaybackRequiresUserGesture: false,
                transparentBackground: false,
              ),
              onWebViewCreated: (c) => controller = c,
              onProgressChanged: (_, p) => setState(() => progress = p / 100.0),
            ),
          ),
        ],
      ),
    );
  }
}
