import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:med_ad_app/theme/app_theme.dart';

/// Messages sent by the clinic.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _listen() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('patientId') ?? '';
    if (id.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('SentNotifications')
        .where('patientId', isEqualTo: id)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) => d.data()).toList();
      DateTime when(Map<String, dynamic> m) {
        final v = m['sentAt'];
        return v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      }

      list.sort((a, b) => when(b).compareTo(when(a)));
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  ({String label, IconData icon, Color color}) _category(String? c) {
    switch (c) {
      case 'excellent':
        return (
          label: tr(context, 'تهنئة بالالتزام', 'Great adherence'),
          icon: Icons.emoji_events_outlined,
          color: AppColors.success
        );
      case 'moderate':
      case 'poor':
      case 'no_activity':
        return (
          label: tr(context, 'متابعة الالتزام الأسبوعي', 'Weekly follow-up'),
          icon: Icons.insights_outlined,
          color: AppColors.warning
        );
      default:
        return (
          label: tr(context, 'رسالة من فريق الرعاية', 'Message from your care team'),
          icon: Icons.campaign_outlined,
          color: AppColors.primary
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = isArabic(context);
    final fmt = DateFormat(ar ? 'd MMMM yyyy، h:mm a' : 'd MMMM yyyy, h:mm a', ar ? 'ar' : 'en');
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'الإشعارات', 'Notifications'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(child: Text(tr(context, 'تعذّر تحميل الإشعارات.', 'Could not load notifications.')))
              : _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.notifications_none_rounded,
                            size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        Text(tr(context, 'لا توجد إشعارات حتى الآن.', 'No notifications yet.'),
                            style: const TextStyle(color: AppColors.textMuted)),
                      ]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        final cat = _category(n['category']?.toString());
                        final sent = n['sentAt'];
                        return AppCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cat.color.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(cat.icon, color: cat.color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${n['title'] ?? ''}'.isNotEmpty
                                          ? '${n['title']}'
                                          : cat.label,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${n['message'] ?? ''}',
                                        style: const TextStyle(fontSize: 15, height: 1.6)),
                                    if (sent is Timestamp) ...[
                                      const SizedBox(height: 6),
                                      Text(fmt.format(sent.toDate()),
                                          style: const TextStyle(
                                              fontSize: 12, color: AppColors.textMuted)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
