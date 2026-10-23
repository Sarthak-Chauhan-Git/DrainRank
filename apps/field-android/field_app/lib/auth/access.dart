part of '../main.dart';

class AccessCheckPage extends StatefulWidget {
  const AccessCheckPage({super.key, required this.user});
  final User user;

  @override
  State<AccessCheckPage> createState() => _AccessCheckPageState();
}

class _AccessCheckPageState extends State<AccessCheckPage> {
  late Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = fieldBackend
        .from('profiles')
        .select()
        .eq('id', widget.user.id)
        .maybeSingle();
  }

  Future<void> _signOut() => fieldBackend.auth.signOut();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return _AccessMessageScreen(
            title: 'Account unavailable',
            message:
                'Your crew profile could not be found. Contact the Municipal Board.',
            onPressed: _signOut,
          );
        }

        final profile = snapshot.data!;
        profile['fullName'] = profile['full_name'];
        profile['municipalId'] = profile['municipal_id'];
        profile['accessBlocked'] = profile['access_blocked'];
        if (profile['accessBlocked'] == true ||
            profile['role'] != 'crew') {
          return _AccessMessageScreen(
            title: 'Access blocked',
            message: 'Contact Municipal Board.',
            onPressed: _signOut,
          );
        }

        return CrewHomePage(
          user: widget.user,
          profile: profile,
          onLogout: _signOut,
        );
      },
    );
  }
}

class _AccessMessageScreen extends StatelessWidget {
  const _AccessMessageScreen({
    required this.title,
    required this.message,
    required this.onPressed,
  });

  final String title;
  final String message;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.gpp_bad_outlined,
                    size: 76,
                    color: const Color(0xFF0F766E),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onPressed,
                    child: const Text('LOG OUT'),
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
