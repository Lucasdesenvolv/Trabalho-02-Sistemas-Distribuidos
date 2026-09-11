"""
Servidor Python - Detecção de Objetos via Socket TCP
=====================================================

Recebe fotos de um app Android (Flutter) via socket TCP, roda um modelo
YOLO (Ultralytics) para detectar objetos e devolve o resultado ao app.

Protocolo de comunicação (simples, simétrico nos dois sentidos):
    [4 bytes big-endian: tamanho do payload] + [payload]

    Cliente -> Servidor: payload = bytes da imagem JPEG
    Servidor -> Cliente: payload = string UTF-8 com os objetos detectados
                         (separados por vírgula) ou "Nada Detectado"

Uso:
    python server.py
    python server.py --port 5000 --model yolo11n.pt
"""

import argparse
import os
import socket
import struct
import threading
import time

import cv2
import numpy as np
from ultralytics import YOLO

SAVE_DIR = "capturas"

# Tradução das 80 classes do dataset COCO (usado pelo YOLO) para português.
TRADUCAO_CLASSES = {
    "person": "pessoa", "bicycle": "bicicleta", "car": "carro", "motorcycle": "moto",
    "airplane": "avião", "bus": "ônibus", "train": "trem", "truck": "caminhão",
    "boat": "barco", "traffic light": "semáforo", "fire hydrant": "hidrante",
    "stop sign": "placa de pare", "parking meter": "parquímetro", "bench": "banco",
    "bird": "pássaro", "cat": "gato", "dog": "cachorro", "horse": "cavalo",
    "sheep": "ovelha", "cow": "vaca", "elephant": "elefante", "bear": "urso",
    "zebra": "zebra", "giraffe": "girafa", "backpack": "mochila", "umbrella": "guarda-chuva",
    "handbag": "bolsa", "tie": "gravata", "suitcase": "mala", "frisbee": "frisbee",
    "skis": "esqui", "snowboard": "snowboard", "sports ball": "bola",
    "kite": "pipa", "baseball bat": "taco de beisebol", "baseball glove": "luva de beisebol",
    "skateboard": "skate", "surfboard": "prancha de surfe", "tennis racket": "raquete de tênis",
    "bottle": "garrafa", "wine glass": "taça de vinho", "cup": "xícara", "fork": "garfo",
    "knife": "faca", "spoon": "colher", "bowl": "tigela", "banana": "banana",
    "apple": "maçã", "sandwich": "sanduíche", "orange": "laranja", "broccoli": "brócolis",
    "carrot": "cenoura", "hot dog": "cachorro-quente", "pizza": "pizza", "donut": "rosquinha",
    "cake": "bolo", "chair": "cadeira", "couch": "sofá", "potted plant": "planta em vaso",
    "bed": "cama", "dining table": "mesa de jantar", "toilet": "vaso sanitário",
    "tv": "televisão", "laptop": "notebook", "mouse": "mouse", "remote": "controle remoto",
    "keyboard": "teclado", "cell phone": "celular", "microwave": "micro-ondas",
    "oven": "forno", "toaster": "torradeira", "sink": "pia", "refrigerator": "geladeira",
    "book": "livro", "clock": "relógio", "vase": "vaso", "scissors": "tesoura",
    "teddy bear": "urso de pelúcia", "hair drier": "secador de cabelo",
    "toothbrush": "escova de dente",
}


def traduzir(nome_ingles: str) -> str:
    """Traduz o nome da classe (inglês, dataset COCO) para português."""
    return TRADUCAO_CLASSES.get(nome_ingles, nome_ingles)


def recv_exact(conn: socket.socket, n: int) -> bytes:
    """Lê exatamente n bytes do socket (recv pode devolver menos que o pedido)."""
    data = bytearray()
    while len(data) < n:
        packet = conn.recv(n - len(data))
        if not packet:
            raise ConnectionError(
                "Conexão encerrada pelo cliente durante a leitura")
        data.extend(packet)
    return bytes(data)


def detectar_objetos(model: YOLO, img: np.ndarray) -> list[str]:
    """Roda o modelo YOLO na imagem e retorna a lista (sem repetição) de classes
    detectadas, já traduzidas para português."""
    results = model(img, verbose=False)
    classes_detectadas = set()
    for r in results:
        for box in r.boxes:
            cls_id = int(box.cls[0])
            nome_ingles = model.names[cls_id]
            classes_detectadas.add(traduzir(nome_ingles))
    return sorted(classes_detectadas)


def handle_client(conn: socket.socket, addr, model: YOLO):
    print(f"[+] Conexão de {addr}")
    try:
        while True:
            # 1) Lê o cabeçalho de 4 bytes com o tamanho da imagem
            raw_len = conn.recv(4)
            if not raw_len:
                break  # cliente fechou a conexão normalmente
            if len(raw_len) < 4:
                raw_len += recv_exact(conn, 4 - len(raw_len))

            img_len = struct.unpack(">I", raw_len)[0]
            # sanity check (máx 50MB)
            if img_len == 0 or img_len > 50 * 1024 * 1024:
                raise ValueError(f"Tamanho de imagem inválido: {img_len}")

            # 2) Lê os bytes da imagem
            img_bytes = recv_exact(conn, img_len)

            # 3) Decodifica a imagem (JPEG -> matriz OpenCV)
            np_arr = np.frombuffer(img_bytes, dtype=np.uint8)
            img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if img is None:
                resposta = "Erro ao decodificar imagem"
            else:
                # 4) Salva a imagem recebida com timestamp
                os.makedirs(SAVE_DIR, exist_ok=True)
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                filepath = os.path.join(SAVE_DIR, f"foto_{timestamp}.jpg")
                cv2.imwrite(filepath, img)

                # 5) Roda a detecção de objetos
                objetos = detectar_objetos(model, img)
                resposta = ", ".join(objetos) if objetos else "Nada Detectado"
                print(f"    [{addr}] {resposta}  (salvo em {filepath})")

            # 6) Envia a resposta de volta: 4 bytes de tamanho + texto UTF-8
            resp_bytes = resposta.encode("utf-8")
            conn.sendall(struct.pack(">I", len(resp_bytes)) + resp_bytes)

    except (ConnectionError, ConnectionResetError, ValueError) as e:
        print(f"[-] Conexão com {addr} encerrada: {e}")
    finally:
        conn.close()
        print(f"[-] Conexão fechada: {addr}")


def main():
    parser = argparse.ArgumentParser(
        description="Servidor de detecção de objetos via socket TCP")
    parser.add_argument("--host", default="0.0.0.0",
                        help="Endereço de escuta (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=5000,
                        help="Porta de escuta (default: 5000)")
    parser.add_argument(
        "--model", default="yolo11n.pt",
        help="Caminho/nome do modelo YOLO (default: yolo11n.pt, baixado automaticamente)"
    )
    args = parser.parse_args()

    print("Aguardando imagem...")
    print(f"Carregando modelo '{args.model}'...")
    model = YOLO(args.model)
    print("Modelo carregado.")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(5)
    print(
        f"Servidor escutando em {args.host}:{args.port}  (Ctrl+C para encerrar)")

    try:
        while True:
            conn, addr = server.accept()
            t = threading.Thread(target=handle_client, args=(
                conn, addr, model), daemon=True)
            t.start()
    except KeyboardInterrupt:
        print("\nEncerrando servidor...")
    finally:
        server.close()


if __name__ == "__main__":
    main()
