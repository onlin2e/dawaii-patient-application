import 'package:flutter/material.dart';
import 'dart:async';
import 'package:med_ad_app/screens/login_screen.dart';
import 'package:med_ad_app/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _checkLoginAndNavigate();
  }

  Future<void> _checkLoginAndNavigate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? patientId = prefs.getString('patientId');

    Timer(const Duration(seconds: 3), () {
      if (patientId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: CirclePainter(_animation.value),
                );
              },
            ),
          ),
          Center(
            child: Image.asset(
              'assets/2812649.png',
              width: 150,
              height: 150,
            ),
          ),
        ],
      ),
    );
  }
}

class CirclePainter extends CustomPainter {
  final double scale;

  CirclePainter(this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromARGB(255, 251, 250, 252).withOpacity(0.1),
          Color.fromARGB(255, 21, 186, 198).withOpacity(0.3),
          Color.fromARGB(255, 77, 30, 220).withOpacity(0.3),
        ],
        stops: [0.4, 0.7, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: size.width * scale,
        ),
      );

    for (double i = 1; i <= 3; i++) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width * scale * (i / 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}