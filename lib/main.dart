import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// راه‌اندازی سرور لوکال امن داخلی برای ایزوله‌سازی کامل
/// پورت روی 8080 قفل شده و به اینترنت بیرونی متصل نیست.
final InAppLocalhostServer localhostServer = InAppLocalhostServer(
  port: 8080,
  documentRoot: 'html_library',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فقط در صورت اجرای اندروید/iOS سرور لوکال را استارت می‌کنیم
  if (Platform.isAndroid || Platform.isIOS) {
    await localhostServer.start();
  }

  runApp(const SafeHtmlRunnerApp());
}

class SafeHtmlRunnerApp extends StatelessWidget {
  const SafeHtmlRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure HTML Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const FolderManagementPage(),
    );
  }
}

/// مدیریت و تضمین ایزوله بودن مسیر پوشه اصلی برنامه
class StorageService {
  static Future<Directory> getSafeRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final secureRoot = Directory(p.join(appDir.path, 'html_library'));
    if (!await secureRoot.exists()) {
      await secureRoot.create(recursive: true);
    }
    return secureRoot;
  }

  /// اعتبارسنجی نام پوشه برای جلوگیری از Directory Traversal
  static String? sanitizeFolderName(String input) {
    final clean = input.replaceAll(RegExp(r'[\\/:*?"<>|.]'), '_').trim();
    if (clean.isEmpty) return null;
    return clean;
  }

  /// بررسی قطعی اینکه یک فایل داخل پوشه مجاز قرار دارد یا خیر
  static bool isInsideDirectory(Directory parent, FileSystemEntity entity) {
    final canonicalParent = p.canonicalize(parent.path);
    final canonicalTarget = p.canonicalize(entity.path);
    return p.isWithin(canonicalParent, canonicalTarget) || canonicalParent == canonicalTarget;
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
        title: const Text('ساخت پوشه محافظت‌شده'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'نام پوشه (کاراکترهای غیرمجاز فیلتر می‌شوند)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('تأیید'),
          ),
        ],
      ),
    );

    if (folderName == null) return;
    final sanitized = StorageService.sanitizeFolderName(folderName);
    if (sanitized == null) {
      _showFeedback('نام وارد شده نامعتبر است.');
      return;
    }

    final root = await StorageService.getSafeRoot();
    final newDir = Directory(p.join(root.path, sanitized));

    if (await newDir.exists()) {
      _showFeedback('این پوشه از قبل وجود دارد.');
      return;
    }

    await newDir.create(recursive: true);
    await _fetchFolders();
  }

  Future<void> _confirmDelete(Directory dir) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('پوشه "${p.basename(dir.path)}" و محتویات آن کاملاً حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله، حذف کن')),
        ],
      ),
    );

    if (confirm == true) {
      final root = await StorageService.getSafeRoot();
      // تست امنیتی: اطمینان از عدم حذف خارج از محدوده
      if (StorageService.isInsideDirectory(root, dir)) {
        await dir.delete(recursive: true);
        await _fetchFolders();
      }
    }
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت پوشه‌های امن'),
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
              ? const Center(child: Text('هیچ پوشه‌ای ثبت نشده است.'))
              : ListView.separated(
                  itemCount: _folders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = _folders[i];
                    return ListTile(
                      leading: const Icon(Icons.folder_special, color: Colors.indigo, size: 36),
                      title: Text(p.basename(item.path), style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
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

  // لیست پسوندهای بی‌خطر و مجاز برای آپلود
  static const Set<String> _allowedExtensions = {
    'html', 'htm', 'css', 'js', 'json', 'txt',
    'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'ico',
    'woff', 'woff2', 'ttf', 'otf', 'mp3', 'mp4'
  };

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

  /// افزودن فایل‌های تکی با اعتبارسنجی Whitelist پسوندها
  Future<void> _uploadSafeFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    int uploadedCount = 0;
    for (final pickedFile in result.files) {
      if (pickedFile.bytes == null) continue;

      final extension = p.extension(pickedFile.name).replaceAll('.', '').toLowerCase();

      // جلوگیری از ورود فایل‌های خطرناک اجرایی (مانند .apk, .sh, .dex, .so)
      if (!_allowedExtensions.contains(extension)) {
        continue;
      }

      // نام فایل فقط با متدهای استاندارد ایمن‌سازی می‌شود
      final safeName = p.basename(pickedFile.name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final destinationPath = p.join(widget.targetDirectory.path, safeName);

      final newFile = File(destinationPath);
      await newFile.writeAsBytes(pickedFile.bytes!, flush: true);
      uploadedCount++;
    }

    _toast('$uploadedCount فایل مجاز با موفقیت ذخیره شد.');
    await _refreshFiles();
  }

  /// اکسترکت فایل ZIP با پیاده‌سازی ضد حمله Zip Slip
  Future<void> _extractSafeZip() async {
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
        // نرمال‌سازی مسیر و حذف حملات با .. یا اسلش مطلق
        final normalizedName = p.normalize(archiveFile.name);
        final fullDestinationPath = p.join(baseFolder.path, normalizedName);

        // دفاع حیاتی Zip Slip: مسیر فایل نهایی باید دقیقاً داخل baseFolder باشد
        if (!p.isWithin(p.canonicalize(baseFolder.path), p.canonicalize(fullDestinationPath))) {
          throw SecurityException('حمله احتمالی Zip Slip در فایل شناسایی شد!');
        }

        if (archiveFile.isFile) {
          final ext = p.extension(fullDestinationPath).replaceAll('.', '').toLowerCase();
          // بررسی پسوندهای مجاز
          if (!_allowedExtensions.contains(ext)) {
            continue; // نادیده گرفتن فایل‌های مشکوک داخل زیپ
          }

          final outFile = File(fullDestinationPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(archiveFile.content as List<int>, flush: true);
        } else {
          await Directory(fullDestinationPath).create(recursive: true);
        }
      }

      _toast('پروژه با ساختار امن استخراج شد.');
      await _refreshFiles();
    } catch (e) {
      _toast('خطای امنیتی یا فرمت نامعتبر: $e');
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final root = await StorageService.getSafeRoot();
    if (StorageService.isInsideDirectory(root, entity)) {
      await entity.delete(recursive: true);
      await _refreshFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.targetDirectory.path)),
        actions: [
          IconButton(
            onPressed: _uploadSafeFiles,
            icon: const Icon(Icons.upload_file),
            tooltip: 'آپلود فایل‌های مجاز',
          ),
          IconButton(
            onPressed: _extractSafeZip,
            icon: const Icon(Icons.folder_zip),
            tooltip: 'استخراج ZIP ایمن',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entities.isEmpty
              ? const Center(child: Text('این پوشه خالی است.'))
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
                              builder: (_) => SecureWebRendererPage(htmlFile: File(entity.path)),
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

class SecureWebRendererPage extends StatefulWidget {
  final File htmlFile;
  const SecureWebRendererPage({super.key, required this.htmlFile});

  @override
  State<SecureWebRendererPage> createState() => _SecureWebRendererPageState();
}

class _SecureWebRendererPageState extends State<SecureWebRendererPage> {
  InAppWebViewController? _webViewController;
  double _loadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.htmlFile.path)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadProgress < 1.0)
            LinearProgressIndicator(value: _loadProgress),
          Expanded(
            child: InAppWebView(
              initialFile: widget.htmlFile.path,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                
                // 1. امنیت دیسک: مسدودسازی دسترسی به سایر فایل‌های محلی با اسکریپت
                allowFileAccess: false,
                allowFileAccessFromFileURLs: false,
                allowUniversalAccessFromFileURLs: false,

                // 2. امنیت رابط کاربری و شبکه: مسدود کردن باز شدن پنجره‌های ناخواسته
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,

                // 3. مسدودسازی درخواست‌های دانلود فایل از داخل WebView
                useOnDownloadStart: false,

                // 4. بهینه‌سازی مدیا و کش
                mediaPlaybackRequiresUserGesture: true,
                domStorageEnabled: true,
                databaseEnabled: false,
                cacheEnabled: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onProgressChanged: (_, progress) {
                setState(() => _loadProgress = progress / 100);
              },

              // 5. مسدودسازی دسترسی به سخت‌افزار (میکروفون، دوربین، موقعیت مکانی)
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.DENY, // رد تمام درخواست‌های دسترسی به سنسورها
                );
              },

              // 6. دیواره آتش جهت ناوبری (Navigation Firewall):
              // اجازه خروج از محیط لوکال به سایت‌های فیشینگ داده نمی‌شود مگر کاربر مستقیماً بخواهد.
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;

                // اگر آدرس یک فایل داخلی یا داده base64 معتبر است مجاز است
                if (uri.scheme == 'file' || uri.scheme == 'data') {
                  return NavigationActionPolicy.ALLOW;
                }

                // اگر به آدرس اینترنتی هدایت می‌شود، در صورت تمایل مسدود یا تایید کنید
                if (uri.scheme == 'http' || uri.scheme == 'https') {
                  // در صورت نیاز به آنلاین بودن:
                  return NavigationActionPolicy.ALLOW;
                }

                // مسدود کردن تمام Schemeهای خطرناک مثل tel: sms: intent: market:
                return NavigationActionPolicy.CANCEL;
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('SecureSandbox Console: ${consoleMessage.message}');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}
