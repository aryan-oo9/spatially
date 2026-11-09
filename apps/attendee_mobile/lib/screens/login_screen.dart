import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app/app_shell.dart';
import '../design_system/design_system.dart';
import '../services/auth_service.dart';

/// Authentication gate screen for Spatially Attendee (ADR 0001).
///
/// Enforces authenticated user sessions prior to accessing tickets,
/// exploration, gamified passport, and safety features.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await AuthService().signInWithGoogle();
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SpatiallyAppShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google sign-in was cancelled or failed: $e';
        });
      }
    }
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final response = await auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SpatiallyAppShell()),
        );
      } else {
        throw Exception('Sign-in failed. Please verify your credentials.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary = isDark ? SpatiallyColors.darkTextPrimary : SpatiallyColors.lightTextPrimary;
    final textSecondary = isDark ? SpatiallyColors.darkTextSecondary : SpatiallyColors.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SpatiallySpacing.lg, vertical: SpatiallySpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Branding
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: SpatiallyColors.violet.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_rounded,
                        color: SpatiallyColors.violet,
                        size: 36,
                      ),
                    ),
                  ),
                  SpatiallySpacing.gapVerticalMd,
                  Text(
                    'Welcome to Spatially',
                    textAlign: TextAlign.center,
                    style: SpatiallyTypography.headingLarge(color: textPrimary).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SpatiallySpacing.gapVerticalXs,
                  Text(
                    'Sign in to access your registered tickets, interactive event passport, and live updates.',
                    textAlign: TextAlign.center,
                    style: SpatiallyTypography.body(color: textSecondary),
                  ),
                  SpatiallySpacing.gapVerticalXl,

                  // Error alert
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(SpatiallySpacing.sm),
                      decoration: BoxDecoration(
                        color: SpatiallyColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(SpatiallyRadius.sm),
                        border: Border.all(color: SpatiallyColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: SpatiallyColors.error, size: 20),
                          SpatiallySpacing.gapHorizontalXs,
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: SpatiallyTypography.caption(color: SpatiallyColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SpatiallySpacing.gapVerticalMd,
                  ],

                  // Email input
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Please enter your email.';
                      if (!val.contains('@')) return 'Enter a valid email address.';
                      return null;
                    },
                  ),
                  SpatiallySpacing.gapVerticalMd,

                  // Password input
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Please enter your password.';
                      return null;
                    },
                  ),
                  SpatiallySpacing.gapVerticalLg,

                  // Sign In button
                  SpatiallyPrimaryButton(
                    label: _isLoading ? 'Signing In...' : 'Sign In with Email',
                    onPressed: _isLoading ? null : _signInWithEmail,
                    isLoading: _isLoading,
                    fullWidth: true,
                  ),
                  SpatiallySpacing.gapVerticalMd,

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: SpatiallySpacing.sm),
                        child: Text('OR', style: SpatiallyTypography.caption(color: textSecondary)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  SpatiallySpacing.gapVerticalMd,

                  // Google Sign In button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SpatiallyRadius.md),
                      ),
                    ),
                    icon: const Icon(Icons.account_circle_outlined, size: 20),
                    label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: _isLoading ? null : _signInWithGoogle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

