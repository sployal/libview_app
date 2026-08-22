import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';
import 'upload_service.dart';

class Course {
  final String id;
  final String name;
  final int years;
  final String sampleAdmissionNumber;
  final String admissionPrefix;
  final String driveFolderId;
  final Map<String, Map<String, String>> semesters;

  const Course({
    required this.id,
    required this.name,
    required this.years,
    required this.sampleAdmissionNumber,
    required this.admissionPrefix,
    required this.driveFolderId,
    required this.semesters,
  });

  String get driveFolderTargetId {
    if (driveFolderId.isNotEmpty) return driveFolderId;
    for (final semester in semesters.values) {
      final id = semester['folderId'] ?? '';
      if (id.isNotEmpty) return id;
    }
    return '';
  }

  List<Map<String, dynamic>> get yearGroups {
    return List.generate(years, (index) {
      final year = index + 1;
      return {
        'year': 'Year $year',
        'semesters': [
          {'name': 'Semester 1', 'key': semesterKey(year, 1)},
          {'name': 'Semester 2', 'key': semesterKey(year, 2)},
        ],
      };
    });
  }

  /// Firestore document ID, matching Engineering (`engineering`).
  static String documentIdFromName(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  static String semesterKey(int year, int sem) => 'year${year}_sem$sem';

  static String driveFolderName(int year, int sem) => 'year $year sem $sem';

  static String displayName(int year, int sem) =>
      'Year $year - Semester $sem';

  static String admissionPrefixFromSample(String sample) {
    final trimmed = sample.trim().toUpperCase();
    if (trimmed.isEmpty) return '';

    var end = trimmed.length;
    final slash = trimmed.indexOf('/');
    final backslash = trimmed.indexOf(r'\');
    if (slash >= 0) end = slash;
    if (backslash >= 0 && backslash < end) end = backslash;

    return trimmed.substring(0, end).trim();
  }

  /// Last segment after the last `/` or `\`, e.g. `21` in `EB24/56171/21`.
  static String classSuffixFromSample(String sample) {
    final trimmed = sample.trim().toUpperCase();
    if (trimmed.isEmpty) return '';

    var start = -1;
    final slash = trimmed.lastIndexOf('/');
    final backslash = trimmed.lastIndexOf(r'\');
    if (slash > start) start = slash;
    if (backslash > start) start = backslash;
    if (start < 0 || start >= trimmed.length - 1) return '';

    return trimmed.substring(start + 1).trim();
  }

  /// Same course prefix and same class-year suffix, e.g. both `EB24/.../21`.
  static bool isSameClass(String registrationA, String registrationB) {
    final prefixA = admissionPrefixFromSample(registrationA);
    final prefixB = admissionPrefixFromSample(registrationB);
    final suffixA = classSuffixFromSample(registrationA);
    final suffixB = classSuffixFromSample(registrationB);
    if (prefixA.isEmpty || prefixB.isEmpty) return false;
    if (suffixA.isEmpty || suffixB.isEmpty) return false;
    return prefixA == prefixB && suffixA == suffixB;
  }

  factory Course.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawSemesters = data['semesters'];
    final semesters = <String, Map<String, String>>{};
    if (rawSemesters is Map) {
      rawSemesters.forEach((key, value) {
        if (value is Map) {
          semesters[key.toString()] = {
            'folderId': value['folderId']?.toString() ?? '',
            'name': value['name']?.toString() ?? key.toString(),
            'driveName': value['driveName']?.toString() ?? '',
          };
        }
      });
    }

    final sampleAdmissionNumber =
        (data['sample_admission_number'] as String?) ?? '';
    final storedPrefix = (data['admission_prefix'] as String?) ?? '';
    final fromSample = admissionPrefixFromSample(sampleAdmissionNumber);

    return Course(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? 'Course',
      years: (data['years'] as num?)?.toInt() ?? 0,
      sampleAdmissionNumber: sampleAdmissionNumber,
      admissionPrefix: fromSample.isNotEmpty
          ? fromSample
          : admissionPrefixFromSample(storedPrefix),
      driveFolderId: (data['drive_folder_id'] as String?) ?? '',
      semesters: semesters,
    );
  }

  factory Course.engineeringFallback() {
    const folderIds = {
      'year1_sem1': '15iLkDdDl1-BzH8j-4rKnlfM1yvThv-_b',
      'year1_sem2': '1mdLVxGH4ipBj8qmVhvs-bHbLnLwfcHKy',
      'year2_sem1': '1QfXoPJEVTKpfmuFpohbLK2gNb_aOwpmd',
      'year2_sem2': '1F-BHcmmx4lj3uQ7sV_CRzW0w4BuVDUgx',
      'year3_sem1': '1y35rFcrodvV6ck_nUO69Iv8z3jGCg5On',
      'year3_sem2': '1ji3Y3bfhmUVumLE1dSGIrEW872olipsU',
      'year4_sem1': '1wAPEQZR8s7TUSCE0ejaKCm79m8LjpAJ9',
      'year4_sem2': '1-S7crcf-aIusfxvUcoC4xglw1c6x_ead',
      'year5_sem1': '13Lp2vVZlbcfASu9CMxFIk8IgbC41yO5k',
      'year5_sem2': '1P1FTWqjLCq_4U9lH-xkGNjUv-kR7v6nj',
    };

    final semesters = <String, Map<String, String>>{};
    for (var year = 1; year <= 5; year++) {
      for (var sem = 1; sem <= 2; sem++) {
        final key = semesterKey(year, sem);
        semesters[key] = {
          'folderId': folderIds[key] ?? '',
          'name': displayName(year, sem),
          'driveName': driveFolderName(year, sem),
        };
      }
    }

    return Course(
      id: 'engineering',
      name: 'Engineering',
      years: 5,
      sampleAdmissionNumber: 'EB24/46271/20',
      admissionPrefix: 'EB24',
      driveFolderId: '',
      semesters: semesters,
    );
  }
}

class CourseService {
  CourseService._();

  static final CourseService instance = CourseService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  Future<List<Course>> listCourses() async {
    try {
      await seedEngineeringIfNeeded();
    } catch (_) {
      // Students may not be allowed to write the seed document.
    }
    final snapshot = await _courses.get();
    return snapshot.docs.map(Course.fromDoc).toList();
  }

  Future<void> seedEngineeringIfNeeded() async {
    final existingDoc = await _courses.doc('engineering').get();
    if (existingDoc.exists) return;

    final existing = await _courses
        .where('admission_prefix', whereIn: ['EB', 'EB24'])
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;

    final fallback = Course.engineeringFallback();
    await _courses.doc('engineering').set({
      'name': fallback.name,
      'years': fallback.years,
      'sample_admission_number': fallback.sampleAdmissionNumber,
      'admission_prefix': fallback.admissionPrefix,
      'drive_folder_id': fallback.driveFolderId,
      'semesters': fallback.semesters,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Course> courseForCurrentUser() async {
    final courses = await listCourses();
    final uid = AuthService.instance.currentUser?.uid;
    String registrationNumber = '';

    if (uid != null) {
      final profile = await _firestore.collection('profiles').doc(uid).get();
      registrationNumber =
          (profile.data()?['registration_number'] as String?) ?? '';
    }

    final matched = matchCourse(registrationNumber, courses);
    if (matched != null) return matched;

    for (final course in courses) {
      if (course.id == 'engineering' || course.admissionPrefix == 'EB24') {
        return course;
      }
    }
    return Course.engineeringFallback();
  }

  Course? matchCourse(String registrationNumber, List<Course> courses) {
    final segment = Course.admissionPrefixFromSample(registrationNumber);
    if (segment.isEmpty) return null;

    for (final course in courses) {
      final prefix = Course.admissionPrefixFromSample(
        course.admissionPrefix.isNotEmpty
            ? course.admissionPrefix
            : course.sampleAdmissionNumber,
      );
      if (prefix.isEmpty) continue;
      if (segment == prefix) return course;
    }
    return null;
  }

  Future<Course> createCourse({
    required String name,
    required int years,
    required String sampleAdmissionNumber,
  }) async {
    final courseName = name.trim();
    final sample = sampleAdmissionNumber.trim();
    final prefix = Course.admissionPrefixFromSample(sample);

    if (courseName.isEmpty) {
      throw UploadException('Course name is required');
    }
    if (years < 1 || years > 10) {
      throw UploadException('Number of years must be between 1 and 10');
    }
    if (sample.isEmpty) {
      throw UploadException('Sample admission number is required');
    }
    if (prefix.isEmpty) {
      throw UploadException(
        'Sample admission number must start with a course code before the first /',
      );
    }

    await seedEngineeringIfNeeded();

    final existing = await listCourses();
    final nameTaken = existing.any(
      (course) => course.name.toLowerCase() == courseName.toLowerCase(),
    );
    if (nameTaken) {
      throw UploadException('A course with this name already exists');
    }
    final prefixTaken = existing.any((course) => course.admissionPrefix == prefix);
    if (prefixTaken) {
      throw UploadException(
        'A course already uses admission code "$prefix"',
      );
    }

    final docId = Course.documentIdFromName(courseName);
    if (docId.isEmpty) {
      throw UploadException(
        'Course name must include letters or numbers so it can be stored in the database',
      );
    }
    if (existing.any((course) => course.id == docId)) {
      throw UploadException('A course with this name already exists');
    }
    final existingDoc = await _courses.doc(docId).get();
    if (existingDoc.exists) {
      throw UploadException('A course with this name already exists');
    }

    final structure = await UploadService.instance.createCourseStructure(
      courseName: courseName,
      years: years,
    );

    final semesters = <String, Map<String, String>>{};
    structure.semesters.forEach((key, value) {
      semesters[key] = {
        'folderId': value.folderId,
        'name': value.name,
        'driveName': value.driveName,
      };
    });

    final payload = {
      'name': courseName,
      'years': years,
      'sample_admission_number': sample,
      'admission_prefix': prefix,
      'drive_folder_id': structure.courseFolderId,
      'semesters': semesters,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'created_by': FirebaseAuth.instance.currentUser?.uid,
    };

    await _courses.doc(docId).set(payload);
    return Course(
      id: docId,
      name: courseName,
      years: years,
      sampleAdmissionNumber: sample,
      admissionPrefix: prefix,
      driveFolderId: structure.courseFolderId,
      semesters: semesters,
    );
  }

  Future<Course> updateCourse({
    required Course course,
    required String name,
    required int years,
    required String sampleAdmissionNumber,
  }) async {
    final courseName = name.trim();
    final sample = sampleAdmissionNumber.trim();
    final prefix = Course.admissionPrefixFromSample(sample);

    if (courseName.isEmpty) {
      throw UploadException('Course name is required');
    }
    if (years < 1 || years > 10) {
      throw UploadException('Number of years must be between 1 and 10');
    }
    if (sample.isEmpty) {
      throw UploadException('Sample admission number is required');
    }
    if (prefix.isEmpty) {
      throw UploadException(
        'Sample admission number must start with a course code before the first /',
      );
    }

    final existing = await listCourses();
    final nameTaken = existing.any(
      (other) =>
          other.id != course.id &&
          other.name.toLowerCase() == courseName.toLowerCase(),
    );
    if (nameTaken) {
      throw UploadException('A course with this name already exists');
    }
    final prefixTaken = existing.any(
      (other) => other.id != course.id && other.admissionPrefix == prefix,
    );
    if (prefixTaken) {
      throw UploadException(
        'A course already uses admission code "$prefix"',
      );
    }

    final driveTargetId = course.driveFolderTargetId;
    if (driveTargetId.isNotEmpty &&
        course.name.trim().toLowerCase() != courseName.toLowerCase()) {
      await UploadService.instance.renameCourseFolder(
        folderId: driveTargetId,
        name: courseName,
      );
    }

    final semesters = Map<String, Map<String, String>>.from(course.semesters);
    for (var year = 1; year <= years; year++) {
      for (var sem = 1; sem <= 2; sem++) {
        final key = Course.semesterKey(year, sem);
        semesters.putIfAbsent(
          key,
          () => {
            'folderId': '',
            'name': Course.displayName(year, sem),
            'driveName': Course.driveFolderName(year, sem),
          },
        );
      }
    }

    await _courses.doc(course.id).update({
      'name': courseName,
      'years': years,
      'sample_admission_number': sample,
      'admission_prefix': prefix,
      'semesters': semesters,
      'updated_at': FieldValue.serverTimestamp(),
    });

    return Course(
      id: course.id,
      name: courseName,
      years: years,
      sampleAdmissionNumber: sample,
      admissionPrefix: prefix,
      driveFolderId: course.driveFolderId,
      semesters: semesters,
    );
  }

  List<Map<String, dynamic>> profilesForCourse(
    Course course,
    List<Map<String, dynamic>> profiles, {
    List<Course>? courses,
  }) {
    final allCourses = courses ?? [course];
    return profiles.where((profile) {
      final registration =
          profile['registration_number']?.toString() ?? '';
      final matched = matchCourse(registration, allCourses);
      return matched?.id == course.id;
    }).toList();
  }

  Future<int> deleteCourse({
    required Course course,
    bool deleteAssociatedUsers = false,
  }) async {
    var deletedUsers = 0;

    final driveTargetId = course.driveFolderTargetId;
    if (driveTargetId.isNotEmpty) {
      await UploadService.instance.deleteCourseFolder(driveTargetId);
    }

    if (deleteAssociatedUsers) {
      final courses = await listCourses();
      final snapshot = await _firestore.collection('profiles').get();
      final profiles = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      final associated = profilesForCourse(course, profiles, courses: courses);
      for (final profile in associated) {
        final id = profile['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _firestore.collection('profiles').doc(id).delete();
        deletedUsers++;
      }
    }

    await _courses.doc(course.id).delete();
    return deletedUsers;
  }
}
