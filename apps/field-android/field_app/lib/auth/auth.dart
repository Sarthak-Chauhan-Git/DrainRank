part of '../main.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.data == null) return const CrewLoginPage();
        return RoleCheckPage(user: snapshot.data!);
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void showAppMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Admin-created Firebase Auth accounts must use this same internal email
/// alias for each Municipal ID. Crew members only enter their Municipal ID.
String internalEmailForMunicipalId(String municipalId) {
  final normalizedId = municipalId.trim().toLowerCase();
  return '$normalizedId@crew.municipal.local';
}

class RoleCheckPage extends StatelessWidget {
  const RoleCheckPage({super.key, required this.user});
  final User user;

  Future<bool> _isAdmin() async {
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return _AccessMessageScreen(
            title: 'Unable to verify account',
            message: 'Please log out and try again. If the problem continues, contact the Municipal Board.',
            onPressed: () => FirebaseAuth.instance.signOut(),
          );
        }
        if (snapshot.data == true) {
          return AdminDashboardPage(user: user);
        }
        return AccessCheckPage(user: user);
      },
    );
  }
}

class CrewLoginPage extends StatefulWidget {
  const CrewLoginPage({super.key});

  @override
  State<CrewLoginPage> createState() => _CrewLoginPageState();
}

class _CrewLoginPageState extends State<CrewLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _municipalIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _adminLogin = false;
  bool _loading = false;
  bool _hidePassword = true;
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _municipalIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final email = _adminLogin
          ? _emailController.text.trim()
          : internalEmailForMunicipalId(_municipalIdController.text);
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      if (_adminLogin) {
        final token = await credential.user!.getIdTokenResult(true);
        if (token.claims?['admin'] != true) {
          await FirebaseAuth.instance.signOut();
          if (mounted) showAppMessage(context, 'This account is not authorized as an administrator.');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if ([
        'invalid-credential',
        'user-not-found',
        'wrong-password',
        'invalid-email',
      ].contains(e.code)) {
        showAppMessage(context, _adminLogin
            ? 'Wrong admin email or password.'
            : 'Wrong Municipal ID or password.');
      } else if (e.code == 'too-many-requests') {
        showAppMessage(
          context,
          'Too many login attempts. Please wait and try again.',
        );
      } else if (e.code == 'network-request-failed') {
        showAppMessage(
          context,
          'Network error. Check your internet connection and try again.',
        );
      } else {
        showAppMessage(
          context,
          'Unable to log in right now. Please try again later.',
        );
        debugPrint('Login error [${e.code}]: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Unable to log in. Please try again.');
      debugPrint('Unexpected login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_city_rounded,
                        size: 82, color: const Color(0xFF0F766E)),
                    const SizedBox(height: 22),
                    Text(
                      _adminLogin ? 'Municipal Board Admin Login' : 'Municipal Crew Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _adminLogin
                          ? 'Sign in with your authorized administrator email and password.'
                          : 'Sign in using the credentials provided by your Municipal Board.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_adminLogin)
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Admin email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) => _adminLogin &&
                            (value == null || !value.contains('@'))
                            ? 'Enter a valid admin email'
                            : null,
                      )
                    else
                      TextFormField(
                        controller: _municipalIdController,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Municipal ID',
                          hintText: 'Enter your unique Municipal ID',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Enter your Municipal ID'
                            : null,
                      ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.go,
                      obscureText: _hidePassword,
                      onFieldSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                        ),
                      ),
                      validator: (value) =>
                      value == null || value.isEmpty
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _loading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('LOG IN',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                        _adminLogin = !_adminLogin;
                        _formKey.currentState?.reset();
                        _emailController.clear();
                        _municipalIdController.clear();
                        _passwordController.clear();
                      }),
                      child: Text(_adminLogin
                          ? 'Switch to Crew Login'
                          : 'Municipal Board Admin Login'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _adminLogin
                          ? 'Only accounts authorized by the Municipal Board can access admin features.'
                          : 'Accounts are created by the Municipal Board. Contact the board for account access or password reset.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
