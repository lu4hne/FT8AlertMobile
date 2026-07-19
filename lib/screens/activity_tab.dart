import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../audio_manager.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/qth_locator.dart';

class ActivityTab extends StatefulWidget {
  final VoidCallback onDownloaded;
  const ActivityTab({super.key, required this.onDownloaded});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  bool _isLoading = false;
  bool _isMetadataLoading = true;
  
  List<dynamic> _activityTypes = [];
  List<dynamic> _modes = [];
  
  int? _selectedTypeId;
  int? _selectedModeId;
  
  final _freqController = TextEditingController();
  final _refController = TextEditingController();
  final _qthController = TextEditingController();
  final _commentController = TextEditingController();

  int? _createdActivityId;

  DateTime _startTimeUtc = DateTime.now().toUtc();
  DateTime _endTimeUtc = DateTime.now().toUtc().add(const Duration(hours: 2));
  bool _waitReport = true;

  @override
  void initState() {
    super.initState();
    _checkLoginAndLoadData();
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _startTimeUtc : _endTimeUtc;
    
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (time == null) return;

    setState(() {
      final newUtc = DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
      if (isStart) {
        _startTimeUtc = newUtc;
        if (_endTimeUtc.isBefore(_startTimeUtc)) {
          _endTimeUtc = _startTimeUtc.add(const Duration(hours: 2));
        }
      } else {
        _endTimeUtc = newUtc;
      }
    });
  }

  bool _isCalculatingQth = false;

  Future<void> _calculateQth() async {
    setState(() => _isCalculatingQth = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permiso denegado');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permisos denegados permanentemente');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final locator = QthLocator.calculate(position.latitude, position.longitude);
      setState(() {
        _qthController.text = locator;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Locator calculado: $locator')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener la ubicación')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCalculatingQth = false);
      }
    }
  }

  Future<void> _checkLoginAndLoadData() async {
    await apiService.init();
    if (apiService.isAuthenticated) {
      _loadMetadata();
    } else {
      setState(() => _isMetadataLoading = false);
    }
  }

  Future<void> _loadMetadata() async {
    setState(() => _isMetadataLoading = true);
    final metadata = await apiService.getMetadata();
    setState(() {
      _activityTypes = metadata['activity_types'] ?? [];
      _modes = metadata['modes'] ?? [];
      if (_activityTypes.isNotEmpty) _selectedTypeId = _activityTypes.first['id'];
      if (_modes.isNotEmpty) _selectedModeId = _modes.first['id'];
      _isMetadataLoading = false;
    });
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final success = await apiService.login();
    if (success) {
      _loadMetadata();
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al iniciar sesión con Google')),
        );
      }
    }
  }

  Future<void> _logout() async {
    await apiService.logout();
    setState(() {});
  }

  Future<void> _createActivity() async {
    if (_selectedTypeId == null || _selectedModeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona tipo y modo')),
      );
      return;
    }

    if (_qthController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El QTH Locator es obligatorio')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    final id = await apiService.createActivity(
      activityTypeId: _selectedTypeId!,
      modeId: _selectedModeId!,
      freq: double.tryParse(_freqController.text),
      reference: _refController.text.isNotEmpty ? _refController.text : null,
      qthLocator: _qthController.text.trim(),
      comment: _commentController.text.isNotEmpty ? _commentController.text : null,
      startTime: _startTimeUtc,
      endTime: _endTimeUtc,
      waitreport: _waitReport,
    );
    setState(() => _isLoading = false);

    if (id != null) {
      setState(() {
        _createdActivityId = id;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actividad creada exitosamente')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear la actividad')),
        );
      }
    }
  }

  Future<void> _downloadAudio(String type) async {
    if (_createdActivityId == null) return;
    
    setState(() => _isLoading = true);
    final url = apiService.getAudioUrl(_createdActivityId!, type);
    
    final file = await AudioManager.downloadAndSaveAudio(url);
    setState(() => _isLoading = false);
    
    if (file != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio $type descargado exitosamente')),
        );
      }
      widget.onDownloaded();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar el audio $type')),
        );
      }
    }
  }

  Widget _buildUnauthenticated() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_sync, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Conecta tu cuenta para crear actividades', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          _isLoading 
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Ingresar con Google'),
                onPressed: _login,
              )
        ],
      ),
    );
  }

  Widget _buildAuthenticated() {
    if (_isMetadataLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_createdActivityId != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text('Actividad Lista', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Text('Descarga el audio para reproducirlo en la radio:', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar FT8'),
                    onPressed: () => _downloadAudio('ft8'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar CW'),
                    onPressed: () => _downloadAudio('cw'),
                  ),
                ],
              ),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () {
                setState(() {
                  _createdActivityId = null;
                  _freqController.clear();
                  _refController.clear();
                  _commentController.clear();
                });
              },
              child: const Text('Crear Otra Actividad'),
            )
          ],
        ),
      );
    }

    if (!apiService.isProfileComplete) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Perfil Incompleto', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Faltan datos en tu perfil para poder crear actividades (Callsign o QTH Locator).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Por favor, completa tu perfil desde la web de FT8Alert.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Ya lo completé, recargar'),
              onPressed: _login, // force a re-login to fetch new data
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _logout,
              child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
            )
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Nueva Actividad', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Cerrar sesión'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inicio (UTC)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('${_startTimeUtc.year}-${_startTimeUtc.month.toString().padLeft(2, '0')}-${_startTimeUtc.day.toString().padLeft(2, '0')} ${_startTimeUtc.hour.toString().padLeft(2, '0')}:${_startTimeUtc.minute.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.access_time, size: 20),
                  onTap: () => _pickDateTime(true),
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fin (UTC)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('${_endTimeUtc.year}-${_endTimeUtc.month.toString().padLeft(2, '0')}-${_endTimeUtc.day.toString().padLeft(2, '0')} ${_endTimeUtc.hour.toString().padLeft(2, '0')}:${_endTimeUtc.minute.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.access_time, size: 20),
                  onTap: () => _pickDateTime(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: 'Tipo de Actividad', border: OutlineInputBorder()),
            value: _selectedTypeId,
            items: _activityTypes.map<DropdownMenuItem<int>>((t) {
              return DropdownMenuItem<int>(
                value: t['id'],
                child: Text(t['name']),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedTypeId = val),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: 'Modo', border: OutlineInputBorder()),
            value: _selectedModeId,
            items: _modes.map<DropdownMenuItem<int>>((m) {
              return DropdownMenuItem<int>(
                value: m['id'],
                child: Text(m['name']),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedModeId = val),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qthController,
            decoration: InputDecoration(
              labelText: 'QTH Locator (obligatorio)', 
              border: const OutlineInputBorder(),
              suffixIcon: _isCalculatingQth
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: 'Calcular con GPS',
                    onPressed: _calculateQth,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _freqController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Frecuencia MHz (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _refController,
            decoration: const InputDecoration(labelText: 'Referencia (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(labelText: 'Comentario (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Esperar Reporte (MQTT)'),
            subtitle: const Text('Alerta de actividad vía servidor', style: TextStyle(fontSize: 12)),
            value: _waitReport,
            onChanged: (bool value) {
              setState(() {
                _waitReport = value;
              });
            },
          ),
          const SizedBox(height: 24),
          _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : ElevatedButton(
                onPressed: _createActivity,
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Crear Actividad', style: TextStyle(fontSize: 16)),
                ),
              )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return apiService.isAuthenticated ? _buildAuthenticated() : _buildUnauthenticated();
  }
}
