import 'dart:async';
import 'dart:convert';
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

  final TextEditingController _numeroController = TextEditingController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _gradController;
  late final Animation<Color?> _color1;
  late final Animation<Color?> _color2;

  Color corDoEmoji(String sentimento) {
    switch (sentimento) {
      case "Medo":
        return Colors.deepPurple;
      case "Satisfeito":
        return Colors.green;
      case "Fome":
        return Colors.orange;
      case "Relaxado":
        return Colors.blue;
      case "Triste":
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  final Map<String, int> _contadores = {
    "Medo": 0,
    "Satisfeito": 0,
    "Fome": 0,
    "Relaxado": 0,
    "Triste": 0,
  };

  Timer? _resumoTimer;

  final String _apiUrl =
      'https://app.meuclickonline.com.br/rest.php?class=EmpresaRestService&method=enviaMensagemTextoZap';

  final String _authHeader =
      'Basic_1927b11f4d4186c2f92d04a25956a41ed5c93909b350560e31b8b5719b43';

  String get _numero => _numeroController.text.trim();
  final String _empresaId = "1";

  @override
  void initState() {
    super.initState();

    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _gradController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat(reverse: true);

    _color1 =
        ColorTween(begin: Colors.purple.shade200, end: Colors.blue.shade200)
            .animate(_gradController);
    _color2 =
        ColorTween(begin: Colors.orange.shade200, end: Colors.pink.shade200)
            .animate(_gradController);

    _resumoTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _enviarResumoSeNecessario();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gradController.dispose();
    _resumoTimer?.cancel();
    _numeroController.dispose();
    super.dispose();
  }

  Future<void> trocarEmoji(String novoEmoji, String sentimento) async {
    setState(() {
      emojiAtual = novoEmoji;
      sentimentoAtual = sentimento;
      _contadores[sentimento] = (_contadores[sentimento] ?? 0) + 1;
    });

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 150);
    }

    NotificacaoService.enviarNotificacao(
      titulo: "Estado do Filho",
      corpo: "Ele está: $sentimento",
    );

    if ((_contadores[sentimento] ?? 0) >= 10) {
      await _enviarResumo(disparoPorLimite: true);
    }
  }

  Future<void> _enviarResumoSeNecessario() async {
    final total = _contadores.values.fold(0, (a, b) => a + b);

    if (total > 0) {
      await _enviarResumo(disparoPorLimite: false);
    }
  }

  Future<void> _enviarResumo({required bool disparoPorLimite}) async {
    try {
      if (_numero.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Digite um número de WhatsApp antes de enviar."),
          ),
        );
        return;
      }

      String predominante = "Neutro";
      int maior = 0;

      _contadores.forEach((k, v) {
        if (v > maior) {
          maior = v;
          predominante = k;
        }
      });

      final mensagemPredominante = _mensagemParaPai(predominante, maior);

      final mensagemFinal = StringBuffer();
      mensagemFinal.writeln(mensagemPredominante);

      if (disparoPorLimite) {
        mensagemFinal.writeln(
            "\nObs.: Relatório enviado automaticamente após 10 registros.");
      } else {
        mensagemFinal
            .writeln("Relatório enviado automaticamente a cada 30 minutos.");
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

      final resp =
          await http.post(Uri.parse(_apiUrl), headers: headers, body: body);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        NotificacaoService.enviarNotificacao(
            titulo: "Resumo enviado",
            corpo: "Resumo do estado do seu filho foi enviado.");
      }
    } catch (e) {
      debugPrint("Erro ao enviar resumo: $e");
    } finally {
      _resetContadores();
    }
  }

  String _mensagemParaPai(String sentimento, int vezes) {
    switch (sentimento) {
      case "Medo":
        return "Seu filho demonstrou medo $vezes vezes.";
      case "Satisfeito":
        return "Seu filho se mostrou feliz/satisfeito $vezes vezes.";
      case "Com Fome":
        return "Ele mostrou sinais de fome $vezes vezes.";
      case "Relaxado":
        return "Ele ficou relaxado $vezes vezes.";
      case "Triste":
        return "Ele ficou triste $vezes vezes.";
      default:
        return "Nenhum sentimento predominante.";
    }
  }

  void _resetContadores() {
    _contadores.updateAll((key, value) => 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradController,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_color1.value!, _color2.value!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Campo WhatsApp
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: _numeroController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: "Número do WhatsApp (DDD + número)",
                            hintText: "Exemplo: 92991677048",
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Emoji central
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(50),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: corDoEmoji(sentimentoAtual).withOpacity(0.2),
                          ),
                          child: Text(
                            emojiAtual,
                            style: const TextStyle(fontSize: 80),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Contadores de emoções
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _contadores.entries.map((e) {
                            return Chip(
                              label: Text("${e.key}: ${e.value}"),
                              backgroundColor: corDoEmoji(e.key).withOpacity(0.2),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Botões
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          _botaoResponsivo("Medo", "😨"),
                          _botaoResponsivo("Satisfeito", "😄"),
                          _botaoResponsivo("Fome", "😋"),
                          _botaoResponsivo("Relaxado", "😌"),
                          _botaoResponsivo("Triste", "😢"),
                        ],
                      ),
                      const SizedBox(height: 30),

                      ElevatedButton.icon(
                        onPressed: _enviarResumoSeNecessario,
                        icon: const Icon(Icons.send),
                        label: const Text("Enviar resumo agora"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
          backgroundColor: corDoEmoji(sentimento), // cor do botão
          foregroundColor: Colors.white,           // garante texto branco
          shadowColor: Colors.transparent,         // tira sombra se aparecer
          side: BorderSide.none,                   // tira borda branca
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(width: 8),
            Text(
              sentimento,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================
// NOTIFICAÇÕES
// =========================================

class NotificacaoService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future inicializar() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'sentimentos_channel',
      'Notificações de Emoções',
      description: 'Canal para notificações do app',
      importance: Importance.high,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    androidImpl?.createNotificationChannel(channel);
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
