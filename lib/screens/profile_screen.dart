import 'package:med_ad_app/screens/aboutus_screen.dart';
import 'package:flutter/material.dart';
import 'package:med_ad_app/provider/local_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _patientName = 'Loading...';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPatientInfo();
  }

  Future<void> _loadPatientInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getString('patientId');
      if (patientId != null && patientId.isNotEmpty) {
        await _fetchPatientName(patientId);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Patient ID not found.';
          _patientName = 'غير متوفر';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load patient info: $e';
        _patientName = 'خطأ في التحميل';
      });
    }
  }

  Future<void> _fetchPatientName(String patientId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ActivePatient')
          .where('patientId', isEqualTo: patientId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final patientData = snapshot.docs.first.data();
        final fullName = patientData['patientName'];
        if (fullName != null && fullName.isNotEmpty) {
          setState(() {
            _patientName = fullName;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _patientName = 'اسم غير متوفر';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _patientName = 'مريض غير موجود';
        
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to fetch patient name: $e';
        _patientName = 'خطأ في جلب الاسم';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage = Provider.of<LocaleProvider>(context).currentLanguage;

    Map<String, Map<String, String>> _localizedTexts = {
      'en': {
        'about': 'About App',
        'whatsapp': 'Contact via WhatsApp',
        'change_language': 'Change Language',
      },
      'ar': {
        'about': 'عن التطبيق',
        'whatsapp': 'تواصل عبر الواتساب',
        'change_language': 'تغيير اللغة',
      },
    };

    final texts = _localizedTexts[currentLanguage]!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 106, 31, 217),
                    const Color.fromARGB(255, 3, 226, 255)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(50),
                  bottomRight: Radius.circular(50),
                ),
              ),
              height: 250,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 80,
                    child: ClipOval(
                      child: Image.asset(
                        "assets/avatar.png",
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 200,
                    child: _isLoading
                        ? Text(
                            "جاري التحميل...",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: const Color.fromARGB(255, 232, 231, 231),
                            ),
                          )
                        : Text(
                            _patientName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: const Color.fromARGB(255, 232, 231, 231),
                            ),
                          ),
                  ),
                  if (_errorMessage != null)
                    Positioned(
                      bottom: 20,
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 50),
            Expanded(
              child: ListView(
                children: [
                  _buildListTile(Icons.info_outline, texts['about']!, onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AboutusScreen()),
                    );
                  }),
                  _buildListTile(Icons.message, texts['whatsapp']!, onTap: () {
                    _launchWhatsApp(context); // Pass context to show SnackBar
                  }),
                  _buildListTile(Icons.language, texts['change_language']!, onTap: _showLanguageDialog),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, {VoidCallback? onTap}) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading:
            Icon(icon, color: const Color.fromARGB(255, 106, 31, 217), size: 28),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color.fromARGB(255, 100, 98, 98),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Colors.grey,
          size: 18,
        ),
        onTap: onTap,
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Choose Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('English'),
                onTap: () => _changeLanguage('en'),
              ),
              ListTile(
                title: Text('العربية'),
                onTap: () => _changeLanguage('ar'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeLanguage(String language) {
    Provider.of<LocaleProvider>(context, listen: false).changeLanguage(language);
    Navigator.pop(context);
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final phoneNumber = '96879335705'; 
    final message = 'مرحبا. ';


    final whatsappUrl = Uri.parse('whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}');
    final webWhatsappUrl = Uri.parse('https://wa.me/$phoneNumber/?text=${Uri.encodeComponent(message)}');

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webWhatsappUrl)) {
        await launchUrl(webWhatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح واتساب. يرجى التأكد من تثبيت التطبيق.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error launching WhatsApp: $e'); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء محاولة فتح واتساب.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}