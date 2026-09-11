import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Serviço responsável por enviar a foto ao servidor Python via socket TCP
/// e ler a resposta com os objetos detectados.
///
/// Protocolo (mesmo usado pelo servidor):
///   [4 bytes big-endian: tamanho do payload] + [payload]
class SocketService {
  /// Envia [imageBytes] (JPEG) para [ip]:[port] e retorna a string de resposta
  /// do servidor (ex.: "pessoa, cadeira" ou "Nada Detectado").
  Future<String> sendImage({
    required String ip,
    required int port,
    required Uint8List imageBytes,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);

      // Cabeçalho: tamanho da imagem em 4 bytes big-endian
      final header = ByteData(4)..setUint32(0, imageBytes.length, Endian.big);
      socket.add(header.buffer.asUint8List());
      // Corpo: bytes da imagem JPEG
      socket.add(imageBytes);
      await socket.flush();

      final resposta = await _lerResposta(socket).timeout(timeout);
      return resposta;
    } on TimeoutException {
      throw Exception('Tempo esgotado aguardando o servidor ($ip:$port).');
    } on SocketException catch (e) {
      throw Exception('Não foi possível conectar ao servidor $ip:$port. (${e.message})');
    } finally {
      await socket?.close();
    }
  }

  /// Lê a resposta do servidor seguindo o protocolo: 4 bytes de tamanho + payload UTF-8.
  Future<String> _lerResposta(Socket socket) async {
    final buffer = BytesBuilder();
    int? tamanhoEsperado;

    await for (final chunk in socket) {
      buffer.add(chunk);

      if (tamanhoEsperado == null && buffer.length >= 4) {
        final bytes = buffer.toBytes();
        tamanhoEsperado = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      }

      if (tamanhoEsperado != null) {
        final total = buffer.toBytes();
        if (total.length >= 4 + tamanhoEsperado) {
          final payload = total.sublist(4, 4 + tamanhoEsperado);
          return String.fromCharCodes(payload);
        }
      }
    }

    throw Exception('Conexão encerrada antes de receber a resposta completa.');
  }
}
