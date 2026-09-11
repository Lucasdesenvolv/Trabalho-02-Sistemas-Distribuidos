import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../services/socket_service.dart';

/// Largura máxima e qualidade JPEG exigidas pelo protocolo combinado com o servidor.
const int kMaxImageWidth = 1280;
const int kJpegQuality = 80;

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  final SocketService _socketService = SocketService();

  String _ip = '192.168.0.100';
  int _port = 5000;

  bool _processando = false;
  String? _resultadoTexto;
  List<String> _objetosDetectados = [];
  Uint8List? _ultimaFotoBytes;

  @override
  void initState() {
    super.initState();
    _iniciarCamera();
  }

  Future<void> _iniciarCamera() async {
    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras.first;
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await controller.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Redimensiona (largura máx. 1280px) e recodifica em JPEG qualidade ~80.
  Uint8List _prepararImagem(Uint8List original) {
    final decoded = img.decodeImage(original);
    if (decoded == null) return original;

    img.Image resized = decoded;
    if (decoded.width > kMaxImageWidth) {
      resized = img.copyResize(decoded, width: kMaxImageWidth);
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: kJpegQuality));
  }

  Future<void> _tirarEAnalisar() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processando) {
      return;
    }

    setState(() {
      _processando = true;
      _resultadoTexto = null;
      _objetosDetectados = [];
    });

    try {
      final XFile foto = await controller.takePicture();
      final bytesOriginais = await foto.readAsBytes();
      final bytesPreparados = _prepararImagem(bytesOriginais);

      final resposta = await _socketService.sendImage(
        ip: _ip,
        port: _port,
        imageBytes: bytesPreparados,
      );

      setState(() {
        _ultimaFotoBytes = bytesPreparados;
        _resultadoTexto = resposta;
        _objetosDetectados = (resposta.trim().toLowerCase() == 'nada detectado')
            ? []
            : resposta.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      });
    } catch (e) {
      setState(() {
        _resultadoTexto = 'Erro: $e';
        _objetosDetectados = [];
      });
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirConfiguracoes() async {
    final ipController = TextEditingController(text: _ip);
    final portController = TextEditingController(text: _port.toString());

    final salvou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar servidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(labelText: 'IP do servidor'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: portController,
              decoration: const InputDecoration(labelText: 'Porta'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (salvou == true) {
      setState(() {
        _ip = ipController.text.trim();
        _port = int.tryParse(portController.text.trim()) ?? _port;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detector de Objetos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _abrirConfiguracoes,
            tooltip: 'Configurar IP/Porta',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Servidor: $_ip:$_port', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: (controller != null && controller.value.isInitialized)
                ? CameraPreview(controller)
                : const Center(child: CircularProgressIndicator()),
          ),
          _buildResultado(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _processando ? null : _tirarEAnalisar,
                icon: _processando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(_processando ? 'Analisando...' : 'Tirar e Analisar'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultado() {
    if (_resultadoTexto == null) return const SizedBox.shrink();

    final semDeteccao = _objetosDetectados.isEmpty && !_resultadoTexto!.startsWith('Erro');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _resultadoTexto!.startsWith('Erro')
            ? Colors.red.shade50
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _resultadoTexto!.startsWith('Erro') ? Colors.red : Colors.green,
        ),
      ),
      child: semDeteccao
          ? const Text('Nada Detectado', style: TextStyle(fontWeight: FontWeight.bold))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _resultadoTexto!.startsWith('Erro')
                  ? [Text(_resultadoTexto!)]
                  : _objetosDetectados
                      .map((obj) => Text(
                            '${_capitalizar(obj)} detectada(o)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ))
                      .toList(),
            ),
    );
  }

  String _capitalizar(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
