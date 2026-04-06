import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AboutusScreen extends StatefulWidget {
  const AboutusScreen({super.key});

  @override
  State<AboutusScreen> createState() => _AboutusScreenState();
}

class _AboutusScreenState extends State<AboutusScreen> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(255, 106, 31, 217).withOpacity(0.8),
                  const Color.fromARGB(255, 3, 226, 255).withOpacity(0.8),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          ClipPath(
            clipper: WaveClipper(),
            child: Container(
              height: screenHeight * 0.4,
              color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.3),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Image.asset(
                    'assets/2812649.png',
                    height: screenHeight * 0.25,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: screenHeight * 0.35),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نبذة عن تطبيق دوائي',
                    style: TextStyle(
                      fontSize: screenWidth * 0.05,
                      fontWeight: FontWeight.bold,
                      color: const Color.fromARGB(255, 75, 12, 169),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'دوائي هو تطبيق مبتكر يهدف إلى مساعدتك في إدارة أدويتك ومواعيد تناولها بكفاءة وسهولة. سواء كنت تتناول دواءً واحدًا أو عدة أدوية، فإن دوائي يوفر لك الأدوات اللازمة لضمان عدم نسيان أي جرعة.',
                    style: TextStyle(
                      fontSize: screenWidth * 0.04,
                      color: Colors.grey[800],
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'الميزات الرئيسية:',
                    style: TextStyle(
                      fontSize: screenWidth * 0.05,
                      fontWeight: FontWeight.bold,
                      color: const Color.fromARGB(255, 75, 12, 169),
                    ),
                  ),
                  SizedBox(height: 10),
                  _buildFeatureItem('تذكيرات ذكية بمواعيد الأدوية'),
                  _buildFeatureItem('قائمة شاملة بأدويتك وجرعاتها'),
                  _buildFeatureItem('إمكانية تأكيد تناول الدواء وتسجيله'),
                  _buildFeatureItem('جدول تتبع التزامك بتناول الأدوية'), 
                  SizedBox(height: 20),
                  Text(
                    'هدفنا هو تسهيل حياتك وضمان حصولك على العلاج في الوقت المحدد، مما يساهم في تحسين صحتك ',
                    style: TextStyle(
                      fontSize: screenWidth *0.04,
                      color: Colors.grey[800],
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 30),
                  Center(
                    child: Text(
                      'دوائي - صحتك في متناول يدك',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // زر الرجوع
          Positioned(
            top: 20,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String feature) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: const Color.fromARGB(255, 75, 12, 169)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              feature,
              style: TextStyle(fontSize: screenWidth * 0.035 , color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height * 0.7);

    var firstControlPoint = Offset(size.width * 0.25, size.height * 0.6);
    var firstEndPoint = Offset(size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(firstControlPoint.dx, firstControlPoint.dy,
        firstEndPoint.dx, firstEndPoint.dy);

    var secondControlPoint = Offset(size.width * 0.75, size.height * 0.8);
    var secondEndPoint = Offset(size.width, size.height * 0.7);
    path.quadraticBezierTo(secondControlPoint.dx, secondControlPoint.dy,
        secondEndPoint.dx, secondEndPoint.dy);

    path.lineTo(size.width, 0); 
    path.lineTo(0, 0); 

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}