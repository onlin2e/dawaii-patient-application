import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:med_ad_app/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final String testPassword = 'appletest12345';
  final String testName = 'appletest';
  final String testPhone = '95511067';

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? patientId = prefs.getString('patientId');

    if (patientId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    }
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    String name = nameController.text.trim();
    String phone = phoneController.text.trim();
    String password = passwordController.text.trim();

    try {
    
      if (password == testPassword) {
        String? deviceToken = await FirebaseMessaging.instance.getToken();

        await FirebaseFirestore.instance.collection('ActivePatient').doc(testPassword).set(
          {
            'patientId': testPassword,
            'patientName': testName,
            'patientPhone': testPhone,
            'deviceToken': deviceToken,
          },
          SetOptions(merge: true), 
        );

        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('patientId', testPassword);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );

        return;
      }

      var querySnapshot = await FirebaseFirestore.instance
          .collection('AddPatient')
          .where('id', isEqualTo: password)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var activePatientSnapshot = await FirebaseFirestore.instance
            .collection('ActivePatient')
            .where('patientId', isEqualTo: password)
            .get();

        if (activePatientSnapshot.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم استخدام الرمز السري مسبقًا')),
          );
        } else {
          String? deviceToken = await FirebaseMessaging.instance.getToken();

          await FirebaseFirestore.instance.collection('ActivePatient').doc(password).set({
            'patientId': password,
            'patientName': name,
            'patientPhone': phone,
            'deviceToken': deviceToken,
          });

          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setString('patientId', password);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('الرمز السري غير صحيح')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ، حاول مرة أخرى')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: screenHeight * 0.1),
                  Text(
                    'أهلا بك!',
                    style: TextStyle(
                      color: Color(0xFF6A1FD9),
                      fontSize: screenWidth * 0.08,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Text('قم بتسجيل الدخول للمتابعة',
                      style: TextStyle(
                        color: Color(0xFF6A1FD9),
                        fontSize: screenWidth * 0.05,
                      )),
                  SizedBox(height: screenHeight * 0.05),
                  TextFormField(
                    controller: nameController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFFF9F4F8),
                      hintText: 'ادخل اسمك',
                      suffixIcon: Icon(Icons.person, color: Color(0xFF6A1FD9)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Color(0xFF6A1FD9)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'الرجاء إدخال الاسم' : null,
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  TextFormField(
                    controller: phoneController,
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFFF9F4F8),
                      hintText: 'ادخل رقم الهاتف',
                      suffixIcon: Icon(Icons.phone, color: Color(0xFF6A1FD9)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Color(0xFF6A1FD9)),
                      ),
                    ),
                    validator: (value) {
                      if (value!.isEmpty) return 'الرجاء إدخال رقم الهاتف';
                      if (value.length != 8) return 'رقم الهاتف يجب أن يكون 8 أرقام';
                      return null;
                    },
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  TextFormField(
                    controller: passwordController,
                    textAlign: TextAlign.right,
                    obscureText: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFFF9F4F8),
                      hintText: 'الرمز السري',
                      suffixIcon: Icon(Icons.lock, color: Color(0xFF6A1FD9)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Color(0xFF6A1FD9)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'الرجاء إدخال الرمز السري' : null,
                  ),
                  SizedBox(height: screenHeight * 0.05),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF03B3D2),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.3,
                          vertical: screenHeight * 0.02,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'تسجيل الدخول',
                              style: TextStyle(
                                fontSize: screenHeight * 0.02,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
