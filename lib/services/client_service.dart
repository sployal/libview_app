import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'upload_service.dart';

class ClientWorkspace {
  final String id;
  final String name;
  final String driveFolderId;
  final String ownerUid;
  final List<String> memberUids;
  final String inviteEmail;
  final bool suspended;
  final int storageLimitBytes;

  static const defaultStorageLimitBytes = 1024 * 1024 * 1024;

  const ClientWorkspace({
    required this.id,
    required this.name,
    required this.driveFolderId,
    required this.ownerUid,
    required this.memberUids,
    this.inviteEmail = '',
    this.suspended = false,
    this.storageLimitBytes = defaultStorageLimitBytes,
  });

  factory ClientWorkspace.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final members = <String>[];
    final rawMembers = data['member_uids'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        final uid = item?.toString() ?? '';
        if (uid.isNotEmpty) members.add(uid);
      }
    }
    return ClientWorkspace(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? 'Client',
      driveFolderId: (data['drive_folder_id'] as String?)?.trim() ?? '',
      ownerUid: (data['owner_uid'] as String?)?.trim() ?? '',
      memberUids: members,
      inviteEmail: normalizeEmail(data['invite_email'] as String?),
      suspended: data['suspended'] == true,
      storageLimitBytes: parseStorageLimitBytes(data['storage_limit_bytes']),
    );
  }

  static String normalizeEmail(String? email) =>
      (email ?? '').trim().toLowerCase();

  static int parseStorageLimitBytes(dynamic value) {
    final parsed = value is int
        ? value
        : value is num
            ? value.round()
            : int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed > 0 ? parsed : defaultStorageLimitBytes;
  }

  static String formatStorage(int bytes) {
    if (bytes <= 0) return '0 MB';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb && bytes % gb == 0) {
      return '${bytes ~/ gb} GB';
    }
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb && bytes % mb == 0) {
      return '${bytes ~/ mb} MB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  static String documentIdFromName(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'client' : slug;
  }
}

class ClientService {
  ClientService._();

  static final ClientService instance = ClientService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _clients =>
      _firestore.collection('clients');

  Stream<List<ClientWorkspace>> watchClients() {
    return _clients.snapshots().map((snapshot) {
      final clients = snapshot.docs
          .map(ClientWorkspace.fromDoc)
          .toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      return clients;
    });
  }

  Future<List<ClientWorkspace>> listClients() async {
    final snapshot = await _clients.get();
    return snapshot.docs.map(ClientWorkspace.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<ClientWorkspace?> clientForUid(String uid) async {
    if (uid.isEmpty) return null;
    final profile = await _firestore.collection('profiles').doc(uid).get();
    final clientId = (profile.data()?['client_id'] as String?)?.trim() ?? '';
    if (clientId.isNotEmpty) {
      final doc = await _clients.doc(clientId).get();
      if (doc.exists) return ClientWorkspace.fromDoc(doc);
    }

    final owned = await _clients.where('owner_uid', isEqualTo: uid).limit(1).get();
    if (owned.docs.isNotEmpty) {
      return ClientWorkspace.fromDoc(owned.docs.first);
    }

    final member = await _clients
        .where('member_uids', arrayContains: uid)
        .limit(1)
        .get();
    if (member.docs.isEmpty) return null;
    return ClientWorkspace.fromDoc(member.docs.first);
  }

  Stream<ClientWorkspace?> watchClientForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<ClientWorkspace?>.value(null);
    }
    return _firestore.collection('profiles').doc(uid).snapshots().asyncMap((
      profile,
    ) async {
      return clientForUid(uid);
    });
  }

  Future<ClientWorkspace?> clientForInviteEmail(String? email) async {
    final normalized = ClientWorkspace.normalizeEmail(email);
    if (normalized.isEmpty || !normalized.contains('@')) return null;
    final snapshot = await _clients
        .where('invite_email', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return ClientWorkspace.fromDoc(snapshot.docs.first);
  }

  Future<ClientWorkspace?> getClient(String id) async {
    if (id.isEmpty) return null;
    final doc = await _clients.doc(id).get();
    if (!doc.exists) return null;
    return ClientWorkspace.fromDoc(doc);
  }

  Future<ClientWorkspace> createClient({
    required String name,
    required String email,
    int storageLimitBytes = ClientWorkspace.defaultStorageLimitBytes,
  }) async {
    final trimmed = name.trim();
    final inviteEmail = ClientWorkspace.normalizeEmail(email);
    if (trimmed.isEmpty) {
      throw UploadException('Client name is required');
    }
    if (inviteEmail.isEmpty || !inviteEmail.contains('@')) {
      throw UploadException('A valid client email is required');
    }

    final existingInvite = await clientForInviteEmail(inviteEmail);
    if (existingInvite != null) {
      throw UploadException('A client with this email already exists');
    }

    final structure = await UploadService.instance.createClientWorkspace(
      name: trimmed,
    );
    if (structure.folderId.isEmpty) {
      throw UploadException('Could not create the client workspace');
    }

    var docId = ClientWorkspace.documentIdFromName(trimmed);
    final existing = await _clients.doc(docId).get();
    if (existing.exists) {
      docId = '${docId}_${DateTime.now().millisecondsSinceEpoch}';
    }

    final limit = storageLimitBytes > 0
        ? storageLimitBytes
        : ClientWorkspace.defaultStorageLimitBytes;

    await _clients.doc(docId).set({
      'name': trimmed,
      'invite_email': inviteEmail,
      'drive_folder_id': structure.folderId,
      'owner_uid': '',
      'member_uids': <String>[],
      'storage_limit_bytes': limit,
      'suspended': false,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    return ClientWorkspace(
      id: docId,
      name: trimmed,
      driveFolderId: structure.folderId,
      ownerUid: '',
      memberUids: const [],
      inviteEmail: inviteEmail,
      storageLimitBytes: limit,
    );
  }

  Future<void> claimInvite({
    required ClientWorkspace client,
    required String uid,
  }) async {
    if (uid.isEmpty) return;
    final members = {...client.memberUids, uid};
    await _clients.doc(client.id).set({
      'owner_uid': client.ownerUid.isEmpty ? uid : client.ownerUid,
      'member_uids': members.toList(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> renameClient({
    required ClientWorkspace client,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw UploadException('Client name is required');
    }
    if (client.driveFolderId.isNotEmpty) {
      await UploadService.instance.renameClientWorkspace(
        folderId: client.driveFolderId,
        name: trimmed,
      );
    }
    await _clients.doc(client.id).set({
      'name': trimmed,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateClient({
    required ClientWorkspace client,
    required String name,
    required String email,
    required int storageLimitBytes,
  }) async {
    final trimmed = name.trim();
    final inviteEmail = ClientWorkspace.normalizeEmail(email);
    final limit = storageLimitBytes > 0
        ? storageLimitBytes
        : ClientWorkspace.defaultStorageLimitBytes;
    if (trimmed.isEmpty) {
      throw UploadException('Client name is required');
    }
    if (inviteEmail.isEmpty || !inviteEmail.contains('@')) {
      throw UploadException('A valid client email is required');
    }

    final existingInvite = await clientForInviteEmail(inviteEmail);
    if (existingInvite != null && existingInvite.id != client.id) {
      throw UploadException('A client with this email already exists');
    }

    if (trimmed != client.name && client.driveFolderId.isNotEmpty) {
      await UploadService.instance.renameClientWorkspace(
        folderId: client.driveFolderId,
        name: trimmed,
      );
    }

    await _clients.doc(client.id).set({
      'name': trimmed,
      'invite_email': inviteEmail,
      'storage_limit_bytes': limit,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> attachUser({
    required ClientWorkspace client,
    required String uid,
  }) async {
    if (uid.isEmpty) {
      throw UploadException('Select a user to attach');
    }

    final profileRef = _firestore.collection('profiles').doc(uid);
    final profile = await profileRef.get();
    if (!profile.exists) {
      throw UploadException('That user was not found');
    }

    final previousClientId =
        (profile.data()?['client_id'] as String?)?.trim() ?? '';
    final batch = _firestore.batch();

    if (previousClientId.isNotEmpty && previousClientId != client.id) {
      batch.set(
        _clients.doc(previousClientId),
        {
          'member_uids': FieldValue.arrayRemove([uid]),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    final members = {...client.memberUids, uid};
    batch.set(
      _clients.doc(client.id),
      {
        'owner_uid': client.ownerUid.isEmpty ? uid : client.ownerUid,
        'member_uids': members.toList(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      profileRef,
      {
        'role': AuthService.clientRole,
        'client_id': client.id,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> detachUser({
    required ClientWorkspace client,
    required String uid,
  }) async {
    if (uid.isEmpty) return;

    final batch = _firestore.batch();
    final nextOwner = client.ownerUid == uid
        ? client.memberUids.firstWhere((id) => id != uid, orElse: () => '')
        : client.ownerUid;
    batch.set(
      _clients.doc(client.id),
      {
        'owner_uid': nextOwner,
        'member_uids': FieldValue.arrayRemove([uid]),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _firestore.collection('profiles').doc(uid),
      {
        'role': 'student',
        'client_id': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> deleteClient(ClientWorkspace client) async {
    if (client.driveFolderId.isNotEmpty) {
      await UploadService.instance.deleteClientWorkspace(client.driveFolderId);
    }

    final members = {...client.memberUids};
    if (client.ownerUid.isNotEmpty) members.add(client.ownerUid);

    final batch = _firestore.batch();
    for (final uid in members) {
      batch.set(
        _firestore.collection('profiles').doc(uid),
        {
          'role': 'student',
          'client_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    batch.delete(_clients.doc(client.id));
    await batch.commit();
  }
}

class ClientRecentFolder {
  final String folderId;
  final String name;
  final DateTime openedAt;

  const ClientRecentFolder({
    required this.folderId,
    required this.name,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'folderId': folderId,
        'name': name,
        'openedAt': openedAt.toIso8601String(),
      };

  factory ClientRecentFolder.fromJson(Map<String, dynamic> json) {
    return ClientRecentFolder(
      folderId: json['folderId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Folder',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ClientRecentFolders {
  static String _key(String clientId) => 'client_recent_folders_$clientId';

  static Future<List<ClientRecentFolder>> load(String clientId) async {
    if (clientId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(clientId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ClientRecentFolder.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.folderId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> record({
    required String clientId,
    required String folderId,
    required String name,
  }) async {
    if (clientId.isEmpty || folderId.isEmpty) return;
    final current = await load(clientId);
    final next = [
      ClientRecentFolder(
        folderId: folderId,
        name: name,
        openedAt: DateTime.now(),
      ),
      ...current.where((item) => item.folderId != folderId),
    ].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(clientId),
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }
}
