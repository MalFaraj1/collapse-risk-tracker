import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_alert.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credential = await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // Force a fresh ID token: if an Admin only just assigned this user's
      // role custom claim, a cached token from an earlier session wouldn't
      // reflect it yet. See auth_providers.dart for the long version.
      await credential.user?.getIdTokenResult(true);
      // Navigation on success is handled by the router's redirect logic,
      // which reacts to authStateChangesProvider — no explicit push here.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(String code) => switch (code) {
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
        'user-disabled' => 'تم تعطيل هذا الحساب. تواصل مع مدير النظام.',
        'too-many-requests' => 'محاولات كثيرة متتالية. الرجاء الانتظار قليلًا والمحاولة مجددًا.',
        _ => 'تعذّر تسجيل الدخول. حاول مجددًا.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        children: [
          // Subtle radial accents, matching the approved prototype's login screen.
          Positioned(top: -80, right: -60, child: _glow(AppColors.gold.withOpacity(.10), 260)),
          Positioned(bottom: -100, left: -60, child: _glow(AppColors.ice.withOpacity(.06), 300)),
          Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AppCard(
                  padding: const EdgeInsets.all(34),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)),
                        child: const Center(
                          child: Text('م', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.navy)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('نظام متابعة المباني الآيلة للسقوط',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                      const SizedBox(height: 3),
                      const Text('بلدية طرابلس · لجنة التحوّل الرقمي',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const SizedBox(height: 26),
                      if (_error != null) ...[
                        AppAlert(kind: AppAlertKind.danger, message: _error!),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline, size: 20),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _loading ? null : _signIn(),
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        label: _loading ? 'جارٍ الدخول...' : 'دخول',
                        onPressed: _loading ? null : _signIn,
                        expand: true,
                      ),
                      const SizedBox(height: 16),
                      const Text('وصول داخلي فقط · للمساعدة تواصل مع مدير النظام',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
