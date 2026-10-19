
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
runApp(const MunicipalCrewApp());
}

class MunicipalCrewApp extends StatelessWidget {
const MunicipalCrewApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'Municipal Crew Services',
debugShowCheckedModeBanner: false,
theme: ThemeData(
useMaterial3: true,
colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
inputDecorationTheme: const InputDecorationTheme(
border: OutlineInputBorder(),
),
),
home: const AuthGate(),
);
}
}

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

@override
void dispose() {
_municipalIdController.dispose();
_emailController.dispose();
_passwordController.dispose();
super.dispose();
}

Future<void> _login() async {
if (!_formKey.currentState!.validate()) return;
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
size: 82, color: Colors.deepPurple),
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
obscureText: _hidePassword,
onFieldSubmitted: (_) {
if (!_loading) _login();
},
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

class AdminDashboardPage extends StatelessWidget {
const AdminDashboardPage({super.key, required this.user});
final User user;

Future<void> _logout() => FirebaseAuth.instance.signOut();

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text('Municipal Board Admin'),
actions: [
IconButton(
tooltip: 'Log out',
onPressed: _logout,
icon: const Icon(Icons.logout),
),
],
),
body: Center(
child: SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: ConstrainedBox(
constraints: const BoxConstraints(maxWidth: 560),
child: Card(
child: Padding(
padding: const EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
const Icon(Icons.admin_panel_settings_outlined,
size: 72, color: Colors.deepPurple),
const SizedBox(height: 16),
const Text('Administrator Dashboard',
textAlign: TextAlign.center,
style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
const Text(
'You are signed in with an administrator account.',
textAlign: TextAlign.center,
),
const SizedBox(height: 24),
const ListTile(
leading: Icon(Icons.person_add_alt_1),
title: Text('Add crew member'),
subtitle: Text(
'Account creation needs a trusted backend. It is not enabled yet, so this screen cannot create accounts securely.',
),
),
const SizedBox(height: 12),
const Text(
'Next step: connect a secure free-tier backend before enabling account creation. Do not place service-account credentials or admin secrets in this Flutter app.',
),
const SizedBox(height: 20),
FilledButton.icon(
onPressed: _logout,
icon: const Icon(Icons.logout),
label: const Text('LOG OUT'),
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

class AccessCheckPage extends StatefulWidget {
const AccessCheckPage({super.key, required this.user});
final User user;

@override
State<AccessCheckPage> createState() => _AccessCheckPageState();
}

class _AccessCheckPageState extends State<AccessCheckPage> {
late Future<DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

@override
void initState() {
super.initState();
_profileFuture = FirebaseFirestore.instance
    .collection('users')
    .doc(widget.user.uid)
    .get();
}

Future<void> _signOut() => FirebaseAuth.instance.signOut();

@override
Widget build(BuildContext context) {
return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
future: _profileFuture,
builder: (context, snapshot) {
if (snapshot.connectionState == ConnectionState.waiting) {
return const LoadingScreen();
}
if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
return _AccessMessageScreen(
title: 'Account unavailable',
message: 'Your crew profile could not be found. Contact the Municipal Board.',
onPressed: _signOut,
);
}

final profile = snapshot.data!.data()!;
if (profile['accessBlocked'] == true) {
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
const Icon(Icons.gpp_bad_outlined,
size: 76, color: Colors.deepPurple),
const SizedBox(height: 20),
Text(title,
textAlign: TextAlign.center,
style: const TextStyle(
fontSize: 26, fontWeight: FontWeight.bold)),
const SizedBox(height: 12),
Text(message, textAlign: TextAlign.center),
const SizedBox(height: 24),
FilledButton(onPressed: onPressed, child: const Text('LOG OUT')),
],
),
),
),
),
),
);
}
}

String _dateKey(DateTime date) {
final local = DateTime(date.year, date.month, date.day);
final year = local.year.toString().padLeft(4, '0');
final month = local.month.toString().padLeft(2, '0');
final day = local.day.toString().padLeft(2, '0');
return '$year-$month-$day';
}

String _prettyDate(DateTime date) {
const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}

class CrewHomePage extends StatefulWidget {
const CrewHomePage({
super.key,
required this.user,
required this.profile,
required this.onLogout,
});

final User user;
final Map<String, dynamic> profile;
final Future<void> Function() onLogout;

@override
State<CrewHomePage> createState() => _CrewHomePageState();
}

class _CrewHomePageState extends State<CrewHomePage> {
DateTime _selectedDate = DateTime.now();
int _refreshCounter = 0;

void _refreshTasks() {
setState(() {
_refreshCounter++;
});
ScaffoldMessenger.of(context)
..hideCurrentSnackBar()
..showSnackBar(
const SnackBar(
content: Text('Refreshing assigned tasks...'),
duration: Duration(seconds: 1),
behavior: SnackBarBehavior.floating,
),
);
}

DateTime _dayOnly(DateTime date) =>
DateTime(date.year, date.month, date.day);

void _selectDay(int offset) {
setState(() {
_selectedDate = _dayOnly(DateTime.now().add(Duration(days: offset)));
});
}

Future<void> _pickDate() async {
final now = DateTime.now();
final picked = await showDatePicker(
context: context,
initialDate: _selectedDate,
firstDate: DateTime(2020),
lastDate: DateTime(2100),
helpText: 'Choose task date',
);
if (picked != null && mounted) {
setState(() => _selectedDate = _dayOnly(picked));
}
}

@override
Widget build(BuildContext context) {
final today = _dayOnly(DateTime.now());
final selectedKey = _dateKey(_selectedDate);
final todayKey = _dateKey(today);
final yesterdayKey = _dateKey(today.subtract(const Duration(days: 1)));
final tomorrowKey = _dateKey(today.add(const Duration(days: 1)));
final isToday = selectedKey == todayKey;
final isYesterday = selectedKey == yesterdayKey;
final isTomorrow = selectedKey == tomorrowKey;
final profileName = (widget.profile['fullName'] ??
widget.profile['name'] ??
widget.user.displayName ??
'')
    .toString()
    .trim();
final crewName = profileName.isNotEmpty
? profileName
    : (widget.user.email?.split('@').first ?? 'there');

// Query tasks for the signed-in crew member, then filter by date below.
// Firestore rules must allow this user to read only their own assigned tasks.
debugPrint('Signed-in crew UID: ${widget.user.uid}');
debugPrint('Selected task dateKey: $selectedKey');

final tasksStream = FirebaseFirestore.instance
    .collection('tasks')
    .where('assignedToUid', isEqualTo: widget.user.uid)
    .snapshots();

// Referencing the counter makes each manual refresh rebuild this screen
// and recreate the Firestore stream subscription.
final currentRefresh = _refreshCounter;
debugPrint('Task refresh number: $currentRefresh');

return Scaffold(
// Keep the top bar for logout only. The app title is placed in the
// page body so it can be larger and visually centered below the top bar.
appBar: AppBar(
automaticallyImplyLeading: false,
title: const SizedBox.shrink(),
actions: [
IconButton(
tooltip: 'Refresh tasks',
onPressed: _refreshTasks,
icon: const Icon(Icons.refresh),
),
IconButton(
tooltip: 'Log out',
onPressed: widget.onLogout,
icon: const Icon(Icons.logout),
),
const SizedBox(width: 8),
],
),
body: Center(
child: SingleChildScrollView(
padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
child: ConstrainedBox(
constraints: const BoxConstraints(maxWidth: 700),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
// Main heading: centered in the page, larger and bold.
const SizedBox(height: 34),
const Text(
'Municipal Crew Services',
textAlign: TextAlign.center,
style: TextStyle(
fontSize: 36,
fontWeight: FontWeight.w800,
letterSpacing: 0.2,
),
),
const SizedBox(height: 42),
Text(
'Hello, $crewName!',
textAlign: TextAlign.center,
style: const TextStyle(
fontSize: 25,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 8),
Text(
isToday
? 'Here are your tasks for today.'
    : isYesterday
? 'Here are your tasks from yesterday.'
    : isTomorrow
? 'Here are your tasks for tomorrow.'
    : 'Here are your tasks for ${_prettyDate(_selectedDate)}.',
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.bodyLarge?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 22),

// Quick date tabs: Yesterday, Today, Tomorrow.
Row(
children: [
Expanded(
child: _DateTab(
label: 'YESTERDAY',
icon: Icons.calendar_month,
selected: isYesterday,
onTap: () => _selectDay(-1),
),
),
const SizedBox(width: 8),
Expanded(
child: _DateTab(
label: 'TODAY',
icon: Icons.event_available,
selected: isToday,
onTap: () => _selectDay(0),
),
),
const SizedBox(width: 8),
Expanded(
child: _DateTab(
label: 'TOMORROW',
icon: Icons.calendar_today,
selected: isTomorrow,
onTap: () => _selectDay(1),
),
),
],
),
const SizedBox(height: 12),

// A separate date picker allows choosing any date.
OutlinedButton.icon(
onPressed: _pickDate,
icon: const Icon(Icons.edit_calendar),
label: Text('Choose date  •  ${_prettyDate(_selectedDate)}'),
style: OutlinedButton.styleFrom(
padding: const EdgeInsets.symmetric(
horizontal: 16,
vertical: 15,
),
alignment: Alignment.center,
),
),
const SizedBox(height: 20),

Row(
children: [
const Icon(Icons.water_damage_outlined, size: 24),
const SizedBox(width: 9),
Expanded(
child: Text(
isToday
? "Today's drain-cleaning tasks"
    : isYesterday
? "Yesterday's drain-cleaning tasks"
    : isTomorrow
? "Tomorrow's drain-cleaning tasks"
    : "Drain-cleaning tasks",
style: Theme.of(context).textTheme.titleMedium?.copyWith(
fontWeight: FontWeight.bold,
),
),
),
],
),
const SizedBox(height: 12),

StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
stream: tasksStream,
builder: (context, snapshot) {
if (snapshot.connectionState == ConnectionState.waiting) {
return const Padding(
padding: EdgeInsets.all(36),
child: Center(child: CircularProgressIndicator()),
);
}
if (snapshot.hasError) {
debugPrint('Task loading error: ${snapshot.error}');
final error = snapshot.error.toString();
return Card(
child: Padding(
padding: const EdgeInsets.all(20),
child: Column(
children: [
const Icon(Icons.cloud_off_outlined, size: 42),
const SizedBox(height: 10),
const Text(
'Unable to load assigned tasks',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
),
textAlign: TextAlign.center,
),
const SizedBox(height: 8),
const Text(
'The app could not read tasks from Firebase. No demo tasks are shown. Check Firestore rules and the task query.',
textAlign: TextAlign.center,
),
const SizedBox(height: 12),
SelectableText(
error,
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.bodySmall,
),
],
),
),
);
}

final allAssignedTasks = snapshot.data?.docs ?? [];
debugPrint(
'Tasks returned for UID: ${allAssignedTasks.length}',
);
debugPrint(
'Task dateKeys returned: ${allAssignedTasks.map((doc) => doc.data()['dateKey']).toList()}',
);

final tasks = allAssignedTasks
    .where((doc) => doc.data()['dateKey'] == selectedKey)
    .toList();

debugPrint(
'Tasks matching selected date: ${tasks.length}',
);

tasks.sort((a, b) =>
(a.data()['startTime'] as String? ?? '')
    .compareTo(b.data()['startTime'] as String? ?? ''));

if (tasks.isEmpty) {
return Card(
child: Padding(
padding: const EdgeInsets.all(24),
child: Column(
children: [
const Icon(Icons.event_busy_outlined, size: 42),
const SizedBox(height: 10),
Text(
isToday
? 'Hello, $crewName! You have no tasks for today.'
    : isYesterday
? 'Hello, $crewName! You had no tasks yesterday.'
    : isTomorrow
? 'Hello, $crewName! You have no tasks assigned for tomorrow yet.'
    : 'Hello, $crewName! You have no tasks assigned for ${_prettyDate(_selectedDate)}.',
style: const TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
),
textAlign: TextAlign.center,
),
const SizedBox(height: 6),
Text(
isToday
? 'Enjoy your day. New tasks will appear here when they are assigned to you.'
    : 'If a task is assigned for ${_prettyDate(_selectedDate)}, it will appear here.',
textAlign: TextAlign.center,
),
],
),
),
);
}

return Column(
children: [
for (var i = 0; i < tasks.length; i++)
_DrainTaskCard(
data: tasks[i].data(),
number: i + 1,
),
],
);
},
),
],
),
),
),
),
);
}
}


List<Map<String, dynamic>> _sampleTasksForDate(String dateKey) {
// Demonstration data only: these tasks are not written to Firestore.
return [
{
'title': 'Clean roadside drain',
'startTime': '08:00 AM',
'endTime': '09:30 AM',
'location': 'Ward 12, near Community Park',
'description': 'Remove waste and blockage. Keep the footpath clear.',
'status': 'Pending',
'dateKey': dateKey,
},
{
'title': 'Remove drain blockage',
'startTime': '10:00 AM',
'endTime': '11:00 AM',
'location': 'Main Market Road, opposite Bus Stop',
'description': 'Check water flow and collect removed waste safely.',
'status': 'In Progress',
'dateKey': dateKey,
},
{
'title': 'Inspect and rinse drain',
'startTime': '01:00 PM',
'endTime': '02:00 PM',
'location': 'Lane 4, Shastri Nagar',
'description': 'Confirm the drain is flowing freely after cleaning.',
'status': 'Completed',
'dateKey': dateKey,
},
];
}

class _DemoTaskPreview extends StatelessWidget {
const _DemoTaskPreview({
required this.tasks,
required this.firebaseError,
});

final List<Map<String, dynamic>> tasks;
final bool firebaseError;

@override
Widget build(BuildContext context) {
final colors = Theme.of(context).colorScheme;
return Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Container(
padding: const EdgeInsets.all(12),
margin: const EdgeInsets.only(bottom: 12),
decoration: BoxDecoration(
color: colors.tertiaryContainer,
borderRadius: BorderRadius.circular(12),
),
child: Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Icon(
firebaseError ? Icons.cloud_off_outlined : Icons.visibility_outlined,
color: colors.onTertiaryContainer,
),
const SizedBox(width: 10),
Expanded(
child: Text(
firebaseError
? 'Showing sample tasks because Firebase tasks could not be loaded. These are demo examples, not real assignments. Check Firestore rules, the tasks collection, and the debug console.'
    : 'Sample preview only — these example tasks are not saved in Firebase. Real tasks assigned by the admin will appear here.',
style: TextStyle(color: colors.onTertiaryContainer),
),
),
],
),
),
for (var i = 0; i < tasks.length; i++)
_DrainTaskCard(data: tasks[i], number: i + 1),
],
);
}
}

class _DateTab extends StatelessWidget {
const _DateTab({
required this.label,
required this.icon,
required this.selected,
required this.onTap,
});

final String label;
final IconData icon;
final bool selected;
final VoidCallback onTap;

@override
Widget build(BuildContext context) {
final colors = Theme.of(context).colorScheme;
return Material(
color: selected ? colors.surfaceContainerHighest : colors.surface,
borderRadius: BorderRadius.circular(12),
child: InkWell(
onTap: onTap,
borderRadius: BorderRadius.circular(12),
child: Container(
padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
decoration: BoxDecoration(
border: Border.all(
color: selected ? colors.primary : colors.outlineVariant,
width: selected ? 1.5 : 1,
),
borderRadius: BorderRadius.circular(12),
),
child: Column(
children: [
Text(
label,
textAlign: TextAlign.center,
style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
),
const SizedBox(height: 7),
Icon(icon, size: 23),
],
),
),
),
);
}
}

class _TaskMessage extends StatelessWidget {
const _TaskMessage({
required this.icon,
required this.title,
required this.message,
});

final IconData icon;
final String title;
final String message;

@override
Widget build(BuildContext context) {
return Card(
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
child: Column(
children: [
Icon(icon, size: 46),
const SizedBox(height: 12),
Text(
title,
textAlign: TextAlign.center,
style: Theme.of(context).textTheme.titleMedium?.copyWith(
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 7),
Text(message, textAlign: TextAlign.center),
],
),
),
);
}
}

class _DrainTaskCard extends StatelessWidget {
const _DrainTaskCard({required this.data, required this.number});

final Map<String, dynamic> data;
final int number;

@override
Widget build(BuildContext context) {
final title = (data['title'] as String?)?.trim();
final startTime = (data['startTime'] as String?)?.trim() ?? '';
final endTime = (data['endTime'] as String?)?.trim() ?? '';
final location = (data['location'] as String?)?.trim() ?? '';
final status = (data['status'] as String?)?.trim() ?? 'Pending';
final description = (data['description'] as String?)?.trim() ?? '';

return Card(
margin: const EdgeInsets.only(bottom: 12),
clipBehavior: Clip.antiAlias,
child: Padding(
padding: const EdgeInsets.all(17),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Container(
width: 44,
height: 44,
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.secondaryContainer,
borderRadius: BorderRadius.circular(12),
),
child: const Icon(Icons.water_damage_outlined, size: 25),
),
const SizedBox(width: 13),
Expanded(
child: Text(
(title == null || title.isEmpty) ? 'Clean assigned drain' : title,
style: Theme.of(context).textTheme.titleLarge?.copyWith(
fontWeight: FontWeight.bold,
),
),
),
Text(
'#$number',
style: Theme.of(context).textTheme.labelLarge?.copyWith(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
],
),
const SizedBox(height: 16),
_TaskDetailRow(
icon: Icons.schedule,
label: 'Time',
value: startTime.isEmpty
? 'Time not specified'
    : '$startTime${endTime.isNotEmpty ? ' – $endTime' : ''}',
),
const SizedBox(height: 10),
_TaskDetailRow(
icon: Icons.location_on_outlined,
label: 'Address',
value: location.isEmpty ? 'Address not specified' : location,
),
if (description.isNotEmpty) ...[
const SizedBox(height: 10),
_TaskDetailRow(
icon: Icons.notes,
label: 'Instructions',
value: description,
),
],
const SizedBox(height: 14),
Row(
children: [
const Text(
'Task status',
style: TextStyle(fontWeight: FontWeight.w600),
),
const Spacer(),
Chip(
avatar: Icon(
status.toLowerCase() == 'completed'
? Icons.check_circle
    : Icons.pending_actions,
size: 17,
),
label: Text(status),
visualDensity: VisualDensity.compact,
),
],
),
],
),
),
);
}
}

class _TaskDetailRow extends StatelessWidget {
const _TaskDetailRow({
required this.icon,
required this.label,
required this.value,
});

final IconData icon;
final String label;
final String value;

@override
Widget build(BuildContext context) {
return Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
const SizedBox(width: 9),
SizedBox(
width: 78,
child: Text(
label,
style: const TextStyle(fontWeight: FontWeight.w600),
),
),
Expanded(child: Text(value)),
],
);
}
}
