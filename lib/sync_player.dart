import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:ntp/ntp.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

enum PlaybackMode { none, async, syncNtp, syncMic }

class SyncPlayer {
  final AudioPlayer audioPlayer = AudioPlayer();
  Timer? _ntpTimer;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  PlaybackMode currentMode = PlaybackMode.none;
  Function(String)? onStatusChanged;
  Function()? onPlaybackFinished;

  void dispose() {
    _ntpTimer?.cancel();
    _noiseSubscription?.cancel();
    audioPlayer.dispose();
  }

  void stop() {
    _ntpTimer?.cancel();
    _noiseSubscription?.cancel();
    audioPlayer.stop();
    currentMode = PlaybackMode.none;
    _updateStatus('Detenido');
  }

  Future<void> playAsync(File file) async {
    stop();
    currentMode = PlaybackMode.async;
    _updateStatus('Reproduciendo (Async)...');
    await _playFile(file);
  }

  Future<void> playSyncNtp(File file) async {
    stop();
    currentMode = PlaybackMode.syncNtp;
    _updateStatus('Sincronizando con NTP...');

    try {
      final DateTime myTime = await NTP.now();
      final int second = myTime.second;
      final int ms = myTime.millisecond;
      
      // Calculate ms into the current minute
      final int currentMsInMinute = second * 1000 + ms;
      
      // FT8 slots are at 0, 15000, 30000, 45000 ms
      const int slotDurationMs = 15000;
      final int nextSlotMs = ((currentMsInMinute ~/ slotDurationMs) + 1) * slotDurationMs;
      
      final int waitTimeMs = nextSlotMs - currentMsInMinute;
      final double waitSeconds = waitTimeMs / 1000.0;
      
      _updateStatus('Esperando ${waitSeconds.toStringAsFixed(1)}s (NTP)...');
      
      _ntpTimer = Timer(Duration(milliseconds: waitTimeMs), () {
        if (currentMode == PlaybackMode.syncNtp) {
          _updateStatus('Reproduciendo (NTP Sync)...');
          _playFile(file);
        }
      });
    } catch (e) {
      _updateStatus('Error NTP: $e');
      currentMode = PlaybackMode.none;
    }
  }

  Future<void> playSyncMic(File file) async {
    stop();
    currentMode = PlaybackMode.syncMic;
    
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _updateStatus('Permiso de micrófono denegado');
      currentMode = PlaybackMode.none;
      return;
    }

    _updateStatus('Escuchando pausa (Mic)...');

    try {
      final noiseMeter = NoiseMeter();
      int silenceStartTime = 0;
      bool isSilence = false;
      // We assume silence is below 50 dB (can be adjusted)
      const double silenceThresholdDb = 50.0;
      const int requiredSilenceMs = 1500;

      _noiseSubscription = noiseMeter.noise.listen((NoiseReading reading) {
        if (currentMode != PlaybackMode.syncMic) {
          _noiseSubscription?.cancel();
          return;
        }

        if (reading.meanDecibel < silenceThresholdDb) {
          if (!isSilence) {
            isSilence = true;
            silenceStartTime = DateTime.now().millisecondsSinceEpoch;
          } else {
            final int elapsedSilence = DateTime.now().millisecondsSinceEpoch - silenceStartTime;
            if (elapsedSilence >= requiredSilenceMs) {
              // Pause detected!
              _noiseSubscription?.cancel();
              _updateStatus('Pausa detectada. Reproduciendo...');
              _playFile(file);
            }
          }
        } else {
          isSilence = false;
        }
      }, onError: (e) {
        _updateStatus('Error en Micrófono: $e');
        currentMode = PlaybackMode.none;
      });
    } catch (e) {
      _updateStatus('Error inicializando Mic: $e');
      currentMode = PlaybackMode.none;
    }
  }

  Future<void> _playFile(File file) async {
    await audioPlayer.play(DeviceFileSource(file.path));
    audioPlayer.onPlayerComplete.listen((event) {
      if (currentMode != PlaybackMode.none) {
        currentMode = PlaybackMode.none;
        _updateStatus('Reproducción finalizada');
        onPlaybackFinished?.call();
      }
    });
  }

  void _updateStatus(String status) {
    if (onStatusChanged != null) {
      onStatusChanged!(status);
    }
  }
}
