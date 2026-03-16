import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:math';

// AppColors визначені в main.dart
class AppColors {
  static const Color bg = Color(0xFF091630);
  static const Color bgCard = Color(0xFF0D1B2A);
  static const Color textPri = Color(0xFFE8EBF0);
  static const Color textSec = Color(0xFF94A3B8);
  static const Color textHint = Color(0xFF475569);
  static const Color uaBlue = Color(0xFF0057B7);
  static const Color uaYellow = Color(0xFFFFD700);
  static const Color accent = Color(0xFF38BDF8);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color border = Color(0xFF1E293B);
}

class MagnetoScreen extends StatefulWidget {
  final Function(String) onLog;
  const MagnetoScreen({super.key, required this.onLog});

  @override
  State<MagnetoScreen> createState() => _MagnetoScreenState();
}

class _MagnetoScreenState extends State<MagnetoScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<MagnetometerEvent>? _sub;
  late AnimationController _pulseAnim;

  // Поточні значення
  double x = 0, y = 0, z = 0;
  double magnitude = 0;
  double anomaly = 0;

  // Калібрування
  double baseline = 50.0;
  bool isCalibrating = false;
  bool isScanning = false;

  // Історія для графіка
  List<double> history = [];
  double maxRecorded = 0;

  // Поріг тривоги
  double threshold = 15.0;

  // Звук
  Timer? _beepTimer;
  int _beepInterval = 1000;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startListening();
  }

  void _startListening() {
    _sub = magnetometerEventStream().listen((MagnetometerEvent event) {
      setState(() {
        x = event.x;
        y = event.y;
        z = event.z;

        magnitude = sqrt(x * x + y * y + z * z);
        anomaly = (magnitude - baseline).abs();

        if (isScanning) {
          history.add(anomaly);
          if (history.length > 100) history.removeAt(0);

          if (anomaly > maxRecorded) {
            maxRecorded = anomaly;
          }

          if (anomaly > threshold) {
            HapticFeedback.mediumImpact();
            _updateBeepInterval();
          }
        }
      });
    });
  }

  void _updateBeepInterval() {
    int newInterval = (1000 / (1 + anomaly / 10)).round().clamp(100, 1000);
    if (newInterval != _beepInterval) {
      _beepInterval = newInterval;
      _restartBeep();
    }
  }

  void _restartBeep() {
    _beepTimer?.cancel();
    if (isScanning && anomaly > threshold) {
      _beepTimer = Timer.periodic(Duration(milliseconds: _beepInterval), (_) {
        if (anomaly > threshold) {
          HapticFeedback.lightImpact();
        }
      });
    }
  }

  Future<void> _calibrate() async {
    setState(() {
      isCalibrating = true;
      isScanning = false;
    });

    _beepTimer?.cancel();

    List<double> samples = [];

    int count = 0;
    await for (var event in magnetometerEventStream()) {
      if (count >= 100) break;

      double mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      samples.add(mag);

      setState(() {
        magnitude = mag;
      });

      await Future.delayed(const Duration(milliseconds: 20));
      count++;
    }

    samples.sort();
    baseline = samples[samples.length ~/ 2];

    setState(() {
      isCalibrating = false;
      history.clear();
      maxRecorded = 0;
    });

    widget.onLog('Магнітометр: калібровано на ${baseline.toStringAsFixed(1)} µT');
  }

  void _toggleScanning() {
    setState(() {
      isScanning = !isScanning;
      if (!isScanning) {
        _beepTimer?.cancel();
      } else {
        history.clear();
        maxRecorded = 0;
      }
    });

    widget.onLog(isScanning ? 'Сканування розпочато' : 'Сканування зупинено');
  }

  void _resetMax() {
    setState(() {
      maxRecorded = 0;
      history.clear();
    });
  }

  Color _getAnomalyColor() {
    if (anomaly < threshold * 0.5) return Colors.green;
    if (anomaly < threshold) return Colors.yellow;
    if (anomaly < threshold * 1.5) return Colors.orange;
    return Colors.red;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseAnim.dispose();
    _beepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('МАГНІТОМЕТР'),
        backgroundColor: AppColors.bgCard,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isCalibrating)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.uaBlue,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('КАЛІБРУВАННЯ...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildRadar(),
                  const SizedBox(height: 24),
                  _buildMetrics(),
                  const SizedBox(height: 24),
                  if (history.isNotEmpty) _buildHistoryChart(),
                  const SizedBox(height: 24),
                  _buildRawData(),
                  const SizedBox(height: 24),
                  _buildThresholdControl(),
                ],
              ),
            ),
          ),

          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildRadar() {
    final color = _getAnomalyColor();
    final isAlert = anomaly > threshold;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(
              color: isAlert ? color.withOpacity(0.6 + _pulseAnim.value * 0.4) : AppColors.border,
              width: isAlert ? 3 : 2,
            ),
            boxShadow: isAlert
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.3 + _pulseAnim.value * 0.3),
                      blurRadius: 20 + _pulseAnim.value * 20,
                      spreadRadius: 5,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                final radius = 40.0 + i * 40;
                return Container(
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withOpacity(0.1), width: 1),
                  ),
                );
              }),

              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.3),
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        anomaly.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        'µT',
                        style: TextStyle(
                          fontSize: 10,
                          color: color.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (isScanning)
                Transform.rotate(
                  angle: _pulseAnim.value * 2 * pi,
                  child: Container(
                    width: 2,
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.green.withOpacity(0),
                          Colors.green.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetrics() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _metricRow('АМПЛІТУДА', '${magnitude.toStringAsFixed(1)} µT', AppColors.uaYellow),
          const Divider(color: AppColors.border, height: 24),
          _metricRow('АНОМАЛІЯ', '${anomaly.toStringAsFixed(1)} µT', _getAnomalyColor()),
          const Divider(color: AppColors.border, height: 24),
          _metricRow('МАКСИМУМ', '${maxRecorded.toStringAsFixed(1)} µT', AppColors.accent),
          const Divider(color: AppColors.border, height: 24),
          _metricRow('БАЗОВА ЛІНІЯ', '${baseline.toStringAsFixed(1)} µT', AppColors.textSec),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSec,
            letterSpacing: 0.8,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryChart() {
    final maxVal = history.reduce(max);
    final scale = maxVal > 0 ? 80 / maxVal : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ІСТОРІЯ АНОМАЛІЙ',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSec,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: _HistoryChartPainter(history, threshold, scale),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawData() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'СИРІ ДАНІ (µT)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSec,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _rawDataColumn('X', x, Colors.red),
              _rawDataColumn('Y', y, Colors.green),
              _rawDataColumn('Z', z, Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rawDataColumn(String axis, double value, Color color) {
    return Column(
      children: [
        Text(
          axis,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.7),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdControl() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ПОРІГ ТРИВОГИ',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSec,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${threshold.toStringAsFixed(0)} µT',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.uaYellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: threshold,
            min: 5,
            max: 50,
            divisions: 45,
            activeColor: AppColors.uaYellow,
            inactiveColor: AppColors.border,
            onChanged: (value) {
              setState(() {
                threshold = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: const Text('КАЛІБРУВАТИ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPri,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: isCalibrating ? null : _calibrate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('СКИНУТИ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSec,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: _resetMax,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: Icon(isScanning ? Icons.stop : Icons.play_arrow, size: 20),
            label: Text(
              isScanning ? 'ЗУПИНИТИ СКАНУВАННЯ' : 'ПОЧАТИ СКАНУВАННЯ',
              style: const TextStyle(letterSpacing: 1, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isScanning ? Colors.red : AppColors.uaBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isCalibrating ? null : _toggleScanning,
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('ЯК КОРИСТУВАТИСЯ', style: TextStyle(fontSize: 16)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. КАЛІБРУВАННЯ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.uaYellow)),
              SizedBox(height: 4),
              Text('Покладіть телефон на чисту поверхню та натисніть "КАЛІБРУВАТИ".', style: TextStyle(fontSize: 12, color: AppColors.textSec)),
              SizedBox(height: 12),

              Text('2. СКАНУВАННЯ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.uaYellow)),
              SizedBox(height: 4),
              Text('Натисніть "ПОЧАТИ" та повільно водіть телефоном. Тримайте 2-5 см.', style: TextStyle(fontSize: 12, color: AppColors.textSec)),
              SizedBox(height: 12),

              Text('ЩО МОЖНА ЗНАЙТИ:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.uaYellow)),
              SizedBox(height: 4),
              Text('• Смартфони/диктофони (5-10 см)\n• Електропроводка (2-5 см)\n• Металеві предмети\n• Камери з ІЧ (3-7 см)', style: TextStyle(fontSize: 12, color: AppColors.textSec)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ЗРОЗУМІЛО', style: TextStyle(color: AppColors.uaYellow)),
          ),
        ],
      ),
    );
  }
}

class _HistoryChartPainter extends CustomPainter {
  final List<double> data;
  final double threshold;
  final double scale;

  _HistoryChartPainter(this.data, this.threshold, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final thresholdPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final thresholdY = size.height - threshold * scale;
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );

    final step = size.width / (data.length - 1);
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - data[i] * scale;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.red, Colors.yellow, Colors.green],
    );

    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
