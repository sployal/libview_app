import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'client_workspace_screen.dart';
import 'semesters_screen.dart';

class MaterialsTabScreen extends StatelessWidget {
  const MaterialsTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) {
      return const SemestersScreen();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AuthService.instance.profileDocStream(uid),
      builder: (context, snapshot) {
        final role = snapshot.data?.data()?['role'] as String?;
        if (AuthService.isClientRole(role)) {
          return const ClientWorkspaceScreen();
        }
        return const SemestersScreen();
      },
    );
  }
}
