part of '../main.dart';

class CrewCredits extends StatelessWidget {
  const CrewCredits({super.key, required this.uid, this.compact = false});
  final String uid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid)
          .collection('creditAwards').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Current Credits: unavailable');
        }
        final total = snapshot.data?.docs.fold<int>(0, (sum, doc) {
          final amount = doc.data()['credits'];
          return sum + (amount is int ? amount : 0);
        });
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium_outlined, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Text('Current Credits: ${total ?? '...'}',
              style: compact ? Theme.of(context).textTheme.titleMedium :
              Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ]);
      },
    );
  }
}
