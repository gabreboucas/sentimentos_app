import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificacaoService.inicializar();
  runApp(const EmojisApp());
}

class EmojisApp extends StatelessWidget {
  const EmojisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Emoções do Filho",
      home: const EmojiHomePage(),
    );
  }
}

class EmojiHomePage extends StatefulWidget {
  const EmojiHomePage({super.key});

  @override
  State<EmojiHomePage> createState() => _EmojiHomePageState();
}

class _EmojiHomePageState extends State<EmojiHomePage>
    with TickerProviderStateMixin {
  String emojiAtual = "🙂";
  String sentimentoAtual = "Neutro";

  // Pulsar contínuo do emoji
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Gradiente animado
  late final AnimationController _gradController;
  late final Animation<Color?> _color1;
  late final Animation<Color?> _color2;
Color corDoEmoji(String sentimento) {
  switch (sentimento) {
    case "Medo":
      return Colors.deepPurple;
    case "Satisfeito":
      return Colors.green;
    case "Com Fome":
      return Colors.orange;
    case "Relaxado":
      return Colors.blue;
    case "Triste":
      return Colors.indigo;
    default:
      return Colors.grey;
  }
}

  // Contadores por sentimento
  final Map<String, int> _contadores = {
    "Medo": 0,
    "Satisfeito": 0,
    "Com Fome": 0,
    "Relaxado": 0,
    "Triste": 0,
  };

  // Timer para enviar resumo a cada 30 minutos
  Timer? _resumoTimer;

  // Configuração da API (coloque aqui se quiser externalizar)
  final String _apiUrl =
      'https://app.meuclickonline.com.br/rest.php?class=EmpresaRestService&method=enviaMensagemTextoZap';
  final String _authHeader =
      'Basic_1927b11f4d4186c2f92d04a25956a41ed5c93909b350560e31b8b5719b43';
  final String _numero = "9285515439";
  final String _empresaId = "1";

  @override
  void initState() {
    super.initState();

    // Pulsar contínuo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Gradiente
    _gradController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat(reverse: true);
    _color1 = ColorTween(begin: Colors.purple.shade200, end: Colors.blue.shade200)
        .animate(_gradController);
    _color2 = ColorTween(begin: Colors.orange.shade200, end: Colors.pink.shade200)
        .animate(_gradController);

    // Inicializa o timer de resumo: 30 minutos
    // Para testes locais você pode usar Duration(minutes: 1)
    _resumoTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _enviarResumoSeNecessario();
    });

    // Opcional: também iniciar envio imediato no startup se quiser
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gradController.dispose();
    _resumoTimer?.cancel();
    super.dispose();
  }

  // Função ao clicar no botão de sentimento
  Future<void> trocarEmoji(String novoEmoji, String sentimento) async {
    setState(() {
      emojiAtual = novoEmoji;
      sentimentoAtual = sentimento;
      _contadores[sentimento] = (_contadores[sentimento] ?? 0) + 1;
    });

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 150);
    }

    // Notificação local simples
    NotificacaoService.enviarNotificacao(
      titulo: "Estado do Filho",
      corpo: "Ele está: $sentimento",
    );

    // Se este sentimento foi pressionado 10x ou mais, envia resumo imediatamente e reseta
    if ((_contadores[sentimento] ?? 0) >= 10) {
      await _enviarResumo(disparoPorLimite: true);
    }
  }

  // Decide se há algo a enviar: se houver contagens > 0
  Future<void> _enviarResumoSeNecessario() async {
    final totalClicks = _contadores.values.fold<int>(0, (a, b) => a + b);
    if (totalClicks > 0) {
      await _enviarResumo(disparoPorLimite: false);
    } else {
      // nada para enviar
      debugPrint("Resumo: nada para enviar (contadores zerados).");
    }
  }

  // Envia resumo por POST para API
  Future<void> _enviarResumo({required bool disparoPorLimite}) async {
    try {
      // calcula o sentimento predominante
      String predominante = "Neutro";
      int maior = 0;
      _contadores.forEach((k, v) {
        if (v > maior) {
          maior = v;
          predominante = k;
        }
      });

      // monta o corpo com contagem por sentimento
      final resumoPartes = _contadores.entries
          .map((e) => "${e.key}: ${e.value}x")
          .toList(growable: false);
      final resumoCounts = resumoPartes.join(", ");

      // mensagem amigável e bonita para o pai
      final mensagemPredominante = _mensagemParaPai(predominante, maior);

      final mensagemFinal = StringBuffer();
      mensagemFinal.writeln(mensagemPredominante);
      if (disparoPorLimite) {
        mensagemFinal.writeln("");
        mensagemFinal.writeln(
            "Obs.: Este relatório foi enviado automaticamente porque uma emoção foi registrada 10 vezes.");
      } else {
        mensagemFinal.writeln(
            "Este relatório foi enviado a cada 30 minutos conforme combinado.");
      }

      final body = jsonEncode({
        "mensagem": mensagemFinal.toString(),
        "numero": _numero,
        "empresa_id": _empresaId,
      });

      final headers = {
        "Content-Type": "application/json",
        "Authorization": _authHeader,
      };

      debugPrint("Enviando resumo: $body");

      final resp = await http.post(Uri.parse(_apiUrl), headers: headers, body: body);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // sucesso
        debugPrint("Resumo enviado com sucesso: ${resp.statusCode}");
        // notificar localmente que envio ocorreu
        NotificacaoService.enviarNotificacao(
            titulo: "Resumo enviado", corpo: "Resumo do estado do seu filho foi enviado.");
      } else {
        debugPrint(
            "Falha ao enviar resumo. status=${resp.statusCode}, body=${resp.body}");
        // opcional: notificar erro
        NotificacaoService.enviarNotificacao(
            titulo: "Erro ao enviar resumo",
            corpo: "Não foi possível enviar o resumo (erro ${resp.statusCode}).");
      }
    } catch (e, st) {
      debugPrint("Erro ao enviar resumo: $e\n$st");
      NotificacaoService.enviarNotificacao(
          titulo: "Erro ao enviar resumo", corpo: "Ocorreu um erro ao enviar o resumo.");
    } finally {
      // sempre resetar contadores após tentativa de envio (pedido)
      _resetContadores();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resumo enviado e contadores resetados.')),
        );
      }
    }
  }

  // Mensagens "bonitinhas" dependendo do sentimento predominante
  String _mensagemParaPai(String sentimento, int vezes) {
    switch (sentimento) {
      case "Medo":
        return "Seu filho parece estar com medo com mais frequência ($vezes vezes). Fique atento a sinais de insegurança e ofereça conforto e segurança.";
      case "Satisfeito":
        return "Seu filho parece estar feliz e satisfeito ($vezes vezes). Ótimo! Continue com as rotinas que o deixam bem.";
      case "Com Fome":
        return "Seu filho apresentou sinais de fome ($vezes vezes). Talvez seja um bom momento para oferecer um lanchinho nutritivo.";
      case "Relaxado":
        return "Seu filho está calmo e relaxado ($vezes vezes). Excelente — parece estar confortável e tranquilo.";
      case "Triste":
        return "Seu filho apresentou tristeza ($vezes vezes). Observe se há um padrão e ofereça atenção e acolhimento.";
      default:
        return "Não houve um sentimento predominante claro.";
    }
  }

  void _resetContadores() {
    _contadores.updateAll((key, value) => 0);
  }

  // UI responsiva
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradController,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final isPortrait = height > width;

              // responsive sizes
              final emojiSize = (isPortrait ? height : width) * 0.18;
              final circlePadding = emojiSize * 0.4;

              return Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_color1.value!, _color2.value!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            "Como seu filho está agora",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            padding: EdgeInsets.all(circlePadding),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      corDoEmoji(sentimentoAtual).withOpacity(0.45),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                              color: corDoEmoji(sentimentoAtual).withOpacity(0.18),
                            ),
                            child: Text(
                              emojiAtual,
                              style: TextStyle(fontSize: emojiSize),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            sentimentoAtual,
                            style: TextStyle(
                              fontSize: isPortrait ? 20 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        // Mostrar contadores rapidamente (opcional)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: _contadores.entries.map((e) {
                              return Chip(
                                label: Text("${e.key}: ${e.value}"),
                                backgroundColor:
                                    corDoEmoji(e.key).withOpacity(0.2),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // botões responsivos
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              _botaoResponsivo("Medo", "😨"),
                              _botaoResponsivo("Satisfeito", "😄"),
                              _botaoResponsivo("Com Fome", "😋"),
                              _botaoResponsivo("Relaxado", "😌"),
                              _botaoResponsivo("Triste", "😢"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // botão manual: enviar resumo agora (útil para teste)
                        ElevatedButton.icon(
                          onPressed: _enviarResumoSeNecessario,
                          icon: const Icon(Icons.send),
                          label: const Text("Enviar resumo agora"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _botaoResponsivo(String sentimento, String emoji) {
    return SizedBox(
      width: 150,
      child: ElevatedButton(
        onPressed: () => trocarEmoji(emoji, sentimento),
        style: ElevatedButton.styleFrom(
          backgroundColor: corDoEmoji(sentimento),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                sentimento,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================
// SERVIÇO DE NOTIFICAÇÃO LOCAL
// =========================================
class NotificacaoService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future inicializar() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

    // Cria canal obrigatório no Android 8+
    const androidChannel = AndroidNotificationChannel(
      'sentimentos_channel',
      'Notificações de Emoções',
      description: 'Canal para notificações de sentimentos do filho',
      importance: Importance.high,
    );

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(androidChannel);
    }
  }

  static Future enviarNotificacao({
    required String titulo,
    required String corpo,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'sentimentos_channel',
      'Notificações de Emoções',
      importance: Importance.high,
      priority: Priority.high,
    );

    const geral = NotificationDetails(android: androidDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      titulo,
      corpo,
      geral,
    );
  }
}