import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:med_ad_app/provider/local_provider.dart';
import 'package:med_ad_app/screens/aboutus_screen.dart';
import 'package:med_ad_app/theme/app_theme.dart';

/// "حسابي".
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _phone = '';
  bool _loading = true;

  static const _clinicWhatsApp = '96879335705';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('patientId') ?? '';
      if (id.isNotEmpty) {
        final doc =
            await FirebaseFirestore.instance.collection('ActivePatient').doc(id).get();
        final d = doc.data() ?? {};
        _name = '${d['patientName'] ?? ''}';
        _phone = '${d['patientPhone'] ?? ''}';
      }
    } catch (e) {
      debugPrint('profile load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openWhatsApp() async {
    final text = Uri.encodeComponent('مرحبًا، ');
    final app = Uri.parse('whatsapp://send?phone=$_clinicWhatsApp&text=$text');
    final web = Uri.parse('https://wa.me/$_clinicWhatsApp?text=$text');
    try {
      if (await canLaunchUrl(app)) {
        await launchUrl(app, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(tr(context, 'تعذّر فتح واتساب. يرجى التأكد من تثبيت التطبيق.',
            'Could not open WhatsApp.', listen: false)),
      ));
    }
  }

  void _chooseLanguage() {
    final provider = Provider.of<LocaleProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final l in const [('ar', 'العربية'), ('en', 'English')])
              ListTile(
                title: Text(l.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: provider.currentLanguage == l.$1
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  provider.changeLanguage(l.$1);
                  Navigator.pop(c);
                },
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _name.trim().isEmpty ? '' : _name.trim().characters.first;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 28, 20, 28),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: initial.isEmpty
                    ? const Icon(Icons.person_outline, color: Colors.white, size: 40)
                    : Text(initial,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Text(
                _loading ? tr(context, 'جارٍ التحميل…', 'Loading…') : _name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (_phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(_phone,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                _tile(Icons.chat_outlined, tr(context, 'التواصل مع الصيدلي عبر واتساب', 'Contact the pharmacist on WhatsApp'),
                    _openWhatsApp),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                _tile(Icons.language_rounded, tr(context, 'لغة التطبيق', 'App language'), _chooseLanguage,
                    trailingText: tr(context, 'العربية', 'English')),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                _tile(Icons.info_outline_rounded, tr(context, 'عن التطبيق', 'About the app'), () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutusScreen()));
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap, {String? trailingText}) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailingText != null)
          Text(trailingText, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ]),
      onTap: onTap,
    );
  }
}
