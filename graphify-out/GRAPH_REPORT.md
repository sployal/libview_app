# Graph Report - libview  (2026-09-16)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 3556 nodes · 4896 edges · 115 communities (95 shown, 20 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8f46643a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- client_files_browser_screen.dart
- semester_detail_screen.dart
- system_admin_dashboard.dart
- system_admin_analytics.dart
- home_screen.dart
- analytics_service.dart
- upload_service.dart
- createAnalytics
- downloads_screen.dart
- MainActivity
- auth_screen.dart
- server.js
- semesters_screen.dart
- download_service.dart
- google_drive_service.dart
- main.dart
- phone_audio.dart
- browse_documents.dart
- notifications_screen.dart
- ai_screen.dart
- weather_service.dart
- phone_pdf.dart
- client_workspace_screen.dart
- profile_screen.dart
- auth_service.dart
- GeneratedPluginRegistrant.swift
- file_details.dart
- course_service.dart
- client_service.dart
- phone_document_service.dart
- edit_profile.dart
- State
- StatelessWidget
- notification_service.dart
- create_notification_screen.dart
- web_view_screen.dart
- OfficeThumbnailRenderer
- media_player_screen.dart
- todo_service.dart
- folder_lock_dialog.dart
- app_update_screen.dart
- class_members.dart
- course_members.dart
- document_reader.dart
- app_update_service.dart
- app_splash_screen.dart
- file_sort.dart
- subject_detail_screen.dart
- my_application.cc
- ai_conversation_store.dart
- users_feedback.dart
- support_service.dart
- help_and_support.dart
- client_editor_dialog.dart
- onboarding_screen.dart
- course_addition.dart
- streak_service.dart
- move_file_dialog.dart
- drive_thumbnail.dart
- notification_image_viewer.dart
- List
- media_service.dart
- FlutterWindow
- adaptive_layout.dart
- ai_service.dart
- static const
- Win32Window
- applyDriveOAuthTokens
- resolveClientWorkspaceId
- win32_window.cpp
- Create
- wWinMain
- ensureCourseStructure
- contact.js
- package:flutter/services.dart
- manifest.json
- package:flutter/foundation.dart
- MaterialPageRoute
- package:flutter/cupertino.dart
- fileNamesClash
- ai_chat.js
- package:cloud_firestore/cloud_firestore.dart
- media server.js
- sanitizeFileName
- Point
- IconData
- ChangeNotifier
- ensureEnvSystemAdminRole
- package:flutter/material.dart
- collectDriveStorage
- CustomPainter
- dart:io
- Exception
- String get
- RegisterPlugins
- _KeepAliveState
- _ResetPasswordDialog
- _NestedNavigatorObserver
- OnboardingGate
- AiScreen
- _ClientFilesHome
- _DownloadPreview
- DownloadsScreen
- SwitchMainTabNotification
- NotificationsScreen
- ProfileScreen
- SemesterDetailScreen
- SystemAdminAnalyticsScreen
- @example
- bool?
- String?

## God Nodes (most connected - your core abstractions)
1. `createAnalytics()` - 66 edges
2. `MainActivity` - 61 edges
3. `OfficeThumbnailRenderer` - 30 edges
4. `buildAnalytics()` - 27 edges
5. `Win32Window` - 24 edges
6. `recordUsage()` - 15 edges
7. `num()` - 12 edges
8. `MessageHandler` - 12 edges
9. `classifyFile()` - 11 edges
10. `mergeAiStats()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `OnCreate` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.h → windows/flutter/generated_plugin_registrant.cc
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h
- `MessageHandler` --references--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h

## Import Cycles
- None detected.

## Communities (115 total, 20 thin omitted)

### Community 0 - "client_files_browser_screen.dart"
Cohesion: 0.01
Nodes (236): actions, _applyFolderRename, _applyListedItemAction, _applyUnitFolderAction, awaitingServer, _backToSubjects, beginFile, build (+228 more)

### Community 1 - "semester_detail_screen.dart"
Cohesion: 0.01
Nodes (170): BuildContext?, CancelToken?, _applyFolderRename, awaitingServer, _backToSubjects, beginFile, build, _buildDetailsFileList (+162 more)

### Community 2 - "system_admin_dashboard.dart"
Cohesion: 0.01
Nodes (148): client_editor_dialog.dart, course_addition.dart, _allowNewAccounts, _allRoles, _applyLocalRoleChange, _associatedProfiles, _bg, build (+140 more)

### Community 3 - "system_admin_analytics.dart"
Cohesion: 0.02
Nodes (121): class, Color get, _accent, _activityCard, _activitySpots, _aiAnalysisCard, _aiOwnerSubtitle, _alignMonth (+113 more)

### Community 4 - "home_screen.dart"
Cohesion: 0.02
Nodes (107): browse_documents.dart, dart:math, _addTodo, _bootstrapHome, build, _buildCalendar, _buildCalendarDay, _buildHeader (+99 more)

### Community 5 - "analytics_service.dart"
Cohesion: 0.02
Nodes (86): int get, activeUsers, activeUsersByCourse, activeUsersByRole, ai, AnalyticsAiOwner, AnalyticsAiStats, AnalyticsAiUsage (+78 more)

### Community 6 - "upload_service.dart"
Cohesion: 0.02
Nodes (81): DateTime? get, accountEmail, accountName, authHeaders, baseUrl, _buildMultipart, bytes, cached (+73 more)

### Community 7 - "createAnalytics"
Cohesion: 0.07
Nodes (75): AUDIO_EXT, createAnalytics(), addAiStats(), addBucket(), addCountFields(), addExtractedAi(), admissionPrefix(), aggregateAiMap() (+67 more)

### Community 8 - "downloads_screen.dart"
Cohesion: 0.03
Nodes (74): _accent, _accentDeep, _barAction, build, _buildGridTile, _buildIntro, _buildListTile, _clearSelection (+66 more)

### Community 9 - "MainActivity"
Cohesion: 0.07
Nodes (12): Bitmap, MainActivity, BitmapFactory, Color, ExifInterface, File?, FlutterActivity, FlutterEngine (+4 more)

### Community 10 - "auth_screen.dart"
Cohesion: 0.03
Nodes (66): _accent, _accentDeep, _admissionNumberController, _blockIncompleteNewAccountIfRestricted, _blue, _bluePath, build, _buildGoogleButton (+58 more)

### Community 11 - "server.js"
Cohesion: 0.03
Nodes (45): admin, ADMIN_UIDS, analytics, app, clientResolveCache, clientWorkspaceIds, CONFIG, cors (+37 more)

### Community 12 - "semesters_screen.dart"
Cohesion: 0.03
Nodes (61): accent, _adminCoursePrefKey, _allCourses, build, _closeSemester, _continueLastSemester, _course, courses (+53 more)

### Community 13 - "download_service.dart"
Cohesion: 0.03
Nodes (58): analytics_service.dart, baseUrl, cancelDownload, cancelled, _cancelledResult, _cancelTokens, clearAllDownloads, contentUri (+50 more)

### Community 14 - "google_drive_service.dart"
Cohesion: 0.03
Nodes (58): androidNameKey, baseUrl, bytes, code, color, copyWith, countFolderContents, countFoldersInFolder (+50 more)

### Community 15 - "main.dart"
Cohesion: 0.03
Nodes (57): Animation, dart:ui, firebase_options.dart, GlobalKey, accent, _animationController, _authTab, build (+49 more)

### Community 16 - "phone_audio.dart"
Cohesion: 0.03
Nodes (57): actionLabel, _browseWithPicker, build, _buildGrid, _buildList, _cardDecoration, _clearSelection, _colorFor (+49 more)

### Community 17 - "browse_documents.dart"
Cohesion: 0.04
Nodes (55): document_reader.dart, actionLabel, _browseWithPicker, build, _buildDetailsList, _buildLargeIconsGrid, _clearSelection, color (+47 more)

### Community 18 - "notifications_screen.dart"
Cohesion: 0.04
Nodes (54): create_notification_screen.dart, _accent, _audienceLabel, build, _buildCourseFilterBar, _buildEmptyState, _buildFilterChip, _buildNotificationRow (+46 more)

### Community 19 - "ai_screen.dart"
Cohesion: 0.04
Nodes (54): accent, _browseFiles, build, _buildChatPane, _buildSidebar, _ChatBubble, _confirmDelete, _controller (+46 more)

### Community 20 - "weather_service.dart"
Cohesion: 0.04
Nodes (54): cachedWeather, _cacheSnapshot, city, _cityKey, condition, country, _countryKey, currentWeather (+46 more)

### Community 21 - "phone_pdf.dart"
Cohesion: 0.04
Nodes (52): actionLabel, _browseWithPicker, build, _buildDetailsList, _buildLargeIconsGrid, _clearSelection, color, _colorFor (+44 more)

### Community 22 - "client_workspace_screen.dart"
Cohesion: 0.04
Nodes (51): client_files_browser_screen.dart, ClientWorkspace get, _accent, _actionChip, _actionsRow, _amber, build, _clearRecents (+43 more)

### Community 23 - "profile_screen.dart"
Cohesion: 0.04
Nodes (48): class_members.dart, course_members.dart, downloads_screen.dart, edit_profile.dart, help_and_support.dart, aboutMessage, _admissionNumber, _appearanceRow (+40 more)

### Community 24 - "auth_service.dart"
Cohesion: 0.04
Nodes (48): client_service.dart, DocumentReference, GoogleSignIn, _accountCreationDoc, AccountCreationSettings, allowNewAccounts, _auth, authErrorMessage (+40 more)

### Community 25 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (36): Any, cloud_firestore, Cocoa, device_info_plus, file_picker, file_selector_macos, firebase_auth, firebase_core (+28 more)

### Community 26 - "file_details.dart"
Cohesion: 0.04
Nodes (46): file_sort.dart, accent, accentColor, background, build, color, copyable, createdAt (+38 more)

### Community 27 - "course_service.dart"
Cohesion: 0.04
Nodes (46): admissionDigitCount, admissionDigitLayoutError, admissionNumberPattern, admissionPrefix, admissionPrefixFromSample, admissionSegments, classSuffixFromSample, courseForCurrentUser (+38 more)

### Community 28 - "client_service.dart"
Cohesion: 0.04
Nodes (44): claimInvite, clear, clientForInviteEmail, clientForUid, ClientRecentFolder, ClientRecentFolders, _clients, ClientService (+36 more)

### Community 29 - "phone_document_service.dart"
Cohesion: 0.04
Nodes (44): audioUploadMimeTypes, _channel, copyToReadablePath, deleteDocuments, documentUploadMimeTypes, fromFile, fromMap, hasAllFilesAccess (+36 more)

### Community 30 - "edit_profile.dart"
Cohesion: 0.05
Nodes (42): _accent, _admissionNumber, _avatarPreview, _avatarPublicId, _avatarUrlController, _buildReadOnlyField, _confirmAvatarPreview, _confirmDiscardIfNeeded (+34 more)

### Community 31 - "State"
Cohesion: 0.08
Nodes (41): _FolderNameDialog, AuthScreen, _AuthScreenState, MainScreen, _MainScreenState, AppUpdateGate, _AppUpdateGateState, BrowseDocumentsScreen (+33 more)

### Community 32 - "StatelessWidget"
Cohesion: 0.05
Nodes (41): ColoredGoogleIcon, _AppBottomNav, AuthGate, _NavItem, StudyApp, _Composer, _EmptyState, _FolderGlyph (+33 more)

### Community 33 - "notification_service.dart"
Cohesion: 0.05
Nodes (39): auth_service.dart, CollectionReference, course_service.dart, admissionPrefix, AppNotification, audience, classSuffix, copyWith (+31 more)

### Community 34 - "create_notification_screen.dart"
Cohesion: 0.05
Nodes (39): _accent, _audience, _bottomContentInset, build, _buildAudienceOption, _chip, _classLabel, _courseName (+31 more)

### Community 35 - "web_view_screen.dart"
Cohesion: 0.05
Nodes (38): _activeDownloadFileId, _bottomNavInset, build, _cancelDownload, _controller, _convertToPreviewUrl, createState, _darkBg (+30 more)

### Community 36 - "OfficeThumbnailRenderer"
Cohesion: 0.21
Nodes (8): Bitmap, OfficeThumbnailRenderer, Xfrm, Canvas, RectF, TextPaint, XmlPullParser, ZipFile

### Community 37 - "media_player_screen.dart"
Cohesion: 0.06
Nodes (36): _audioBody, _bottomNavInset, build, _cacheForPlayback, _cancelDownload, _controller, _controlsOverlay, createState (+28 more)

### Community 38 - "todo_service.dart"
Cohesion: 0.06
Nodes (35): add, all, copyWith, createdAtMs, dateKey, _decodeTodos, done, forDate (+27 more)

### Community 39 - "folder_lock_dialog.dart"
Cohesion: 0.06
Nodes (32): AnimationController, FocusNode, accent, build, _confirm, controller, createState, dispose (+24 more)

### Community 40 - "app_update_screen.dart"
Cohesion: 0.06
Nodes (31): dart:async, _apkFile, AppUpdateScreen, _AppUpdateScreenState, _authSub, build, _busy, _checkForUpdate (+23 more)

### Community 41 - "class_members.dart"
Cohesion: 0.06
Nodes (31): _accent, _admissionNumber, _applyFilters, _avatar, build, _classLabel, ClassMembersScreen, _ClassMembersScreenState (+23 more)

### Community 42 - "course_members.dart"
Cohesion: 0.06
Nodes (31): _accent, _applyFilters, _assignableRoles, _avatar, build, CourseMembersScreen, _CourseMembersScreenState, _courseName (+23 more)

### Community 43 - "document_reader.dart"
Cohesion: 0.07
Nodes (29): build, _buildBody, canOpenInApp, createState, DocumentReaderScreen, _DocumentReaderScreenState, _error, _ErrorState (+21 more)

### Community 44 - "app_update_service.dart"
Cohesion: 0.07
Nodes (28): ../app_version.dart, google_drive_service.dart, _int, _apkMime, _apkNamePattern, AppUpdateRelease, AppUpdateService, compareVersions (+20 more)

### Community 45 - "app_splash_screen.dart"
Cohesion: 0.07
Nodes (28): double?, double get, AppSplashScreen, _awaitingHome, build, child, complete, completeIfAwaitingHome (+20 more)

### Community 46 - "file_sort.dart"
Cohesion: 0.07
Nodes (28): build, card, FileSort, FileSortKind, FileSortMode, FileSortModeX, FileSortSheet, fromStorage (+20 more)

### Community 47 - "subject_detail_screen.dart"
Cohesion: 0.07
Nodes (27): build, _confirmDelete, createState, _deleteMaterial, _deletingIds, errorMessage, folderId, _getFileColor (+19 more)

### Community 48 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 49 - "ai_conversation_store.dart"
Cohesion: 0.08
Nodes (25): ai_service.dart, AiConversation, AiConversationStore, AiConversationSummary, _conversationDir, delete, fromJson, id (+17 more)

### Community 50 - "users_feedback.dart"
Cohesion: 0.08
Nodes (25): build, card, _checkingAccess, createState, _danger, _deleteMessage, divider, _FeedbackCard (+17 more)

### Community 51 - "support_service.dart"
Cohesion: 0.08
Nodes (24): DateTime, _collection, createdAt, deleteMessage, description, _firestore, fromDoc, heading (+16 more)

### Community 52 - "help_and_support.dart"
Cohesion: 0.08
Nodes (24): FormState, _accent, build, createState, _danger, _descriptionController, dispose, _formKey (+16 more)

### Community 53 - "client_editor_dialog.dart"
Cohesion: 0.08
Nodes (24): build, _chip, client, _ClientEditorDialog, _ClientEditorDialogState, ClientEditorResult, createState, _custom (+16 more)

### Community 54 - "onboarding_screen.dart"
Cohesion: 0.09
Nodes (23): bool get, accent, _accentDeep, build, createState, dispose, _goNext, icon (+15 more)

### Community 55 - "course_addition.dart"
Cohesion: 0.09
Nodes (23): _accent, _admissionController, build, _buildTextField, course, CourseAdditionScreen, _CourseAdditionScreenState, createState (+15 more)

### Community 56 - "streak_service.dart"
Cohesion: 0.10
Nodes (20): FirebaseAuth, FirebaseFirestore, _auth, _cache, _cached, cachedStreak, currentStreak, dateKey (+12 more)

### Community 57 - "move_file_dialog.dart"
Cohesion: 0.10
Nodes (19): _accent, background, build, fileName, _FolderTile, _Header, id, isFolder (+11 more)

### Community 58 - "drive_thumbnail.dart"
Cohesion: 0.12
Nodes (17): BoxFit, Future, build, createState, didUpdateWidget, DriveThumbnail, _DriveThumbnailState, fallback (+9 more)

### Community 59 - "notification_image_viewer.dart"
Cohesion: 0.12
Nodes (17): build, createState, dispose, _doubleTapDetails, _fileName, heroTag, imageUrl, NotificationImageViewer (+9 more)

### Community 60 - "List"
Cohesion: 0.12
Nodes (17): allowedRoles, build, _checkVisibility, child, createState, fallback, getCurrentUserRole, hasAnyRole (+9 more)

### Community 61 - "media_service.dart"
Cohesion: 0.12
Nodes (16): Dio, deleteImage, _dio, folderNotifications, folderProfiles, folderSupport, instance, MediaService (+8 more)

### Community 62 - "FlutterWindow"
Cohesion: 0.12
Nodes (14): FlutterViewController, unique_ptr, DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM (+6 more)

### Community 63 - "adaptive_layout.dart"
Cohesion: 0.12
Nodes (16): actions, AdaptiveLayout, automaticallyImplyLeading, backgroundColor, bottomClearance, compactSliverAppBar, false, foregroundColor (+8 more)

### Community 64 - "ai_service.dart"
Cohesion: 0.12
Nodes (15): dart:convert, dart:typed_data, AiService, ChatMessage, _dio, imageBytes, imageMime, instance (+7 more)

### Community 65 - "static const"
Cohesion: 0.13
Nodes (14): followsSystem, _fromName, instance, labelFor, load, _mode, _prefsKey, setMode (+6 more)

### Community 66 - "Win32Window"
Cohesion: 0.20
Nodes (14): RECT, OnCreate, OnDestroy, HWND, Win32Window, child_content_, GetClientArea, OnCreate (+6 more)

### Community 67 - "applyDriveOAuthTokens"
Cohesion: 0.19
Nodes (13): applyDriveOAuthTokens(), fetchAuthorizedDriveEmail(), firestoreTimeToIso(), firestoreTimeToMs(), initDriveAuth(), loadClientWorkspaceIdsFromFirestore(), loadOAuthStatus(), loadRefreshToken() (+5 more)

### Community 68 - "resolveClientWorkspaceId"
Cohesion: 0.26
Nodes (13): assertLockableClientFolder(), clientWorkspaceAllowsUser(), isClientWorkspaceFolder(), isCourseFolderUnderEdupal(), isManagedFromParents(), isManagedItem(), isSemesterFolder(), isValidCreateParent() (+5 more)

### Community 69 - "win32_window.cpp"
Cohesion: 0.32
Nodes (11): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+3 more)

### Community 70 - "Create"
Cohesion: 0.19
Nodes (11): wchar_t, Scale(), Create, Destroy, Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, GetWindowClass (+3 more)

### Community 71 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 72 - "ensureCourseStructure"
Cohesion: 0.27
Nodes (12): createClientWorkspaceFolder(), createCourseStructure(), driveIsConfigured(), ensureClientsRootFolder(), ensureCourseStructure(), ensureUpdatesFolder(), findOrCreateNamedFolder(), listChildFolders() (+4 more)

### Community 73 - "contact.js"
Cohesion: 0.31
Nodes (10): clientIp(), contactToEmail(), encodeSubject(), escapeHtml(), gmailRawMessage(), { google }, isRateLimited(), recentByIp (+2 more)

### Community 74 - "package:flutter/services.dart"
Cohesion: 0.20
Nodes (10): build, _checking, createState, ensureOnline, NoInternetScreen, _NoInternetScreenState, routeName, _tryAgain (+2 more)

### Community 75 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 76 - "package:flutter/foundation.dart"
Cohesion: 0.20
Nodes (9): android, DefaultFirebaseOptions, ios, macos, web, windows, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart (+1 more)

### Community 77 - "MaterialPageRoute"
Cohesion: 0.20
Nodes (10): build, _buildRecentsHeader, _buildShortcuts, _openNotifications, _openCreateNotification, _openImage, _openOnlinePage, _showStorageUsage (+2 more)

### Community 78 - "package:flutter/cupertino.dart"
Cohesion: 0.22
Nodes (9): build, createState, message, _signingOut, _signOut, SuspendedAccountScreen, _SuspendedAccountScreenState, title (+1 more)

### Community 79 - "fileNamesClash"
Cohesion: 0.24
Nodes (10): androidNameKey(), childNamesClash(), fileNamesClash(), folderNamesClash(), isFolderInside(), keysMatch(), listChildItems(), moveItem() (+2 more)

### Community 80 - "ai_chat.js"
Cohesion: 0.43
Nodes (7): axios, extractReply(), extractUsage(), isClientUser(), lastUserMessageHasImage(), registerAiRoutes(), toNvidiaMessages()

### Community 81 - "package:cloud_firestore/cloud_firestore.dart"
Cohesion: 0.25
Nodes (7): client_workspace_screen.dart, DocumentSnapshot, build, MaterialsTabScreen, package:cloud_firestore/cloud_firestore.dart, semesters_screen.dart, services/auth_service.dart

### Community 82 - "media server.js"
Cohesion: 0.54
Nodes (7): cloudinaryConfigured(), configureCloudinary(), deleteProfileAvatar(), destroyEdupalImage(), profileAvatarPublicId(), registerMediaRoutes(), uploadBuffer()

### Community 83 - "sanitizeFileName"
Cohesion: 0.25
Nodes (8): contentDispositionAttachment(), createFolder(), mimeFromFileName(), parseDriveDateTime(), { Readable }, renameItem(), sanitizeFileName(), uploadFile()

### Community 84 - "Point"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 85 - "IconData"
Cohesion: 0.29
Nodes (6): IconData, build, destructive, icon, PreviewOverlayIcon, size

### Community 86 - "ChangeNotifier"
Cohesion: 0.33
Nodes (6): ChangeNotifier, _UploadProgressSession, _UploadProgressSession, ThemeController, TodoService, StartupOverlay

### Community 87 - "ensureEnvSystemAdminRole"
Cohesion: 0.33
Nodes (6): ensureEnvSystemAdminRole(), isConfiguredSystemAdminEmail(), isSystemAdminUser(), promoteEnvSystemAdminOnStartup(), requireAuth(), requireSystemAdmin()

### Community 88 - "package:flutter/material.dart"
Cohesion: 0.40
Nodes (4): package:flutter/material.dart, package:flutter_test/flutter_test.dart, package:uni_study_app/main.dart, main

### Community 89 - "collectDriveStorage"
Cohesion: 0.50
Nodes (5): assertClientStorageAllows(), collectDriveStorage(), countFolderContents(), listDirectChildren(), sumFolderBytes()

### Community 90 - "CustomPainter"
Cohesion: 0.50
Nodes (4): CustomPainter, _GoogleLogoPainter, _StreakRingPainter, _TodoProgressPainter

### Community 91 - "dart:io"
Cohesion: 0.50
Nodes (3): dart:io, ConnectivityService, hasInternet

### Community 92 - "Exception"
Cohesion: 0.50
Nodes (4): Exception, AnalyticsException, UploadCancelledException, UploadException

### Community 93 - "String get"
Cohesion: 0.50
Nodes (3): appAboutMessage, appApkLabel, String get

### Community 95 - "_KeepAliveState"
Cohesion: 0.67
Nodes (3): AutomaticKeepAliveClientMixin, _KeepAlive, _KeepAliveState

## Knowledge Gaps
- **2631 isolated node(s):** `actions`, `_applyFolderRename`, `_applyListedItemAction`, `_applyUnitFolderAction`, `awaitingServer` (+2626 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 2795 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `FileSortMode` connect `file_sort.dart` to `client_files_browser_screen.dart`, `semester_detail_screen.dart`, `downloads_screen.dart`, `phone_audio.dart`, `browse_documents.dart`, `phone_pdf.dart`, `client_workspace_screen.dart`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `createAnalytics()` (e.g. with `analytics.js` and `clientPlatform()`) actually correct?**
  _`createAnalytics()` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `actions`, `_applyFolderRename`, `_applyListedItemAction` to the rest of the system?**
  _2631 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `client_files_browser_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.008438818565400843 - nodes in this community are weakly interconnected._
- **Should `semester_detail_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.011695906432748537 - nodes in this community are weakly interconnected._
- **Should `system_admin_dashboard.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.013422818791946308 - nodes in this community are weakly interconnected._
- **Should `system_admin_analytics.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01639344262295082 - nodes in this community are weakly interconnected._