/// Single source of truth for the installed APK label.
///
/// Bump this when shipping. Must match the Drive APK file name without `.apk`
/// (example Drive file: `Edupal v8.10.apk`).
///
/// Kept as a getter (not `const` / not a cached field) so each read evaluates
/// the latest source after hot reload. [AppUpdateGate] also re-checks on
/// hot reload via [State.reassemble].
String get appApkLabel => 'Edupal v6.10';

String get appAboutMessage =>
    'Your Academic Companion. Edupal helps you organize and access your study '
    'materials seamlessly. Created and maintained by David Muigai.';
