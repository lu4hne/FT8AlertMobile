import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'audio_manager.dart';
import 'sync_player.dart';

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
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'v${info.version}';
    });
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acerca de FT8Alert Mobile'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aplicación compañera para FT8Alert. Permite escanear códigos QR desde la PC para descargar y reproducir alertas de audio en tiempo sincronizado (NTP o local).'),
            SizedBox(height: 16),
            Text('Desarrollado por:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Maximiliano Duarte LU4HNE'),
            Text('lu4hne@gmail.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('FT8Alert Companion $_version'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: 'Acerca de',
          ),
        ],
      ),
      body: _currentIndex == 0 
          ? const AudioListTab() 
          : ScannerTab(onDownloaded: () => _onTabTapped(0)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Mis Audios',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Escáner QR',
          ),
        ],
      ),
    );
  }
}

class AudioListTab extends StatefulWidget {
  const AudioListTab({super.key});

  @override
  State<AudioListTab> createState() => _AudioListTabState();
}

class _AudioListTabState extends State<AudioListTab> {
  List<File> _audios = [];
  final SyncPlayer _syncPlayer = SyncPlayer();
  String _playerStatus = 'Listo';

  @override
  void initState() {
    super.initState();
    _loadAudios();
    _syncPlayer.onStatusChanged = (status) {
      if (mounted) setState(() => _playerStatus = status);
    };
    _syncPlayer.onPlaybackFinished = () {
      if (mounted) setState(() => _playerStatus = 'Listo');
    };
  }

  @override
  void dispose() {
    _syncPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAudios() async {
    final audios = await AudioManager.getSavedAudios();
    if (mounted) {
      setState(() => _audios = audios);
    }
  }

  Future<void> _deleteAudio(File file) async {
    await AudioManager.deleteAudio(file);
    _loadAudios();
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // We call loadAudios in build in case the tab was hidden and now shown, 
    // although IndexedStack keeps it alive. We can use a RefreshIndicator.
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          width: double.infinity,
          child: Text(
            'Estado: $_playerStatus',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        if (_syncPlayer.currentMode != PlaybackMode.none)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () => _syncPlayer.stop(),
              icon: const Icon(Icons.stop),
              label: const Text('Detener Reproducción'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAudios,
            child: _audios.isEmpty
                ? const Center(child: Text('No hay audios guardados. Escanea un QR.'))
                : ListView.builder(
                    itemCount: _audios.length,
                    itemBuilder: (context, index) {
                      final file = _audios[index];
                      final filename = file.path.split('/').last;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ExpansionTile(
                          title: Text(filename),
                          leading: const Icon(Icons.audiotrack, color: Colors.blue),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildActionBtn(Icons.play_arrow, Colors.green, 'Normal', () => _syncPlayer.playAsync(file)),
                                  _buildActionBtn(Icons.sync, Colors.orange, 'Sync NTP', () => _syncPlayer.playSyncNtp(file)),
                                  _buildActionBtn(Icons.mic, Colors.purple, 'Micrófono', () => _syncPlayer.playSyncMic(file)),
                                  _buildActionBtn(Icons.delete, Colors.red, 'Eliminar', () => _deleteAudio(file)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class ScannerTab extends StatefulWidget {
  final VoidCallback onDownloaded;
  const ScannerTab({super.key, required this.onDownloaded});

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  bool _isDownloading = false;
  String _status = 'Apunta al código QR en tu PC';
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isDownloading) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? qrCodeValue = barcodes.first.rawValue;

      if (qrCodeValue != null && qrCodeValue.contains('/download_ft8_audio/')) {
        setState(() {
          _isDownloading = true;
          _status = 'Descargando audio...';
        });

        final file = await AudioManager.downloadAndSaveAudio(qrCodeValue);
        
        if (mounted) {
          setState(() {
            _isDownloading = false;
            if (file != null) {
              _status = '¡Audio descargado!';
              widget.onDownloaded();
            } else {
              _status = 'Error al descargar.';
            }
          });
          
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _status = 'Apunta al código QR en tu PC';
              });
            }
          });
        }
      } else {
        setState(() {
          _status = 'QR Inválido: Apunta al QR de FT8Alert';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                controller: _scannerController,
                fit: BoxFit.cover,
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
                if (_isDownloading)
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
    );
  }
}
