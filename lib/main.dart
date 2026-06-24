import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const FT8AlertMobileApp());
}

class FT8AlertMobileApp extends StatelessWidget {
  const FT8AlertMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FT8Alert Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isDownloading = false;
  bool _isPlaying = false;
  String _status = 'Apunta al código QR en tu PC';

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isDownloading || _isPlaying) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? qrCodeValue = barcodes.first.rawValue;
      
      if (qrCodeValue != null && qrCodeValue.contains('/download_ft8_audio/')) {
        setState(() {
          _isDownloading = true;
          _status = 'Descargando audio...';
        });

        try {
          // Download file
          final response = await http.get(Uri.parse(qrCodeValue));
          
          if (response.statusCode == 200) {
            setState(() {
              _status = 'Reproduciendo audio FT8...';
              _isPlaying = true;
            });
            
            // Save to temp directory
            final directory = await getTemporaryDirectory();
            final filePath = '${directory.path}/ft8_audio.wav';
            final file = File(filePath);
            await file.writeAsBytes(response.bodyBytes);
            
            // Play audio
            await _audioPlayer.play(DeviceFileSource(filePath));
            
            _audioPlayer.onPlayerComplete.listen((event) {
              if (mounted) {
                setState(() {
                  _isPlaying = false;
                  _isDownloading = false;
                  _status = 'Audio finalizado. Escanea otro QR.';
                });
              }
            });
          } else {
            _showError('Error al descargar: Código ${response.statusCode}');
          }
        } catch (e) {
          _showError('Error de red: No se pudo conectar a la PC.');
        }
      } else {
         // Prevent spamming error
         setState(() {
           _status = 'QR Inválido: Apunta al QR de FT8Alert';
         });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isPlaying = false;
      _status = message;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isDownloading && !_isPlaying) {
        setState(() {
          _status = 'Apunta al código QR en tu PC';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FT8Alert Companion'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: MobileScanner(
                  onDetect: _handleBarcode,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDownloading || _isPlaying) 
                    const CircularProgressIndicator()
                  else 
                    const Icon(Icons.qr_code_scanner, size: 48, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
