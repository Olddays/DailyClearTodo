import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isSubmitting = false;
  String? _error;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _infoMessage = null;
    });
    final client = Supabase.instance.client;
    try {
      if (_isSignUp) {
        final res = await client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        // Supabase deliberately doesn't throw for "email already registered" --
        // that would let an attacker enumerate valid accounts. Instead it
        // returns a user with an empty `identities` list. Without this check
        // the screen just sits there with no feedback at all, which is exactly
        // the bug being fixed here.
        if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
          setState(() => _error = '这个邮箱已经注册过了，请直接登录。');
          return;
        }
        if (res.session == null) {
          // Email confirmation is required (the default for a fresh Supabase
          // project) -- signUp succeeds but doesn't sign the user in yet.
          setState(() {
            _infoMessage = '注册成功！我们发了一封确认邮件到 ${_emailController.text.trim()}，点击邮件里的链接确认后再回来登录。';
            _isSignUp = false;
          });
          return;
        }
      } else {
        await client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      await _syncDeviceTimezone();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// user_profiles.timezone defaults to 'UTC' on signup (server has no way to know
  /// the device's real timezone) -- this is what makes the 23:59 auto-archive land
  /// on the user's actual local midnight instead of UTC midnight.
  Future<void> _syncDeviceTimezone() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      await Supabase.instance.client.from('user_profiles').update({'timezone': tz}).eq('user_id', userId);
    } catch (_) {
      // Non-fatal: falls back to UTC, user can be prompted to fix it later in settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('日清', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  const Text('番茄工作法助手'),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder()),
                    validator: (v) => (v == null || !v.contains('@')) ? '请输入有效邮箱' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.length < 6) ? '密码至少6位' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_infoMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _infoMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isSignUp ? '注册' : '登录'),
                  ),
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                              _infoMessage = null;
                            }),
                    child: Text(_isSignUp ? '已有账号？去登录' : '没有账号？去注册'),
                  ),
                  if (!_isSignUp)
                    TextButton(
                      onPressed: _isSubmitting ? null : () => context.push('/forgot-password'),
                      child: const Text('忘记密码？'),
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
