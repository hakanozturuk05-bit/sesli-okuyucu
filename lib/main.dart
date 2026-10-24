import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

late List<CameraDescription> kameralar;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kameralar = await availableCameras();
  runApp(const SesliOkuyucuApp());
}

const _birler = ['', 'bir', 'iki', 'üç', 'dört', 'beş', 'altı', 'yedi', 'sekiz', 'dokuz'];
const _onlar = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli', 'altmış', 'yetmiş', 'seksen', 'doksan'];

String _yuzluk(int n) {
  final y = n ~/ 100, o = (n % 100) ~/ 10, b = n % 10;
  final p = <String>[];
  if (y > 0) {
    if (y > 1) p.add(_birler[y]);
    p.add('yüz');
  }
  if (o > 0) p.add(_onlar[o]);
  if (b > 0) p.add(_birler[b]);
  return p.join(' ');
}

String sayiyiYaziyaCevir(int n) {
  if (n == 0) return 'sıfır';
  final p = <String>[];
  for (final g in [[1000000000, 'milyar'], [1000000, 'milyon'], [1000, 'bin']]) {
    final b = g[0] as int;
    final q = n ~/ b;
    if (q > 0) {
      if (!(b == 1000 && q == 1)) p.add(_yuzluk(q));
      p.add(g[1] as String);
      n %= b;
    }
  }
  if (n > 0) p.add(_yuzluk(n));
  return p.join(' ');
}

/// "742,50" -> "yedi yüz kırk iki virgül elli", "500" -> "beş yüz"
String sayilariYaziyaCevir(String metin) {
  final s = metin.replaceAllMapped(
    RegExp(r'(\d+),(\d+)'),
    (m) => '${m[1]} virgül ${m[2]}',
  );
  return s.replaceAllMapped(RegExp(r'\d+'), (m) {
    final t = m[0]!;
    return t.length > 12 ? t : sayiyiYaziyaCevir(int.parse(t));
  });
}

class SesliOkuyucuApp extends StatelessWidget {
  const SesliOkuyucuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sesli Okuyucu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const OkumaEkrani(),
    );
  }
}

class OkumaEkrani extends StatefulWidget {
  const OkumaEkrani({super.key});

  @override
  State<OkumaEkrani> createState() => _OkumaEkraniState();
}

class _OkumaEkraniState extends State<OkumaEkrani> {
  CameraController? _kamera;
  final FlutterTts _tts = FlutterTts();
  final TextRecognizer _ocr = TextRecognizer(script: TextRecognitionScript.latin);

  bool _hazir = false;
  bool _mesgul = false;
  String _sonMetin = '';
  String _durum = 'Hazırlanıyor...';

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);

    try {
      _kamera = CameraController(
        kameralar.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _kamera!.initialize();
      if (!mounted) return;
      setState(() {
        _hazir = true;
        _durum = 'Okumak için ekrana dokunun';
      });
      await _soyle(
        'Sesli okuyucu hazır. Yazıyı kameraya tutun ve ekranın herhangi bir '
        'yerine dokunun. Son okunanı tekrar dinlemek için ekrana uzun basın.',
      );
    } catch (_) {
      setState(() => _durum = 'Kamera açılamadı');
      await _soyle('Kamera açılamadı. Lütfen kamera iznini kontrol edin.');
    }
  }

  Future<void> _soyle(String metin) async {
    await _tts.stop();
    await _tts.speak(sayilariYaziyaCevir(metin));
  }

  Future<void> _oku() async {
    if (!_hazir || _mesgul) return;
    setState(() {
      _mesgul = true;
      _durum = 'Okunuyor...';
    });
    HapticFeedback.mediumImpact();

    try {
      await _tts.stop();
      final foto = await _kamera!.takePicture();
      final sonuc = await _ocr.processImage(InputImage.fromFilePath(foto.path));
      final metin = sonuc.text.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (metin.isEmpty) {
        HapticFeedback.heavyImpact();
        setState(() => _durum = 'Yazı bulunamadı');
        await _soyle(
          'Yazı bulunamadı. Telefonu biraz uzaklaştırın, yazıyı ortalayın '
          've tekrar deneyin.',
        );
      } else {
        _sonMetin = metin;
        setState(() => _durum = metin);
        HapticFeedback.lightImpact();
        await _soyle(metin);
      }
    } catch (_) {
      await _soyle('Bir hata oluştu. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) {
        setState(() {
          _mesgul = false;
          if (_sonMetin.isEmpty) _durum = 'Okumak için ekrana dokunun';
        });
      }
    }
  }

  Future<void> _tekrarOku() async {
    if (_sonMetin.isEmpty) {
      await _soyle('Henüz okunmuş bir yazı yok.');
    } else {
      await _soyle(_sonMetin);
    }
  }

  @override
  void dispose() {
    _kamera?.dispose();
    _ocr.close();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        button: true,
        label: 'Yazıyı oku. Çift dokunarak fotoğraf çekin. Uzun basarak son metni tekrar dinleyin.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _oku,
          onLongPress: _tekrarOku,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hazir && _kamera != null)
                CameraPreview(_kamera!)
              else
                const Center(child: CircularProgressIndicator()),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black87,
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _durum,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.yellow,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
