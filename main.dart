import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Android emulator: 10.0.2.2 | iOS sim: 127.0.0.1 | cihaz: bilgisayar LAN IP
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);

const storage = FlutterSecureStorage();

void main() {
  runApp(const ProviderScope(child: OptiyoApp()));
}

class OptiyoApp extends ConsumerWidget {
  const OptiyoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Optiyo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2563EB),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        final refresh = await storage.read(key: 'refresh_token');
        if (refresh != null) {
          try {
            final res = await Dio().post(
              '$apiBase/auth/refresh',
              options: Options(headers: {'Authorization': 'Bearer $refresh'}),
            );
            await storage.write(key: 'access_token', value: res.data['access_token']);
            await storage.write(key: 'refresh_token', value: res.data['refresh_token']);
            error.requestOptions.headers['Authorization'] =
                'Bearer ${res.data['access_token']}';
            return handler.resolve(await dio.fetch(error.requestOptions));
          } catch (_) {}
        }
      }
      return handler.next(error);
    },
  ));
  return dio;
});

class Product {
  final String id;
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final String? imageUrl;
  final double? aiScore;

  Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    this.imageUrl,
    this.aiScore,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'].toString(),
        barcode: j['barcode'] ?? '',
        name: j['name'] ?? '',
        brand: j['brand'] ?? '',
        category: j['category'] ?? '',
        imageUrl: j['image_url'],
        aiScore: (j['ai_score'] as num?)?.toDouble(),
      );
}

class AuthState {
  final bool loggedIn;
  final String? name;
  final String? email;
  final bool loading;

  AuthState({
    this.loggedIn = false,
    this.name,
    this.email,
    this.loading = false,
  });
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;
  AuthNotifier(this.ref) : super(AuthState()) {
    _boot();
  }

  Future<void> _boot() async {
    final t = await storage.read(key: 'access_token');
    if (t == null) return;
    try {
      final r = await ref.read(dioProvider).get('/user/profile');
      state = AuthState(
        loggedIn: true,
        name: r.data['name'],
        email: r.data['email'],
      );
    } catch (_) {
      await logout();
    }
  }

  Future<bool> login(String email, String password) async {
    state = AuthState(loading: true);
    try {
      final r = await ref.read(dioProvider).post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await storage.write(key: 'access_token', value: r.data['access_token']);
      await storage.write(key: 'refresh_token', value: r.data['refresh_token']);
      await _boot();
      return true;
    } catch (_) {
      state = AuthState();
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    try {
      await ref.read(dioProvider).post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      return login(email, password);
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await storage.deleteAll();
    state = AuthState();
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));

final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final r = await ref.read(dioProvider).get('/products');
  return (r.data as List).map((e) => Product.fromJson(e)).toList();
});

final searchProvider =
    FutureProvider.autoDispose.family<List<Product>, String>((ref, q) async {
  if (q.trim().isEmpty) return [];
  final r = await ref
      .read(dioProvider)
      .get('/products/search', queryParameters: {'q': q});
  return (r.data as List).map((e) => Product.fromJson(e)).toList();
});

final detailProvider =
    FutureProvider.autoDispose.family<Product, String>((ref, id) async {
  final r = await ref.read(dioProvider).get('/products/$id');
  return Product.fromJson(r.data);
});

final pricesProvider =
    FutureProvider.autoDispose.family<List<Map>, String>((ref, id) async {
  final r = await ref.read(dioProvider).get('/prices/$id');
  return List<Map>.from(r.data);
});

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/ocr', builder: (_, __) => const OcrScreen()),
      GoRoute(
        path: '/product/:id',
        builder: (_, s) => DetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ],
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(productsProvider);
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optiyo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => context.push('/scan'),
          ),
          IconButton(
            icon: const Icon(Icons.document_scanner),
            onPressed: () => context.push('/ocr'),
          ),
          IconButton(
            icon: Icon(auth.loggedIn ? Icons.logout : Icons.login),
            onPressed: () {
              if (auth.loggedIn) {
                ref.read(authProvider.notifier).logout();
              } else {
                context.push('/login');
              }
            },
          ),
        ],
      ),
      body: list.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Henüz ürün yok. API çalışıyor mu?'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  return ListTile(
                    leading: p.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: p.imageUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.image),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.brand} • skor ${p.aiScore?.toStringAsFixed(0) ?? "-"}',
                    ),
                    onTap: () => context.push('/product/${p.id}'),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(searchProvider(q));
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ürün ara...',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      body: res.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final p = items[i];
            return ListTile(
              title: Text(p.name),
              subtitle: Text(p.brand),
              onTap: () => context.push('/product/${p.id}'),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barkod Tara')),
      body: MobileScanner(
        onDetect: (capture) async {
          if (done) return;
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code == null || code.length != 13) return;
          setState(() => done = true);
          try {
            final r = await ref.read(dioProvider).get('/barcode/$code');
            if (mounted) {
              context.push('/product/${r.data['product']['id']}');
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Bulunamadı: $code')),
              );
              setState(() => done = false);
            }
          }
        },
      ),
    );
  }
}

class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key});
  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> {
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  String text = '';
  bool loading = false;

  Future<void> run(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src);
    if (f == null) return;
    setState(() {
      loading = true;
      text = '';
    });
    try {
      final local = await rec.processImage(InputImage.fromFilePath(f.path));
      var out = local.text;
      try {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(f.path),
        });
        final r = await ref.read(dioProvider).post('/scan', data: form);
        out += '\n\nAI: ${r.data}';
      } catch (_) {}
      setState(() {
        text = out.isEmpty ? 'Metin yok' : out;
        loading = false;
      });
    } catch (e) {
      setState(() {
        text = '$e';
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    rec.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: loading ? null : () => run(ImageSource.camera),
                    child: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: loading ? null : () => run(ImageSource.gallery),
                    child: const Text('Galeri'),
                  ),
                ),
              ],
            ),
            if (loading) const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            Expanded(child: SingleChildScrollView(child: SelectableText(text))),
          ],
        ),
      ),
    );
  }
}

class DetailScreen extends ConsumerWidget {
  final String id;
  const DetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(detailProvider(id));
    final prices = ref.watch(pricesProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün')),
      body: p.when(
        data: (product) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (product.imageUrl != null)
              CachedNetworkImage(
                imageUrl: product.imageUrl!,
                height: 200,
                fit: BoxFit.cover,
              ),
            Text(
              product.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text('${product.brand} • ${product.category}'),
            const SizedBox(height: 16),
            const Text('Fiyatlar', style: TextStyle(fontWeight: FontWeight.bold)),
            prices.when(
              data: (list) => Column(
                children: list.map((x) {
                  return ListTile(
                    title: Text('${x['store']}'),
                    trailing: Text(
                      '${x['price']} ₺',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      try {
                        final r = await ref.read(dioProvider).post(
                          '/affiliate/click',
                          data: {
                            'product_id': id,
                            'store': x['store'],
                            'original_url': x['store_url'],
                          },
                        );
                        final url = r.data['redirect_url']?.toString();
                        if (url != null) {
                          final full = url.startsWith('http')
                              ? url
                              : apiBase.replaceAll('/api/v1', '') + url;
                          await launchUrl(
                            Uri.parse(full),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      } catch (_) {
                        final u = x['store_url']?.toString();
                        if (u != null) {
                          await launchUrl(
                            Uri.parse(u),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      }
                    },
                  );
                }).toList(),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final e = TextEditingController();
  final p = TextEditingController();
  final n = TextEditingController();
  bool reg = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: Text(reg ? 'Kayıt' : 'Giriş')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (reg)
              TextField(
                controller: n,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
            TextField(
              controller: e,
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
            TextField(
              controller: p,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Şifre'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: auth.loading
                  ? null
                  : () async {
                      final ok = reg
                          ? await ref.read(authProvider.notifier).register(
                                n.text.trim(),
                                e.text.trim(),
                                p.text,
                              )
                          : await ref.read(authProvider.notifier).login(
                                e.text.trim(),
                                p.text,
                              );
                      if (ok && context.mounted) context.go('/');
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Başarısız')),
                        );
                      }
                    },
              child: Text(reg ? 'Kayıt Ol' : 'Giriş'),
            ),
            TextButton(
              onPressed: () => setState(() => reg = !reg),
              child: Text(reg ? 'Girişe dön' : 'Hesap oluştur'),
            ),
          ],
        ),
      ),
    );
  }
}
