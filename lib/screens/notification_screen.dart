import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _patientId;
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadPatientIdAndFetchNotifications();
  }

  Future<String?> getPatientId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('patientId');
  }

  Future<void> _loadPatientIdAndFetchNotifications() async {
    _patientId = await getPatientId();
    if (_patientId != null && _patientId!.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('SentNotifications')
          .where('patientId', isEqualTo: _patientId)
          .snapshots()
          .listen(
        (snapshot) {
          setState(() {
            _notifications = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
            _notifications.sort((a, b) => (b['sentAt'] as Timestamp).compareTo(a['sentAt'] as Timestamp));
            _isLoading = false;
          });
        },
        onError: (error) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'حدث خطأ: $error';
          });
        },
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'لم يتم العثور على معرف المريض.';
      });
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate().toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(child: Text(_errorMessage!))
                : _notifications.isEmpty
                    ? const Center(child: Text('لا يوجد إشعارات حتى الآن.'))
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          String categoryTitle;
                          if (notification['category'] == 'general') { // تم التغيير من 'education' إلى 'general'
                            categoryTitle = 'إشعار';
                          } else if (notification['category'] == 'excellent' ||
                                     notification['category'] == 'moderate' ||
                                     notification['category'] == 'poor') {
                            categoryTitle = 'إشعار الالتزام الأسبوعي'; 
                          } else {
                            categoryTitle = 'إشعار'; 
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: const Icon(
                                Icons.notifications,
                                color: Colors.orange,
                              ),
                              title: Text(
                                categoryTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification['message'] ?? 'لا يوجد رسالة',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'تم الإرسال في: ${_formatTimestamp(notification['sentAt'])}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}