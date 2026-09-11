# Atividade 2 — Foto via Botão (Android → Servidor Python por Sockets)

App Flutter que tira uma foto e a envia via **socket TCP** para um servidor
**Python**, que detecta objetos na imagem usando **OpenCV** + **YOLO** e
retorna o resultado ao app.

```
projeto/
├── server/                  # Servidor Python
│   ├── server.py
│   └── requirements.txt
└── app/                      # App Flutter (Dart)
    ├── pubspec.yaml
    ├── android_manifest_snippet.xml
    └── lib/
        ├── main.dart
        ├── screens/home_screen.dart
        └── services/socket_service.dart
```

## Protocolo de comunicação

Simples e simétrico nos dois sentidos, via socket TCP:

```
[4 bytes big-endian: tamanho do payload] + [payload]
```

- **App → Servidor**: payload = bytes da imagem **JPEG** (qualidade ~80,
  largura máx. 1280px).
- **Servidor → App**: payload = string UTF-8 com os objetos detectados
  separados por vírgula (ex.: `"person, chair"`) ou `"Nada Detectado"`.

## Como rodar o servidor (Python)

1. Instale as dependências:
   ```bash
   cd server
   pip install -r requirements.txt
   ```
2. Rode o servidor:
   ```bash
   python server.py
   # ou especificando porta/modelo:
   python server.py --port 5000 --model yolo11n.pt
   ```
   O modelo `yolo11n.pt` (ou `yolov8n.pt`) é baixado automaticamente pela
   biblioteca `ultralytics` na primeira execução.
3. O servidor mostrará `Aguardando imagem...` e depois
   `Servidor escutando em 0.0.0.0:5000`. Cada foto recebida é salva em
   `server/capturas/foto_<timestamp>.jpg` e o resultado é impresso no console.

## Como rodar o app (Flutter)

O app foi escrito como arquivos-fonte Dart prontos para colar em um projeto
Flutter novo (não incluímos os arquivos nativos gerados automaticamente do
Android/iOS, pois são gerados pelo próprio `flutter create`):

1. Crie um projeto Flutter novo:
   ```bash
   flutter create photo_detector_app
   cd photo_detector_app
   ```
2. Copie o conteúdo de `app/lib/` para dentro do `lib/` do projeto criado,
   substituindo o `main.dart` padrão.
3. Copie as dependências de `app/pubspec.yaml` (seção `dependencies`) para o
   `pubspec.yaml` do projeto criado, e rode:
   ```bash
   flutter pub get
   ```
4. Adicione as permissões do Android — veja `app/android_manifest_snippet.xml`
   para o trecho exato a inserir em
   `android/app/src/main/AndroidManifest.xml` (permissão de câmera, internet
   e `usesCleartextTraffic="true"`, necessário pois o socket não usa TLS).
5. Conecte um celular/emulador Android e rode:
   ```bash
   flutter run
   ```

## Como configurar o IP e a porta

No app, toque no ícone de **engrenagem** (⚙) no canto superior direito para
abrir o diálogo de configuração e informar o **IP** e a **porta** do
computador onde o `server.py` está rodando.

> ⚠️ O celular e o computador precisam estar na **mesma rede Wi-Fi**. Para
> descobrir o IP do computador: `ipconfig` (Windows) ou `ifconfig` /
> `ip a` (Linux/Mac). Use a porta configurada no servidor (padrão: `5000`).

## Roteiro de uso

1. Inicie o servidor Python (`Aguardando imagem...`).
2. No app, configure IP/porta (⚙) e toque em **"Tirar e Analisar"**.
3. O app captura a foto, redimensiona (máx. 1280px) e comprime em JPEG
   (qualidade ~80), e envia via socket TCP.
4. O servidor recebe, detecta os objetos com YOLO e salva a imagem com
   timestamp em `server/capturas/`.
5. O servidor retorna a lista de objetos identificados.
6. O app exibe o resultado, ex.:
   - **Pessoa detectada**
   - **Cadeira detectada**
   - **Mochila detectada**
   - Ou **"Nada Detectado"**, se nenhum objeto for identificado.
7. Nova foto → nova análise, resultado atualizado no app.

## Modelo utilizado

- **YOLO11n** (`yolo11n.pt`) via biblioteca `ultralytics`, com fallback fácil
  para **YOLOv8n** (`yolov8n.pt`) — basta passar `--model yolov8n.pt` ao
  iniciar o servidor. Ambos são modelos "nano", leves e rápidos, adequados
  para inferência em tempo quase real em CPU.
- Detecção rodada com OpenCV (`cv2`) para leitura/decodificação/gravação das
  imagens.


