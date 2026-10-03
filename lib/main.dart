import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const ChunkyCatBudgApp());
}

const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

class ChunkyCatBudgApp extends StatelessWidget {
  const ChunkyCatBudgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chunky Cat Budget',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A8C),
          primary: const Color(0xFF1F7A8C),
          secondary: const Color(0xFFE07A5F),
          tertiary: const Color(0xFF3D405B),
          surface: const Color(0xFFF8F9FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE4E7EC)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          isDense: true,
        ),
      ),
      home: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: const BudgetHome(),
      ),
    );
  }
}

class BudgetApi {
  int? activeProfileId;

  Uri _uri(String path) {
    var resolvedPath = path;
    if (_usesActiveProfile(path) &&
        activeProfileId != null &&
        !path.contains('profile_id=')) {
      resolvedPath =
          '$path${path.contains('?') ? '&' : '?'}profile_id=$activeProfileId';
    }
    if (apiBaseUrl.isNotEmpty) {
      return Uri.parse('$apiBaseUrl$resolvedPath');
    }
    return Uri.base.resolve(
      resolvedPath.startsWith('/') ? resolvedPath.substring(1) : resolvedPath,
    );
  }

  bool _usesActiveProfile(String path) {
    return path.startsWith('/api/dashboard/') ||
        path == '/api/accounts' ||
        path.startsWith('/api/accounts/') ||
        path == '/api/paycheck-profile' ||
        path.startsWith('/api/paycheck-profiles') ||
        path == '/api/chunks' ||
        path.startsWith('/api/chunks/') ||
        path.startsWith('/api/paychecks') ||
        path == '/api/money-movements' ||
        path == '/api/transactions';
  }

  Future<dynamic> get(String path) async {
    final response = await http.get(_uri(path));
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await http.put(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await http.delete(_uri(path));
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 400) {
          throw ApiException(_apiErrorMessage(null, response.body));
        }
        throw ApiException('The server returned an invalid response.');
      }
    }
    if (response.statusCode >= 400) {
      final message = _apiErrorMessage(body, response.body);
      throw ApiException(message);
    }
    return body;
  }

  String _apiErrorMessage(dynamic body, String fallback) {
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
      }
      return detail.toString();
    }
    return fallback.isEmpty ? 'Something went wrong.' : fallback;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return error.toString();
}

class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.buildNumber,
    required this.commit,
    required this.buildTime,
  });

  final String version;
  final String buildNumber;
  final String commit;
  final String buildTime;

  factory BuildInfo.fromJson(Map<String, dynamic> json) {
    return BuildInfo(
      version: json['version']?.toString() ?? 'unknown',
      buildNumber: json['buildNumber']?.toString() ?? '',
      commit: json['commit']?.toString() ?? 'unknown',
      buildTime: json['buildTime']?.toString() ?? 'unknown',
    );
  }

  String get shortCommit {
    if (commit.length <= 7) return commit;
    return commit.substring(0, 7);
  }

  String get formattedBuildTime {
    final parsed = DateTime.tryParse(buildTime);
    if (parsed == null) return buildTime;
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toUtc());
  }
}

Future<BuildInfo> loadBuildInfo() async {
  final uri = Uri.base.resolve(
    'version.json?v=${DateTime.now().millisecondsSinceEpoch}',
  );
  final response = await http.get(
    uri,
    headers: const {'Cache-Control': 'no-cache'},
  );
  if (response.statusCode >= 400) {
    throw ApiException('Build information unavailable');
  }
  return BuildInfo.fromJson(
    Map<String, dynamic>.from(jsonDecode(response.body) as Map),
  );
}

final Future<BuildInfo> appBuildInfo = loadBuildInfo();

class BudgetHome extends StatefulWidget {
  const BudgetHome({super.key});

  @override
  State<BudgetHome> createState() => _BudgetHomeState();
}

class _BudgetHomeState extends State<BudgetHome> {
  final api = BudgetApi();
  var selected = 0;
  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? selectedProfile;
  Map<String, dynamic>? summaryData;
  Future<Map<String, dynamic>>? summaryFuture;

  final screens = const [
    ('Dashboard', Icons.dashboard_outlined),
    ('Budget Overview', Icons.fact_check_outlined),
    ('Add Paycheck', Icons.add_circle_outline),
    ('Accounts', Icons.account_balance_wallet_outlined),
    ('Chunks', Icons.savings_outlined),
    ('Transfers', Icons.swap_horiz_outlined),
    ('Paycheck Setup', Icons.payments_outlined),
    ('Settings', Icons.settings_outlined),
  ];

  Future<Map<String, dynamic>> _loadSummary() async {
    final data = Map<String, dynamic>.from(
      await api.get('/api/dashboard/summary'),
    );
    if (mounted) setState(() => summaryData = data);
    return data;
  }

  void refresh() {
    setState(() => summaryFuture = _loadSummary());
  }

  void signIn(Map<String, dynamic> user) {
    setState(() {
      currentUser = user;
      selectedProfile = null;
      api.activeProfileId = null;
      selected = 0;
      summaryData = null;
      summaryFuture = null;
    });
  }

  void selectProfile(Map<String, dynamic> profile) {
    setState(() {
      selectedProfile = profile;
      api.activeProfileId = profile['id'] as int;
      selected = 0;
      summaryData = null;
      summaryFuture = _loadSummary();
    });
  }

  void chooseAnotherProfile() {
    setState(() {
      selectedProfile = null;
      api.activeProfileId = null;
      selected = 0;
      summaryData = null;
      summaryFuture = null;
    });
  }

  void signOut() {
    setState(() {
      currentUser = null;
      selectedProfile = null;
      api.activeProfileId = null;
      selected = 0;
      summaryData = null;
      summaryFuture = null;
    });
  }

  void openScreen(int index) {
    setState(() => selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    if (user == null) {
      return AuthGateway(api: api, onSignedIn: signIn);
    }
    final profile = selectedProfile;
    if (profile == null) {
      return ProfileSelectionScreen(
        api: api,
        user: user,
        onProfileSelected: selectProfile,
        onSignOut: signOut,
      );
    }
    final canEdit = profile['role'] == 'admin';

    return FutureBuilder<Map<String, dynamic>>(
      future: summaryFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? summaryData;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting && data == null;
        final error = data == null ? snapshot.error : null;
        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 860;
            final child = isLoading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? _ErrorView(message: error.toString(), onRetry: refresh)
                : _ScreenHost(
                    selected: selected,
                    data: data ?? const {},
                    api: api,
                    refresh: refresh,
                    goTo: openScreen,
                    canEdit: canEdit,
                    selectedProfile: profile,
                  );

            if (isDesktop) {
              return _DesktopShell(
                screens: screens,
                selected: selected,
                onSelect: openScreen,
                user: user,
                profile: profile,
                onChangeProfile: chooseAnotherProfile,
                onSignOut: signOut,
                child: child,
              );
            }
            return _PhoneShell(
              selected: selected,
              onSelect: openScreen,
              user: user,
              profile: profile,
              onChangeProfile: chooseAnotherProfile,
              onSignOut: signOut,
              child: child,
            );
          },
        );
      },
    );
  }
}

class AuthGateway extends StatefulWidget {
  const AuthGateway({super.key, required this.api, required this.onSignedIn});
  final BudgetApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<AuthGateway> createState() => _AuthGatewayState();
}

class _AuthGatewayState extends State<AuthGateway> {
  var createAccount = false;

  @override
  Widget build(BuildContext context) {
    if (createAccount) {
      return CreateAccountScreen(
        api: widget.api,
        onCreated: widget.onSignedIn,
        onSignIn: () => setState(() => createAccount = false),
      );
    }
    return LoginScreen(
      api: widget.api,
      onSignedIn: widget.onSignedIn,
      onCreateAccount: () => setState(() => createAccount = true),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
    required this.onCreateAccount,
  });
  final BudgetApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;
  final VoidCallback onCreateAccount;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  var signingIn = false;
  var submitted = false;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isPhone ? 18 : 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(isPhone ? 18 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Chunky Cat Budget',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sign in to choose or manage budget profiles.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 22),
                      AutofillGroup(
                        child: Column(
                          children: [
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Email',
                                errorText:
                                    submitted && email.text.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: password,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) {
                                if (!signingIn) _signIn();
                              },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                errorText: submitted && password.text.isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: signingIn ? null : _signIn,
                          icon: signingIn
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: const Text('Sign In'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: widget.onCreateAccount,
                        child: const Text('Create an account'),
                      ),
                      const SizedBox(height: 18),
                      const BuildInfoText(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => submitted = true);
    if (email.text.trim().isEmpty || password.text.isEmpty) return;
    setState(() => signingIn = true);
    try {
      final user = Map<String, dynamic>.from(
        await widget.api.post('/api/login', {
          'email': email.text.trim(),
          'password': password.text,
        }),
      );
      widget.onSignedIn(user);
    } catch (error) {
      if (!mounted) return;
      final message = errorMessage(error);
      toast(
        context,
        message == 'Invalid email or password'
            ? 'Incorrect email or password.'
            : message,
      );
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.api,
    required this.onCreated,
    required this.onSignIn,
  });
  final BudgetApi api;
  final ValueChanged<Map<String, dynamic>> onCreated;
  final VoidCallback onSignIn;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final email = TextEditingController();
  final displayName = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  var creating = false;
  var submitted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Email verification will be enabled when an email provider is configured.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: displayName,
                        decoration: InputDecoration(
                          labelText: 'Display name',
                          errorText:
                              submitted && displayName.text.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          errorText: submitted && email.text.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          errorText: submitted && password.text.isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPassword,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          errorText: submitted && confirmPassword.text.isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: creating ? null : _create,
                          icon: creating
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add),
                          label: const Text('Create Account'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: widget.onSignIn,
                        child: const Text('Back to sign in'),
                      ),
                      const SizedBox(height: 18),
                      const BuildInfoText(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    setState(() => submitted = true);
    if (displayName.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.isEmpty ||
        confirmPassword.text.isEmpty) {
      return;
    }
    if (password.text != confirmPassword.text) {
      toast(context, 'Passwords do not match');
      return;
    }
    setState(() => creating = true);
    try {
      final user = Map<String, dynamic>.from(
        await widget.api.post('/api/register', {
          'email': email.text.trim(),
          'display_name': displayName.text.trim(),
          'password': password.text,
        }),
      );
      widget.onCreated(user);
    } catch (error) {
      if (!mounted) return;
      final message = errorMessage(error);
      toast(
        context,
        message == 'An account with this email already exists'
            ? 'This email is already associated with an account. Sign in instead.'
            : message,
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }
}

class BuildInfoText extends StatelessWidget {
  const BuildInfoText({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BuildInfo>(
      future: appBuildInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const Text(
            'ChunkyCat build loading',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
          );
        }
        final versionSuffix = info.buildNumber.isEmpty
            ? ''
            : '+${info.buildNumber}';
        return Text(
          'ChunkyCat v${info.version}$versionSuffix\nBuild ${info.shortCommit}\n${info.formattedBuildTime} UTC',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            height: 1.35,
          ),
        );
      },
    );
  }
}

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onProfileSelected,
    required this.onSignOut,
  });

  final BudgetApi api;
  final Map<String, dynamic> user;
  final ValueChanged<Map<String, dynamic>> onProfileSelected;
  final VoidCallback onSignOut;

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> profileData =
      _loadProfileData();
  final profileName = TextEditingController();
  final selectedProfileIds = <int>{};
  var creating = false;
  var acceptingInvitationId = 0;
  var selectionMode = false;

  Future<Map<String, List<Map<String, dynamic>>>> _loadProfileData() async {
    final profiles = listOfMaps(
      await widget.api.get('/api/budget-profiles?user_id=${widget.user['id']}'),
    );
    final invitations = listOfMaps(
      await widget.api.get(
        '/api/invitations?email=${Uri.encodeComponent(widget.user['email'].toString())}',
      ),
    ).where((invitation) => invitation['status'] == 'pending').toList();
    return {'profiles': profiles, 'invitations': invitations};
  }

  void reload() {
    setState(() => profileData = _loadProfileData());
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget Profiles'),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              selectionMode = !selectionMode;
              selectedProfileIds.clear();
            }),
            tooltip: selectionMode ? 'Done selecting' : 'Select profiles',
            icon: Icon(selectionMode ? Icons.check : Icons.checklist),
          ),
          if (selectionMode)
            IconButton(
              onPressed: selectedProfileIds.isEmpty
                  ? null
                  : _deleteSelectedProfiles,
              tooltip: 'Delete selected profiles',
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            onPressed: widget.onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
          future: profileData,
          builder: (context, snapshot) {
            final rows = snapshot.data?['profiles'] ?? [];
            final invitations = snapshot.data?['invitations'] ?? [];
            return ListView(
              padding: EdgeInsets.all(isPhone ? 14 : 22),
              children: [
                Text(
                  widget.user['email']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                _SectionTitle('Profiles You Can Access'),
                Card(
                  child: rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            snapshot.connectionState == ConnectionState.waiting
                                ? 'Loading profiles'
                                : 'No profiles yet',
                            style: const TextStyle(color: Color(0xFF667085)),
                          ),
                        )
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length,
                          onReorder: (oldIndex, newIndex) =>
                              _reorderProfiles(rows, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final profile = rows[index];
                            final id = profile['id'] as int;
                            final isAdmin = profile['role'] == 'admin';
                            return ListTile(
                              key: ValueKey('profile-$id'),
                              leading: selectionMode
                                  ? Checkbox(
                                      value: selectedProfileIds.contains(id),
                                      onChanged: (checked) => setState(() {
                                        if (checked ?? false) {
                                          selectedProfileIds.add(id);
                                        } else {
                                          selectedProfileIds.remove(id);
                                        }
                                      }),
                                    )
                                  : Icon(
                                      isAdmin
                                          ? Icons.admin_panel_settings_outlined
                                          : Icons.visibility_outlined,
                                    ),
                              title: Text(
                                profile['name'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                isAdmin ? 'Admin access' : 'Read only access',
                              ),
                              trailing: selectionMode
                                  ? const Icon(Icons.drag_handle)
                                  : const Icon(Icons.chevron_right),
                              onTap: selectionMode
                                  ? () => setState(() {
                                      if (selectedProfileIds.contains(id)) {
                                        selectedProfileIds.remove(id);
                                      } else {
                                        selectedProfileIds.add(id);
                                      }
                                    })
                                  : () => widget.onProfileSelected(profile),
                            );
                          },
                        ),
                ),
                if (invitations.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Pending Invitations'),
                  _DataCard(
                    emptyText: 'No pending invitations',
                    children: invitations.map((invitation) {
                      final id = invitation['id'] as int;
                      return ListTile(
                        leading: const Icon(Icons.mail_outline),
                        title: Text(
                          invitation['email'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          invitation['role'] == 'admin'
                              ? 'Admin invitation'
                              : 'Read only invitation',
                        ),
                        trailing: FilledButton(
                          onPressed: acceptingInvitationId == id
                              ? null
                              : () => _acceptInvitation(id),
                          child: Text(
                            acceptingInvitationId == id
                                ? 'Accepting'
                                : 'Accept',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 20),
                _SectionTitle('Create Profile'),
                _SettingsCard(
                  children: [
                    TextField(
                      controller: profileName,
                      decoration: const InputDecoration(
                        labelText: 'Profile name',
                      ),
                    ),
                    _SubmitButton(
                      saving: creating,
                      label: 'Create Profile',
                      onPressed: _createProfile,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _createProfile() async {
    setState(() => creating = true);
    try {
      await widget.api.post('/api/budget-profiles', {
        'name': profileName.text,
        'owner_user_id': widget.user['id'],
      });
      profileName.clear();
      reload();
      if (!mounted) return;
      toast(context, 'Profile created');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> _acceptInvitation(int invitationId) async {
    setState(() => acceptingInvitationId = invitationId);
    try {
      await widget.api.post('/api/invitations/$invitationId/accept', {
        'user_id': widget.user['id'],
      });
      reload();
      if (!mounted) return;
      toast(context, 'Invitation accepted');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => acceptingInvitationId = 0);
    }
  }

  Future<void> _reorderProfiles(
    List<Map<String, dynamic>> rows,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...rows];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    try {
      await widget.api.put('/api/budget-profiles/reorder', {
        'user_id': widget.user['id'],
        'profile_ids': reordered.map((profile) => profile['id']).toList(),
      });
      reload();
    } catch (error) {
      if (mounted) toast(context, error.toString());
    }
  }

  Future<void> _deleteSelectedProfiles() async {
    final count = selectedProfileIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profiles'),
        content: Text(
          'Delete $count selected profile${count == 1 ? '' : 's'}? This permanently deletes each profile and all accounts, chunks, paychecks, transfers, and transactions inside it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final id in selectedProfileIds.toList()) {
        await widget.api.delete('/api/budget-profiles/$id');
      }
      setState(() {
        selectedProfileIds.clear();
        selectionMode = false;
      });
      reload();
      if (mounted) toast(context, 'Profiles deleted');
    } catch (error) {
      if (mounted) toast(context, error.toString());
    }
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.screens,
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.profile,
    required this.onChangeProfile,
    required this.onSignOut,
    required this.child,
  });

  final List<(String, IconData)> screens;
  final int selected;
  final ValueChanged<int> onSelect;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final VoidCallback onChangeProfile;
  final VoidCallback onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(screens: screens, selected: selected, onSelect: onSelect),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _SignedInBar(
                    user: user,
                    profile: profile,
                    onChangeProfile: onChangeProfile,
                    onSignOut: onSignOut,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.profile,
    required this.onChangeProfile,
    required this.onSignOut,
    required this.child,
  });

  static const routes = [0, 1, 5, 4, 8];

  final int selected;
  final ValueChanged<int> onSelect;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final VoidCallback onChangeProfile;
  final VoidCallback onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final navIndex = routes.contains(selected)
        ? routes.indexOf(selected)
        : routes.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile['name']?.toString() ?? 'Budget'),
        actions: [
          IconButton(
            onPressed: onChangeProfile,
            tooltip: 'Switch profile',
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            onPressed: onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (index) => onSelect(routes[index]),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Transfer',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Chunks',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu_open),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _SignedInBar extends StatelessWidget {
  const _SignedInBar({
    required this.user,
    required this.profile,
    required this.onChangeProfile,
    required this.onSignOut,
  });
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final VoidCallback onChangeProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile['name']?.toString() ?? 'Budget',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${user['email']}  |  ${profile['role'] == 'admin' ? 'Admin' : 'Read only'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onChangeProfile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Switch'),
          ),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.screens,
    required this.selected,
    required this.onSelect,
  });
  final List<(String, IconData)> screens;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final settingsIndex = screens.indexWhere(
      (screen) => screen.$1 == 'Settings',
    );
    final primaryIndexes = [
      for (var index = 0; index < screens.length; index++)
        if (index != settingsIndex) index,
    ];
    return Container(
      width: 236,
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Text(
                'ChunkyCat Budget',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: primaryIndexes.length,
                itemBuilder: (context, listIndex) =>
                    _sidebarTile(context, primaryIndexes[listIndex]),
              ),
            ),
            if (settingsIndex >= 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _sidebarTile(context, settingsIndex),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarTile(BuildContext context, int index) {
    final item = screens[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child:
          NavigationDrawerDestination(
            icon: Icon(item.$2),
            label: Text(item.$1),
            selectedIcon: Icon(item.$2),
          ).buildListTile(
            context,
            selected: selected == index,
            onTap: () => onSelect(index),
          ),
    );
  }
}

extension on NavigationDrawerDestination {
  Widget buildListTile(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: .11)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: icon,
        title: label,
        selected: selected,
        selectedColor: colors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
      ),
    );
  }
}

class _ScreenHost extends StatelessWidget {
  const _ScreenHost({
    required this.selected,
    required this.data,
    required this.api,
    required this.refresh,
    required this.goTo,
    required this.canEdit,
    required this.selectedProfile,
  });

  final int selected;
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final ValueChanged<int> goTo;
  final bool canEdit;
  final Map<String, dynamic> selectedProfile;

  @override
  Widget build(BuildContext context) {
    return switch (selected) {
      0 => DashboardScreen(
        data: data,
        api: api,
        refresh: refresh,
        goTo: goTo,
        canEdit: canEdit,
      ),
      1 => BudgetOverviewScreen(data: data),
      2 => AddPaycheckScreen(
        data: data,
        api: api,
        refresh: refresh,
        canEdit: canEdit,
      ),
      3 => AccountsScreen(
        data: data,
        api: api,
        refresh: refresh,
        canEdit: canEdit,
      ),
      4 => ChunksScreen(
        data: data,
        api: api,
        refresh: refresh,
        canEdit: canEdit,
      ),
      5 => TransfersScreen(
        data: data,
        api: api,
        refresh: refresh,
        canEdit: canEdit,
      ),
      6 => PaycheckSetupScreen(
        data: data,
        api: api,
        refresh: refresh,
        canEdit: canEdit,
      ),
      8 => MobileMoreScreen(goTo: goTo),
      _ => SettingsScreen(
        api: api,
        selectedProfile: selectedProfile,
        canEdit: canEdit,
      ),
    };
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.goTo,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final ValueChanged<int> goTo;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final totals = Map<String, dynamic>.from(data['totals'] ?? {});
    final accounts = List<Map<String, dynamic>>.from(
      (data['accounts'] ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final chunks = List<Map<String, dynamic>>.from(
      (data['chunks'] ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final movements = List<Map<String, dynamic>>.from(
      (data['recent_money_movements'] ?? []).map(
        (e) => Map<String, dynamic>.from(e),
      ),
    );
    final paychecks = listOfMaps(data['recent_paychecks']);

    return _Page(
      title: 'Dashboard',
      actions: [
        IconButton(
          onPressed: refresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _ResponsiveGrid(
            minWidth: 210,
            children: [
              _MetricCard(
                label: 'Account Balance',
                value: money(totals['account_balance']),
                icon: Icons.account_balance_wallet_outlined,
              ),
              _MetricCard(
                label: 'Allocated',
                value: money(totals['allocated_balance']),
                icon: Icons.savings_outlined,
              ),
              _MetricCard(
                label: 'Unallocated',
                value: money(totals['unallocated_balance']),
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (canEdit) _DashboardActions(isPhone: isPhone, goTo: goTo),
          const SizedBox(height: 20),
          _SectionTitle('Accounts'),
          _DataCard(
            emptyText: 'No accounts yet',
            children: accounts.map((a) {
              return _ListRow(
                title: a['name'].toString(),
                subtitle:
                    'Allocated ${money(a['allocated_balance'])}  |  Unallocated ${money(a['unallocated_balance'])}',
                trailing: money(a['balance']),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Chunks'),
          const _ChunkListHeader(
            description: "Chunk's Account | Amount Per Paycheck",
            amountLabel: 'Current Balance',
          ),
          _DataCard(
            emptyText: 'No chunks yet',
            children: chunks.map((c) {
              return _ListRow(
                title: c['name'].toString(),
                subtitle:
                    '${c['account_name']}  |  ${money(c['amount_per_paycheck'])} per paycheck',
                trailing: money(c['balance']),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Paychecks'),
          _DataCard(
            emptyText: 'No paychecks added',
            children: paychecks.map((paycheck) {
              return _ListRow(
                title:
                    paycheck['paycheck_profile_name']?.toString() ?? 'Paycheck',
                subtitle: paycheck['is_reverted'] == true
                    ? 'Reverted ${formatDateTime(paycheck['reverted_at'])}'
                    : formatDateTime(paycheck['created_at']),
                trailing: money(paycheck['net_amount']),
                onTap: () => showPaycheckDetails(
                  context,
                  paycheck,
                  api,
                  refresh,
                  canEdit,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Recent Transfers'),
          _DataCard(
            emptyText: 'No transfers logged',
            children: movements.map((m) {
              return _ListRow(
                title: m['movement_type'] == 'purchase_transaction'
                    ? '${m['source_type']} purchase/transaction'
                    : '${m['source_type']} to ${m['destination_type']}',
                subtitle: m['note'].toString().isEmpty
                    ? formatDateTime(m['created_at'])
                    : m['note'].toString(),
                trailing: money(m['amount']),
                onTap: () => showTransferDetails(context, m, accounts, chunks),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DashboardActions extends StatelessWidget {
  const _DashboardActions({required this.isPhone, required this.goTo});
  final bool isPhone;
  final ValueChanged<int> goTo;

  @override
  Widget build(BuildContext context) {
    if (!isPhone) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: () => goTo(2),
            icon: const Icon(Icons.add),
            label: const Text('Add Paycheck'),
          ),
          OutlinedButton.icon(
            onPressed: () => goTo(5),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Add Transfer'),
          ),
          OutlinedButton.icon(
            onPressed: () => goTo(3),
            icon: const Icon(Icons.add_card),
            label: const Text('Account'),
          ),
          OutlinedButton.icon(
            onPressed: () => goTo(4),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Chunk'),
          ),
          OutlinedButton.icon(
            onPressed: () => goTo(1),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Overview'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => goTo(2),
            icon: const Icon(Icons.add),
            label: const Text('Add Paycheck'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => goTo(5),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Add Transfer'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => goTo(1),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Overview'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => goTo(3),
                  icon: const Icon(Icons.add_card),
                  label: const Text('Account'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => goTo(4),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Chunk'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class BudgetOverviewScreen extends StatelessWidget {
  const BudgetOverviewScreen({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final profiles = listOfMaps(data['paycheck_profiles']);
    final chunks = listOfMaps(data['chunks']);
    final activeChunks = chunks
        .where((chunk) => chunk['is_active'] != false)
        .toList();
    final expectedPay = profiles.fold<double>(
      0,
      (total, profile) =>
          total + parseMoney('${profile['net_pay_amount'] ?? 0}'),
    );
    final chunkTotal = activeChunks.fold<double>(
      0,
      (total, chunk) =>
          total + parseMoney('${chunk['amount_per_paycheck'] ?? 0}'),
    );
    final leftover = expectedPay - chunkTotal;

    return _Page(
      title: 'Budget Overview',
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _Notice(
            expectedPay <= 0
                ? 'Set your expected net pay in Paycheck Setup to compare paycheck income against chunk deductions.'
                : 'Expected paycheck minus every active chunk deduction shows the leftover unallocated amount for each paycheck.',
          ),
          const SizedBox(height: 16),
          _ResponsiveGrid(
            minWidth: 210,
            children: [
              _MetricCard(
                label: 'Expected Paycheck',
                value: money(expectedPay),
                icon: Icons.payments_outlined,
              ),
              _MetricCard(
                label: 'Chunk Deductions',
                value: money(chunkTotal),
                icon: Icons.savings_outlined,
              ),
              _MetricCard(
                label: 'Leftover',
                value: money(leftover),
                icon: leftover < 0
                    ? Icons.warning_amber_outlined
                    : Icons.inventory_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (leftover < 0)
            const _Notice(
              'Your active chunks are over the expected paycheck amount. Reduce chunk amounts or increase expected pay before using this paycheck plan.',
            ),
          if (leftover < 0) const SizedBox(height: 20),
          _SectionTitle('Paycheck Plan'),
          _DataCard(
            emptyText: 'No paycheck profile yet',
            children: [
              _ListRow(
                title: 'Expected net pay',
                subtitle:
                    '${profiles.length} paycheck profile${profiles.length == 1 ? '' : 's'}',
                trailing: money(expectedPay),
              ),
              _ListRow(
                title: 'Minus active chunks',
                subtitle:
                    '${activeChunks.length} chunk${activeChunks.length == 1 ? '' : 's'}',
                trailing: money(chunkTotal),
              ),
              _ListRow(
                title: leftover < 0 ? 'Over budget' : 'Leftover unallocated',
                subtitle: 'Expected paycheck result',
                trailing: money(leftover),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('Paycheck Profiles'),
          _DataCard(
            emptyText: 'No paycheck profiles yet',
            children: profiles.map((profile) {
              return _ListRow(
                title: profile['name']?.toString() ?? 'Paycheck',
                subtitle: movementLabel(
                  profile['pay_frequency']?.toString() ?? 'custom',
                ),
                trailing: money(profile['net_pay_amount']),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Chunk Deductions'),
          const _ChunkListHeader(
            description: "Chunk's Account",
            amountLabel: 'Amount Per Paycheck',
          ),
          _DataCard(
            emptyText: 'No active chunks yet',
            children: activeChunks.map((chunk) {
              return _ListRow(
                title: chunk['name'].toString(),
                subtitle: chunk['account_name']?.toString() ?? 'Account',
                trailing: money(chunk['amount_per_paycheck']),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class PaycheckSetupScreen extends StatefulWidget {
  const PaycheckSetupScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final bool canEdit;

  @override
  State<PaycheckSetupScreen> createState() => _PaycheckSetupScreenState();
}

class _PaycheckSetupScreenState extends State<PaycheckSetupScreen> {
  final profileName = TextEditingController(text: 'Paycheck');
  final net = TextEditingController();
  var mode = 'expected';
  var frequency = 'biweekly';
  int? selectedPaycheckProfileId;
  int? defaultAccountId;
  var saving = false;
  var submitted = false;

  @override
  void initState() {
    super.initState();
    net.addListener(() => setState(() {}));
    profileName.addListener(() => setState(() {}));
    final profiles = listOfMaps(widget.data['paycheck_profiles']);
    if (profiles.isNotEmpty) _loadProfile(profiles.first);
  }

  @override
  void dispose() {
    profileName.dispose();
    net.dispose();
    super.dispose();
  }

  void _loadProfile(Map<String, dynamic> profile) {
    selectedPaycheckProfileId = profile['id'] as int?;
    profileName.text = profile['name']?.toString() ?? 'Paycheck';
    net.text = '${profile['net_pay_amount'] ?? ''}';
    mode = profile['net_pay_mode']?.toString() ?? mode;
    frequency = profile['pay_frequency']?.toString() ?? frequency;
    defaultAccountId = profile['default_account_id'] as int?;
  }

  void _newProfile() {
    setState(() {
      selectedPaycheckProfileId = null;
      profileName.text = 'Paycheck';
      net.clear();
      mode = 'expected';
      frequency = 'biweekly';
      final accounts = listOfMaps(widget.data['accounts']);
      defaultAccountId = accounts.isNotEmpty
          ? accounts.first['id'] as int
          : null;
      submitted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = listOfMaps(widget.data['paycheck_profiles']);
    final accounts = listOfMaps(widget.data['accounts']);
    defaultAccountId ??= accounts.isNotEmpty
        ? accounts.first['id'] as int
        : null;
    return _Page(
      title: 'Paycheck Setup',
      child: _FormCard(
        children: [
          if (profiles.isNotEmpty)
            _DropdownField<int>(
              label: 'Paycheck profile',
              value: selectedPaycheckProfileId,
              values: profiles.map((profile) => profile['id'] as int).toList(),
              labelFor: (id) => profiles
                  .firstWhere((profile) => profile['id'] == id)['name']
                  .toString(),
              onChanged: (id) {
                final profile = profiles.firstWhere(
                  (profile) => profile['id'] == id,
                );
                setState(() => _loadProfile(profile));
              },
            ),
          TextField(
            controller: profileName,
            decoration: InputDecoration(
              labelText: 'Profile name',
              errorText: submitted && profileName.text.trim().isEmpty
                  ? 'Required'
                  : null,
            ),
          ),
          _MoneyField(
            label: 'Net paycheck amount',
            controller: net,
            errorText: submitted && parseMoney(net.text) <= 0
                ? 'Required'
                : null,
          ),
          _DropdownField(
            label: 'Net pay mode',
            value: mode,
            values: const ['manual', 'expected', 'estimated'],
            labelFor: (value) => switch (value) {
              'manual' => 'Manual exact amount',
              'expected' => 'Expected recurring amount',
              'estimated' => 'Estimated amount',
              _ => value,
            },
            onChanged: (v) => setState(() => mode = v ?? mode),
          ),
          const _BalanceHint(
            text:
                'Net pay mode is a label for how confident this net amount is. Manual is exact, expected is your normal recurring amount, and estimated is a planning placeholder.',
          ),
          _DropdownField(
            label: 'Pay frequency',
            value: frequency,
            values: const [
              'weekly',
              'biweekly',
              'semimonthly',
              'monthly',
              'custom',
            ],
            onChanged: (v) => setState(() => frequency = v ?? frequency),
          ),
          _DropdownField<int>(
            label: 'Default deposit account',
            value: defaultAccountId,
            values: accounts.map((account) => account['id'] as int).toList(),
            labelFor: (id) => accounts
                .firstWhere((account) => account['id'] == id)['name']
                .toString(),
            onChanged: (v) => setState(() => defaultAccountId = v),
            errorText: submitted && defaultAccountId == null
                ? 'Required'
                : null,
          ),
          OutlinedButton.icon(
            onPressed: widget.canEdit ? _newProfile : null,
            icon: const Icon(Icons.add),
            label: const Text('New Paycheck Profile'),
          ),
          if (selectedPaycheckProfileId != null)
            OutlinedButton.icon(
              onPressed: widget.canEdit ? _deleteProfile : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Paycheck Profile'),
            ),
          _SubmitButton(
            saving: saving,
            label: selectedPaycheckProfileId == null
                ? 'Create Profile'
                : 'Save Profile',
            onPressed: widget.canEdit ? _save : null,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => submitted = true);
    if (profileName.text.trim().isEmpty ||
        parseMoney(net.text) <= 0 ||
        defaultAccountId == null) {
      return;
    }
    setState(() => saving = true);
    try {
      final saved = await widget.api.post('/api/paycheck-profile', {
        'id': selectedPaycheckProfileId,
        'name': profileName.text,
        'net_pay_amount': parseMoney(net.text),
        'net_pay_mode': mode,
        'pay_frequency': frequency,
        'default_account_id': defaultAccountId,
      });
      selectedPaycheckProfileId = saved['id'] as int?;
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Paycheck profile saved');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _deleteProfile() async {
    final id = selectedPaycheckProfileId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Paycheck Profile'),
        content: Text(
          'Delete ${profileName.text}? Existing paycheck history will be kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/paycheck-profiles/$id');
      _newProfile();
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Paycheck profile deleted');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    }
  }
}

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final bool canEdit;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final selectedAccountIds = <int>{};
  var selectionMode = false;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final accounts = listOfMaps(widget.data['accounts']);
    return _Page(
      title: 'Accounts',
      actions: widget.canEdit
          ? [
              IconButton(
                onPressed: () => setState(() {
                  selectionMode = !selectionMode;
                  selectedAccountIds.clear();
                }),
                tooltip: selectionMode ? 'Done selecting' : 'Select accounts',
                icon: Icon(selectionMode ? Icons.check : Icons.checklist),
              ),
              if (selectionMode)
                IconButton(
                  onPressed: selectedAccountIds.isEmpty
                      ? null
                      : () => _deleteSelected(accounts),
                  tooltip: 'Delete selected accounts',
                  icon: const Icon(Icons.delete_outline),
                ),
              if (selectionMode)
                IconButton(
                  onPressed: selectedAccountIds.isEmpty
                      ? null
                      : () => _moveChunks(accounts),
                  tooltip: 'Move chunks',
                  icon: const Icon(Icons.drive_file_move_outline),
                ),
              FilledButton.icon(
                onPressed: () =>
                    showAccountDialog(context, widget.api, widget.refresh),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ]
          : [],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          if (widget.canEdit && !selectionMode) ...[
            _AccountCreateCard(api: widget.api, refresh: widget.refresh),
            const SizedBox(height: 18),
          ],
          Card(
            child: accounts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Create a real-world account to hold paycheck money',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: accounts.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorderAccounts(accounts, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final a = accounts[index];
                      final id = a['id'] as int;
                      return ListTile(
                        key: ValueKey('account-$id'),
                        leading: selectionMode
                            ? Checkbox(
                                value: selectedAccountIds.contains(id),
                                onChanged: (checked) => setState(() {
                                  if (checked ?? false) {
                                    selectedAccountIds.add(id);
                                  } else {
                                    selectedAccountIds.remove(id);
                                  }
                                }),
                              )
                            : null,
                        title: Text(
                          a['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${a['type']}  |  ${a['source_mode'] == 'bank_connected' ? 'Bank connected' : 'Manual'}  |  Balance ${money(a['balance'])}  |  Unallocated ${money(a['unallocated_balance'])}',
                        ),
                        onTap: selectionMode
                            ? () => setState(() {
                                if (selectedAccountIds.contains(id)) {
                                  selectedAccountIds.remove(id);
                                } else {
                                  selectedAccountIds.add(id);
                                }
                              })
                            : null,
                        trailing: selectionMode
                            ? const Icon(Icons.drag_handle)
                            : widget.canEdit
                            ? PopupMenuButton<String>(
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    await showAccountDialog(
                                      context,
                                      widget.api,
                                      widget.refresh,
                                      account: a,
                                    );
                                  } else if (action == 'delete') {
                                    await deleteAccount(
                                      context,
                                      widget.api,
                                      widget.refresh,
                                      a,
                                    );
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit account'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete account'),
                                  ),
                                ],
                              )
                            : Text(
                                money(a['balance']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected(List<Map<String, dynamic>> accounts) async {
    final count = selectedAccountIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Accounts'),
        content: Text(
          'Delete $count selected zero-balance account${count == 1 ? '' : 's'}? Cash-flow logs are kept. Accounts with balances or assigned chunks cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final id in selectedAccountIds.toList()) {
        await widget.api.delete('/api/accounts/$id');
      }
      setState(() {
        selectedAccountIds.clear();
        selectionMode = false;
      });
      widget.refresh();
      if (mounted) toast(context, 'Accounts deleted');
    } catch (error) {
      if (mounted) toast(context, error.toString());
    }
  }

  Future<void> _reorderAccounts(
    List<Map<String, dynamic>> accounts,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = [...accounts];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    try {
      await widget.api.put('/api/accounts/reorder', {
        'account_ids': reordered.map((account) => account['id']).toList(),
      });
      widget.refresh();
    } catch (error) {
      if (mounted) toast(context, error.toString());
    }
  }

  Future<void> _moveChunks(List<Map<String, dynamic>> accounts) async {
    if (selectedAccountIds.length != 1) {
      toast(context, 'Select one source account to move chunks');
      return;
    }
    final sourceId = selectedAccountIds.first;
    final destinations = accounts
        .where((account) => account['id'] != sourceId)
        .toList();
    if (destinations.isEmpty) {
      toast(context, 'Create another account first');
      return;
    }
    var destinationId = destinations.first['id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Move Chunks'),
          content: _DropdownField<int>(
            label: 'Destination account',
            value: destinationId,
            values: destinations.map((a) => a['id'] as int).toList(),
            labelFor: (id) => destinations
                .firstWhere((a) => a['id'] == id)['name']
                .toString(),
            onChanged: (value) =>
                setState(() => destinationId = value ?? destinationId),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.post('/api/accounts/$sourceId/move-chunks', {
        'destination_account_id': destinationId,
      });
      setState(() {
        selectedAccountIds.clear();
        selectionMode = false;
      });
      widget.refresh();
      if (mounted) toast(context, 'Chunks moved');
    } catch (error) {
      if (mounted) toast(context, error.toString());
    }
  }
}

class _AccountCreateCard extends StatefulWidget {
  const _AccountCreateCard({required this.api, required this.refresh});
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  State<_AccountCreateCard> createState() => _AccountCreateCardState();
}

class _AccountCreateCardState extends State<_AccountCreateCard> {
  final name = TextEditingController();
  final balance = TextEditingController(text: '0');
  var type = 'checking';
  var sourceMode = 'manual';
  var saving = false;
  var submitted = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create Account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: 'Account name',
                errorText: submitted && name.text.trim().isEmpty
                    ? 'Required'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Type',
              value: type,
              values: const ['checking', 'savings', 'cash', 'other'],
              onChanged: (v) => setState(() => type = v ?? type),
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Balance management',
              value: sourceMode,
              values: const ['manual', 'bank_connected'],
              labelFor: (value) =>
                  value == 'manual' ? 'Manual' : 'Bank connected',
              onChanged: (v) => setState(() => sourceMode = v ?? sourceMode),
            ),
            const SizedBox(height: 12),
            _MoneyField(label: 'Starting balance', controller: balance),
            const SizedBox(height: 12),
            _SubmitButton(
              saving: saving,
              label: 'Add Account',
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => submitted = true);
    if (name.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      await widget.api.post('/api/accounts', {
        'name': name.text,
        'type': type,
        'source_mode': sourceMode,
        'balance': parseMoney(balance.text),
        'is_active': true,
      });
      name.clear();
      balance.text = '0';
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Account created');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class ChunksScreen extends StatefulWidget {
  const ChunksScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final bool canEdit;

  @override
  State<ChunksScreen> createState() => _ChunksScreenState();
}

class _ChunksScreenState extends State<ChunksScreen> {
  final selectedChunkIds = <int>{};
  var selecting = false;
  var sortBy = _ChunkSortBy.account;
  var sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final chunks = listOfMaps(widget.data['chunks'])..sort(_compareChunks);
    final accounts = listOfMaps(widget.data['accounts']);
    final paycheckProfiles = listOfMaps(widget.data['paycheck_profiles']);
    return _Page(
      title: 'Chunks',
      actions: widget.canEdit
          ? [
              IconButton(
                onPressed: () => setState(() {
                  selecting = !selecting;
                  selectedChunkIds.clear();
                }),
                tooltip: selecting ? 'Cancel selection' : 'Select chunks',
                icon: Icon(selecting ? Icons.close : Icons.checklist),
              ),
              if (selecting)
                IconButton(
                  onPressed: selectedChunkIds.isEmpty ? null : _deleteSelected,
                  tooltip: 'Delete selected chunks',
                  icon: const Icon(Icons.delete_outline),
                ),
              FilledButton.icon(
                onPressed: accounts.isEmpty
                    ? null
                    : () => showChunkDialog(
                        context,
                        widget.api,
                        widget.refresh,
                        accounts,
                        paycheckProfiles: paycheckProfiles,
                      ),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ]
          : [],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _ChunkSortBar(
            sortBy: sortBy,
            sortAscending: sortAscending,
            onSortByChanged: (value) => setState(() => sortBy = value),
            onDirectionChanged: () =>
                setState(() => sortAscending = !sortAscending),
          ),
          const SizedBox(height: 12),
          const _ChunkListHeader(
            description:
                "Standard/Loan | Chunk's Account | Paycheck Profile Source | Amount Per Paycheck",
            amountLabel: 'Current Balance',
          ),
          _DataCard(
            emptyText: accounts.isEmpty
                ? 'Create an account before adding chunks'
                : 'Create chunks that apply once per paycheck',
            children: chunks.map((c) {
              final id = c['id'] as int;
              final selected = selectedChunkIds.contains(id);
              final type = c['chunk_type']?.toString() == 'loan'
                  ? 'Loan'
                  : 'Standard';
              final loanText = c['chunk_type']?.toString() == 'loan'
                  ? '  |  Loan balance ${money(c['loan_balance'])}  |  APR ${c['loan_interest_rate'] ?? 0}%'
                  : '';
              final accountText = c['chunk_type']?.toString() == 'loan'
                  ? ''
                  : '  |  ${c['account_name']}';
              final paycheckText = c['paycheck_profile_name'] == null
                  ? '  |  No paycheck assigned'
                  : '  |  ${c['paycheck_profile_name']}';
              return _ListRow(
                wrapSubtitle: true,
                title: selecting
                    ? '${selected ? '✓ ' : ''}${c['name']}'
                    : c['name'].toString(),
                subtitle:
                    '$type$accountText$paycheckText  |  ${money(c['amount_per_paycheck'])} per paycheck$loanText',
                trailing: c['chunk_type']?.toString() == 'loan'
                    ? money(c['loan_balance'])
                    : money(c['balance']),
                onTap: selecting
                    ? () => setState(() {
                        selected
                            ? selectedChunkIds.remove(id)
                            : selectedChunkIds.add(id);
                      })
                    : widget.canEdit
                    ? () => showChunkDialog(
                        context,
                        widget.api,
                        widget.refresh,
                        accounts,
                        paycheckProfiles: paycheckProfiles,
                        chunk: c,
                      )
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  int _compareChunks(Map<String, dynamic> a, Map<String, dynamic> b) {
    final result = switch (sortBy) {
      _ChunkSortBy.account => _compareText(
        a['account_name'],
        b['account_name'],
      ),
      _ChunkSortBy.type => _compareText(a['chunk_type'], b['chunk_type']),
      _ChunkSortBy.amountPerPaycheck => _compareMoney(
        a['amount_per_paycheck'],
        b['amount_per_paycheck'],
      ),
      _ChunkSortBy.paycheck => _compareText(
        a['paycheck_profile_name'] ?? '',
        b['paycheck_profile_name'] ?? '',
      ),
      _ChunkSortBy.currentBalance => _compareMoney(
        _currentChunkBalance(a),
        _currentChunkBalance(b),
      ),
    };
    if (result != 0) return sortAscending ? result : -result;
    return _compareText(a['name'], b['name']);
  }

  double _currentChunkBalance(Map<String, dynamic> chunk) =>
      chunk['chunk_type']?.toString() == 'loan'
      ? parseMoney('${chunk['loan_balance'] ?? 0}')
      : parseMoney('${chunk['balance'] ?? 0}');

  int _compareMoney(Object? a, Object? b) =>
      parseMoney('${a ?? 0}').compareTo(parseMoney('${b ?? 0}'));

  int _compareText(Object? a, Object? b) => (a?.toString().toLowerCase() ?? '')
      .compareTo(b?.toString().toLowerCase() ?? '');

  Future<void> _deleteSelected() async {
    final count = selectedChunkIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chunks'),
        content: Text(
          'Delete $count selected chunk${count == 1 ? '' : 's'}? Chunk balances will return to unallocated money in their account. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final id in selectedChunkIds) {
        await widget.api.delete('/api/chunks/$id');
      }
      selectedChunkIds.clear();
      setState(() => selecting = false);
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Chunks deleted');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    }
  }
}

enum _ChunkSortBy { account, type, amountPerPaycheck, paycheck, currentBalance }

class _ChunkSortBar extends StatelessWidget {
  const _ChunkSortBar({
    required this.sortBy,
    required this.sortAscending,
    required this.onSortByChanged,
    required this.onDirectionChanged,
  });
  final _ChunkSortBy sortBy;
  final bool sortAscending;
  final ValueChanged<_ChunkSortBy> onSortByChanged;
  final VoidCallback onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final field = _DropdownField<_ChunkSortBy>(
      label: 'Sort by',
      value: sortBy,
      values: _ChunkSortBy.values,
      labelFor: _chunkSortLabel,
      onChanged: (value) {
        if (value != null) onSortByChanged(value);
      },
    );
    final direction = IconButton.filledTonal(
      onPressed: onDirectionChanged,
      tooltip: sortAscending ? 'Ascending' : 'Descending',
      icon: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: isPhone
          ? Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 8),
                direction,
              ],
            )
          : Row(
              children: [
                SizedBox(width: 280, child: field),
                const SizedBox(width: 8),
                direction,
              ],
            ),
    );
  }
}

String _chunkSortLabel(_ChunkSortBy value) => switch (value) {
  _ChunkSortBy.account => 'Account',
  _ChunkSortBy.type => 'Loan/Standard',
  _ChunkSortBy.amountPerPaycheck => 'Amount per paycheck',
  _ChunkSortBy.paycheck => 'Paycheck',
  _ChunkSortBy.currentBalance => 'Current balance',
};

class AddPaycheckScreen extends StatefulWidget {
  const AddPaycheckScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final bool canEdit;

  @override
  State<AddPaycheckScreen> createState() => _AddPaycheckScreenState();
}

class _AddPaycheckScreenState extends State<AddPaycheckScreen> {
  var mode = 'expected';
  int? paycheckProfileId;
  int? accountId;
  final custom = TextEditingController();
  var saving = false;
  var submitted = false;

  @override
  void initState() {
    super.initState();
    custom.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = listOfMaps(widget.data['accounts']);
    final profiles = listOfMaps(widget.data['paycheck_profiles']);
    paycheckProfileId ??= profiles.isNotEmpty
        ? profiles.first['id'] as int
        : null;
    final profile = profiles.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == paycheckProfileId,
      orElse: () => null,
    );
    accountId ??=
        profile?['default_account_id'] as int? ??
        (accounts.isNotEmpty ? accounts.first['id'] as int : null);
    final depositAccount = accounts.cast<Map<String, dynamic>?>().firstWhere(
      (account) => account?['id'] == accountId,
      orElse: () => null,
    );
    return _Page(
      title: 'Add Paycheck',
      child: _FormCard(
        children: [
          if (profiles.isEmpty)
            const _Notice(
              'Create a paycheck profile before adding a paycheck.',
            ),
          if (accounts.isEmpty)
            const _Notice('Create an account before adding a paycheck.'),
          _DropdownField<int>(
            label: 'Paycheck profile',
            value: paycheckProfileId,
            values: profiles.map((profile) => profile['id'] as int).toList(),
            labelFor: (id) => profiles
                .firstWhere((profile) => profile['id'] == id)['name']
                .toString(),
            onChanged: (id) {
              final selected = profiles
                  .cast<Map<String, dynamic>?>()
                  .firstWhere(
                    (profile) => profile?['id'] == id,
                    orElse: () => null,
                  );
              setState(() {
                paycheckProfileId = id;
                accountId =
                    selected?['default_account_id'] as int? ??
                    (accounts.isNotEmpty ? accounts.first['id'] as int : null);
              });
            },
            errorText: submitted && paycheckProfileId == null
                ? 'Required'
                : null,
          ),
          if (profile != null)
            _BalanceHint(
              text:
                  'Expected deposit from ${profile['name']}: ${money(profile['net_pay_amount'])}',
            ),
          if (depositAccount != null)
            _BalanceHint(
              text:
                  'Default deposit account: ${depositAccount['name']}. Chunk allocations in other accounts will be moved there automatically.',
            ),
          if (accountId != null && depositAccount == null)
            const _Notice(
              'The paycheck profile default account is inactive. Select an active default account in Paycheck Setup before adding this paycheck.',
            ),
          _DropdownField(
            label: 'Amount',
            value: mode,
            values: const ['expected', 'custom'],
            labelFor: (v) =>
                v == 'expected' ? 'Use expected net pay' : 'Use custom amount',
            onChanged: (v) => setState(() => mode = v ?? mode),
          ),
          if (mode == 'custom')
            _MoneyField(
              label: 'Custom amount',
              controller: custom,
              errorText: submitted && parseMoney(custom.text) <= 0
                  ? 'Required'
                  : null,
            ),
          _SubmitButton(
            saving: saving,
            label: 'Add Paycheck',
            onPressed: widget.canEdit ? _add : null,
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    setState(() => submitted = true);
    final profiles = listOfMaps(widget.data['paycheck_profiles']);
    final profile = profiles.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == paycheckProfileId,
      orElse: () => null,
    );
    final paycheckAmount = mode == 'custom'
        ? parseMoney(custom.text)
        : parseMoney('${profile?['net_pay_amount'] ?? 0}');
    final accountIsActive = listOfMaps(
      widget.data['accounts'],
    ).any((account) => account['id'] == accountId);
    if (profile == null ||
        accountId == null ||
        !accountIsActive ||
        paycheckAmount <= 0) {
      return;
    }

    final eligibleChunks = listOfMaps(widget.data['chunks']).where((chunk) {
      return chunk['is_active'] != false &&
          chunk['paycheck_profile_id'] == paycheckProfileId &&
          parseMoney('${chunk['amount_per_paycheck'] ?? 0}') > 0;
    }).toList();
    final configuredTotal = eligibleChunks.fold<double>(
      0,
      (total, chunk) => total + _paycheckChunkMaximum(chunk),
    );
    List<Map<String, dynamic>>? allocations;
    if (configuredTotal > paycheckAmount) {
      allocations = await _reviewAllocations(eligibleChunks, paycheckAmount);
      if (allocations == null) return;
    }

    setState(() => saving = true);
    try {
      final result = await widget.api.post('/api/paychecks/add', {
        'paycheck_profile_id': paycheckProfileId,
        'amount_mode': mode,
        'custom_amount': mode == 'custom' ? parseMoney(custom.text) : null,
        'account_id': accountId,
        'allocations': allocations,
      });
      widget.refresh();
      if (!mounted) return;
      toast(
        context,
        'Paycheck added. Unallocated: ${money(result['unallocated_amount'])}',
      );
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  double _paycheckChunkMaximum(Map<String, dynamic> chunk) {
    final configured = parseMoney('${chunk['amount_per_paycheck'] ?? 0}');
    if (chunk['chunk_type']?.toString() == 'loan' &&
        chunk['loan_balance'] != null) {
      return configured
          .clamp(0, parseMoney('${chunk['loan_balance']}'))
          .toDouble();
    }
    return configured;
  }

  Future<List<Map<String, dynamic>>?> _reviewAllocations(
    List<Map<String, dynamic>> chunks,
    double paycheckAmount,
  ) async {
    final selected = <int, bool>{};
    final controllers = <int, TextEditingController>{};
    for (final chunk in chunks) {
      final id = chunk['id'] as int;
      selected[id] = true;
      controllers[id] = TextEditingController(
        text: _paycheckChunkMaximum(chunk).toStringAsFixed(2),
      );
    }
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final total = chunks.fold<double>(0, (sum, chunk) {
            final id = chunk['id'] as int;
            return sum +
                (selected[id] == true ? parseMoney(controllers[id]!.text) : 0);
          });
          return AlertDialog(
            title: const Text('Review Paycheck Chunks'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Notice(
                      'This paycheck is less than the configured total for chunks assigned to this paycheck. Deselect chunks or lower one-time amounts before adding it.',
                    ),
                    const SizedBox(height: 12),
                    for (final chunk in chunks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected[chunk['id']] == true,
                              onChanged: (value) => setDialogState(
                                () => selected[chunk['id'] as int] =
                                    value ?? false,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                chunk['chunk_type']?.toString() == 'loan'
                                    ? '${chunk['name']} (Loan)'
                                    : '${chunk['name']} (${chunk['account_name']})',
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: _MoneyField(
                                label: 'This paycheck',
                                controller: controllers[chunk['id'] as int]!,
                                onChanged: (_) => setDialogState(() {}),
                                errorText:
                                    parseMoney(
                                          controllers[chunk['id'] as int]!.text,
                                        ) >
                                        _paycheckChunkMaximum(chunk)
                                    ? 'Too high'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    _BalanceHint(
                      text:
                          'Selected ${money(total)} of ${money(paycheckAmount)} paycheck',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel Paycheck'),
              ),
              FilledButton(
                onPressed:
                    total <= paycheckAmount &&
                        chunks.every(
                          (chunk) =>
                              selected[chunk['id']] != true ||
                              parseMoney(
                                    controllers[chunk['id'] as int]!.text,
                                  ) <=
                                  _paycheckChunkMaximum(chunk),
                        )
                    ? () => Navigator.pop(context, [
                        for (final chunk in chunks)
                          if (selected[chunk['id']] == true)
                            {
                              'chunk_id': chunk['id'],
                              'amount': parseMoney(
                                controllers[chunk['id'] as int]!.text,
                              ),
                            },
                      ])
                    : null,
                child: const Text('Add Paycheck'),
              ),
            ],
          );
        },
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({
    super.key,
    required this.data,
    required this.api,
    required this.refresh,
    required this.canEdit,
  });
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final bool canEdit;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  var movementType = 'allocation';
  var sourceType = 'unallocated';
  var destinationType = 'chunk';
  int? sourceId;
  int? destinationId;
  final amount = TextEditingController();
  final note = TextEditingController();
  var saving = false;
  var submitted = false;

  @override
  void initState() {
    super.initState();
    amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = listOfMaps(widget.data['accounts']);
    final manualAccounts = accounts
        .where((account) => account['source_mode'] != 'bank_connected')
        .toList();
    final chunks = listOfMaps(widget.data['chunks']);
    final sourceChunks = chunks
        .where((chunk) => chunk['chunk_type']?.toString() != 'loan')
        .toList();
    final selectableAccounts = movementType == 'manual_account_transfer'
        ? manualAccounts
        : accounts;
    sourceId ??= sourceType == 'chunk' && sourceChunks.isNotEmpty
        ? sourceChunks.first['id'] as int
        : selectableAccounts.isNotEmpty
        ? selectableAccounts.first['id'] as int
        : null;
    destinationId ??= destinationType == 'chunk' && chunks.isNotEmpty
        ? chunks.first['id'] as int
        : selectableAccounts.isNotEmpty
        ? selectableAccounts.first['id'] as int
        : null;

    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final source = _selectedSource(accounts, sourceChunks);
    final destination = _selectedDestination(accounts, chunks);
    final transferAmount = parseMoney(amount.text);

    final formFields = [
      _DropdownField(
        label: 'Transfer type',
        value: movementType,
        values: const [
          'allocation',
          'manual_account_transfer',
          'purchase_transaction',
        ],
        labelFor: (value) => value == 'allocation'
            ? 'Allocation transfer'
            : value == 'manual_account_transfer'
            ? 'Manual account transfer'
            : 'Purchase/Transaction',
        onChanged: (v) => setState(() {
          movementType = v ?? movementType;
          sourceType = 'unallocated';
          destinationType = movementType == 'manual_account_transfer'
              ? 'unallocated'
              : movementType == 'purchase_transaction'
              ? 'outside_account'
              : 'chunk';
          sourceId = null;
          destinationId = null;
        }),
      ),
      if (movementType == 'manual_account_transfer') ...[
        _EntityDropdown(
          label: 'From manual account',
          type: 'unallocated',
          id: sourceId,
          accounts: manualAccounts,
          chunks: chunks,
          onChanged: (v) => setState(() => sourceId = v),
          errorText: submitted && sourceId == null ? 'Required' : null,
        ),
        if (source != null) _BalanceHint(text: _accountBalanceSummary(source)),
        _EntityDropdown(
          label: 'To manual account',
          type: 'unallocated',
          id: destinationId,
          accounts: manualAccounts,
          chunks: chunks,
          onChanged: (v) => setState(() => destinationId = v),
          errorText: submitted && destinationId == null ? 'Required' : null,
        ),
        if (destination != null)
          _BalanceHint(text: _accountBalanceSummary(destination)),
      ] else ...[
        _DropdownField(
          label: 'From',
          value: sourceType,
          values: const ['chunk', 'unallocated'],
          onChanged: (v) => setState(() {
            sourceType = v ?? sourceType;
            sourceId = null;
          }),
        ),
        _EntityDropdown(
          label: 'Source',
          type: sourceType,
          id: sourceId,
          accounts: accounts,
          chunks: sourceChunks,
          onChanged: (v) => setState(() => sourceId = v),
          errorText: submitted && sourceId == null ? 'Required' : null,
        ),
        if (source != null) _BalanceHint(text: _sourceBalanceSummary(source)),
        if (movementType != 'purchase_transaction') ...[
          _DropdownField(
            label: 'To',
            value: destinationType,
            values: const ['chunk', 'unallocated', 'outside_account'],
            labelFor: movementLabel,
            onChanged: (v) => setState(() {
              destinationType = v ?? destinationType;
              destinationId = null;
            }),
          ),
          if (destinationType != 'outside_account')
            _EntityDropdown(
              label: 'Destination',
              type: destinationType == 'chunk' ? 'chunk' : 'unallocated',
              id: destinationId,
              accounts: accounts,
              chunks: chunks,
              onChanged: (v) => setState(() => destinationId = v),
              errorText: submitted && destinationId == null ? 'Required' : null,
            ),
          if (destination != null)
            _BalanceHint(text: _destinationBalanceSummary(destination)),
        ],
      ],
      _MoneyField(
        label: 'Amount',
        controller: amount,
        errorText: submitted && transferAmount <= 0 ? 'Required' : null,
      ),
      TextField(
        controller: note,
        decoration: const InputDecoration(labelText: 'Note'),
      ),
      if (movementType == 'purchase_transaction' && source != null)
        _BalanceHint(
          text:
              'Remaining ${sourceType == 'chunk' ? source['name'] : '${source['name']} unallocated'} balance: ${money(_sourceAvailable(source) - transferAmount)}',
        ),
      _SubmitButton(
        saving: saving,
        label: 'Add Transfer',
        onPressed: widget.canEdit && !saving ? _save : null,
      ),
    ];

    final formCard = FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(isPhone ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isPhone) ...[
                const _Notice(
                  'Use Add Transfer to move existing budget money between unallocated balances and chunks. For unallocated to chunk, choose the account as the source and a chunk in that same account as the destination.',
                ),
                const SizedBox(height: 12),
              ],
              ...formFields.map(
                (child) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return _Page(
      title: 'Transfers',
      actions: [
        FilledButton.icon(
          onPressed: widget.canEdit && !saving ? _save : null,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: const Text('Add Transfer'),
        ),
      ],
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isPhone) ...[
              const _Notice(
                'Use Add Transfer to move existing budget money between unallocated balances and chunks. For unallocated to chunk, choose the account as the source and a chunk in that same account as the destination.',
              ),
              const SizedBox(height: 14),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isPhone ? double.infinity : 620,
                ),
                child: formCard,
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Movement Log'),
            _DataCard(
              emptyText: 'No movements yet',
              children: listOfMaps(widget.data['recent_money_movements']).map((
                m,
              ) {
                return _ListRow(
                  title: m['movement_type'] == 'purchase_transaction'
                      ? '${m['source_type']} purchase/transaction'
                      : '${m['source_type']} to ${m['destination_type']}',
                  subtitle: m['note'].toString().isEmpty
                      ? formatDateTime(m['created_at'])
                      : m['note'].toString(),
                  trailing: money(m['amount']),
                  onTap: () =>
                      showTransferDetails(context, m, accounts, chunks),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => submitted = true);
    if (sourceId == null ||
        (destinationType != 'outside_account' && destinationId == null)) {
      return;
    }
    final sourceAvailable = _sourceAvailable(
      _selectedSource(
        listOfMaps(widget.data['accounts']),
        listOfMaps(widget.data['chunks']),
      ),
    );
    final requestedAmount = parseMoney(amount.text);
    if (requestedAmount <= 0) {
      toast(context, 'Enter a transfer amount greater than zero.');
      return;
    }
    final destination = _selectedDestination(
      listOfMaps(widget.data['accounts']),
      listOfMaps(widget.data['chunks']),
    );
    final effectiveAmount =
        destination?['chunk_type']?.toString() == 'loan' &&
            destination?['loan_balance'] != null
        ? requestedAmount
              .clamp(0, parseMoney('${destination?['loan_balance']}'))
              .toDouble()
        : requestedAmount;
    if (effectiveAmount > sourceAvailable) {
      toast(
        context,
        'Transfer amount is greater than the source amount available.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      final movement = await widget.api.post('/api/money-movements', {
        'movement_type': movementType,
        'source_type': sourceType,
        'source_id': sourceId,
        'destination_type': destinationType,
        'destination_id': destinationType == 'outside_account'
            ? null
            : destinationId,
        'amount': requestedAmount,
        'note': note.text,
      });
      amount.clear();
      note.clear();
      sourceId = null;
      destinationId = null;
      widget.refresh();
      if (!mounted) return;
      toast(
        context,
        effectiveAmount != requestedAmount
            ? 'Movement adjusted to remaining loan balance: ${money(movement['amount'])}'
            : 'Movement logged',
      );
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Map<String, dynamic>? _selectedSource(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> chunks,
  ) {
    if (sourceId == null) return null;
    final values = sourceType == 'chunk' ? chunks : accounts;
    return values.cast<Map<String, dynamic>?>().firstWhere(
      (value) => value?['id'] == sourceId,
      orElse: () => null,
    );
  }

  Map<String, dynamic>? _selectedDestination(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> chunks,
  ) {
    if (destinationId == null || destinationType == 'outside_account') {
      return null;
    }
    final values = destinationType == 'chunk' ? chunks : accounts;
    return values.cast<Map<String, dynamic>?>().firstWhere(
      (value) => value?['id'] == destinationId,
      orElse: () => null,
    );
  }

  double _sourceAvailable(Map<String, dynamic>? source) {
    if (source == null) return 0;
    if (sourceType == 'chunk') return parseMoney(source['balance'].toString());
    return parseMoney(source['unallocated_balance'].toString());
  }

  String _sourceBalanceSummary(Map<String, dynamic> source) {
    if (sourceType == 'chunk') {
      return 'Available in ${source['name']}: ${money(source['balance'])}';
    }
    return _accountBalanceSummary(source);
  }

  String _destinationBalanceSummary(Map<String, dynamic> destination) {
    if (destinationType == 'chunk') {
      if (destination['chunk_type']?.toString() == 'loan') {
        return 'Current ${destination['name']} loan balance: ${money(destination['loan_balance'])}';
      }
      return 'Current ${destination['name']} balance: ${money(destination['balance'])}';
    }
    return _accountBalanceSummary(destination);
  }

  String _accountBalanceSummary(Map<String, dynamic> account) {
    return 'Allocated ${money(account['allocated_balance'])}  |  Unallocated ${money(account['unallocated_balance'])}  |  Total ${money(account['balance'])}';
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.selectedProfile,
    required this.canEdit,
  });
  final BudgetApi api;
  final Map<String, dynamic> selectedProfile;
  final bool canEdit;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> data = _load();
  final userEmail = TextEditingController();
  final userName = TextEditingController();
  final userPassword = TextEditingController();
  final inviteEmail = TextEditingController();
  int? inviterUserId;
  var inviteRole = 'read_only';
  var saving = false;

  Future<Map<String, List<Map<String, dynamic>>>> _load() async {
    final users = listOfMaps(await widget.api.get('/api/users'));
    final invitations = listOfMaps(
      await widget.api.get(
        '/api/invitations?profile_id=${widget.selectedProfile['id']}',
      ),
    );
    return {'users': users, 'invitations': invitations};
  }

  void reload() {
    setState(() => data = _load());
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return _Page(
      title: 'Settings',
      child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: data,
        builder: (context, snapshot) {
          final users = snapshot.data?['users'] ?? [];
          final invitations = snapshot.data?['invitations'] ?? [];
          inviterUserId ??= users.isNotEmpty ? users.first['id'] as int : null;

          return ListView(
            padding: EdgeInsets.all(isPhone ? 14 : 20),
            children: [
              _Notice(
                widget.canEdit
                    ? 'Admins can invite other users to this profile as admin or read only.'
                    : 'This profile is read only for you. You can view balances, accounts, chunks, and activity.',
              ),
              const SizedBox(height: 14),
              if (widget.canEdit) ...[
                _SectionTitle('Create User'),
                _SettingsCard(
                  children: [
                    TextField(
                      controller: userEmail,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: userName,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    TextField(
                      controller: userPassword,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    _SubmitButton(
                      saving: saving,
                      label: 'Create User',
                      onPressed: _createUser,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              _SectionTitle('Invite User'),
              _SettingsCard(
                children: [
                  TextField(
                    controller: inviteEmail,
                    decoration: const InputDecoration(
                      labelText: 'Invite email',
                    ),
                  ),
                  _DropdownField<int>(
                    label: 'Inviting admin',
                    value: inviterUserId,
                    values: users.map((u) => u['id'] as int).toList(),
                    labelFor: (id) => users
                        .firstWhere((u) => u['id'] == id)['email']
                        .toString(),
                    onChanged: (v) => setState(() => inviterUserId = v),
                  ),
                  _DropdownField(
                    label: 'Role',
                    value: inviteRole,
                    values: const ['admin', 'read_only'],
                    labelFor: (role) => role == 'admin' ? 'Admin' : 'Read only',
                    onChanged: (v) =>
                        setState(() => inviteRole = v ?? inviteRole),
                  ),
                  _SubmitButton(
                    saving: saving,
                    label: 'Create Invitation',
                    onPressed: !widget.canEdit || inviterUserId == null
                        ? null
                        : _invite,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle('Users'),
              _DataCard(
                emptyText: snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading users'
                    : 'No users yet',
                children: users
                    .map(
                      (u) => _ListRow(
                        title: u['email'].toString(),
                        subtitle: u['display_name'].toString(),
                        trailing: '#${u['id']}',
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Invitations'),
              _DataCard(
                emptyText: 'No invitations yet',
                children: invitations
                    .map(
                      (i) => _ListRow(
                        title: i['email'].toString(),
                        subtitle: '${i['role']}  |  ${i['status']}',
                        trailing: '#${i['id']}',
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 22),
              const BuildInfoText(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createUser() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/users', {
        'email': userEmail.text,
        'display_name': userName.text,
        'password': userPassword.text,
      });
      userEmail.clear();
      userName.clear();
      userPassword.clear();
      reload();
      if (!mounted) return;
      toast(context, 'User saved');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _invite() async {
    setState(() => saving = true);
    try {
      await widget.api.post(
        '/api/budget-profiles/${widget.selectedProfile['id']}/invitations',
        {
          'email': inviteEmail.text,
          'role': inviteRole,
          'invited_by_user_id': inviterUserId,
        },
      );
      inviteEmail.clear();
      reload();
      if (!mounted) return;
      toast(context, 'Invitation created');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .map(
                  (child) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: child,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class MobileMoreScreen extends StatelessWidget {
  const MobileMoreScreen({super.key, required this.goTo});
  final ValueChanged<int> goTo;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'More',
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _MoreTile(
            icon: Icons.payments_outlined,
            title: 'Paycheck Setup',
            onTap: () => goTo(6),
          ),
          _MoreTile(
            icon: Icons.add_circle_outline,
            title: 'Add Paycheck',
            onTap: () => goTo(2),
          ),
          _MoreTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Accounts',
            onTap: () => goTo(3),
          ),
          _MoreTile(
            icon: Icons.fact_check_outlined,
            title: 'Budget Overview',
            onTap: () => goTo(1),
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () => goTo(7),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 18,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EntityDropdown extends StatelessWidget {
  const _EntityDropdown({
    required this.label,
    required this.type,
    required this.id,
    required this.accounts,
    required this.chunks,
    required this.onChanged,
    this.errorText,
  });
  final String label;
  final String type;
  final int? id;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> chunks;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final values = type == 'chunk' ? chunks : accounts;
    return _DropdownField<int>(
      label: label,
      value: id,
      values: values.map((v) => v['id'] as int).toList(),
      labelFor: (value) =>
          values.firstWhere((v) => v['id'] == value)['name'].toString(),
      onChanged: onChanged,
      errorText: errorText,
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            isPhone ? 14 : 20,
            isPhone ? 12 : 18,
            isPhone ? 14 : 20,
            isPhone ? 10 : 14,
          ),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isPhone ? 22 : 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, required this.minWidth});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minWidth).floor().clamp(1, 4);
        final isPhone = constraints.maxWidth < 600;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: isPhone ? 3.2 : 2.7,
          children: children,
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.children, required this.emptyText});
  final List<Widget> children;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: children.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                emptyText,
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            )
          : Column(children: children),
    );
  }
}

class _ChunkListHeader extends StatelessWidget {
  const _ChunkListHeader({
    required this.description,
    required this.amountLabel,
  });

  final String description;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chunk Name', style: textTheme.titleSmall),
                Text(description, style: textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              amountLabel,
              textAlign: TextAlign.right,
              style: textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.wrapSubtitle = false,
  });
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;
  final bool wrapSubtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        softWrap: wrapSubtitle,
        maxLines: wrapSubtitle ? null : 1,
        overflow: wrapSubtitle ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
      trailing: onTap == null
          ? Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final card = FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isPhone ? double.infinity : 620),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(isPhone ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children
                  .map(
                    (child) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: child,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );

    return ListView(
      padding: EdgeInsets.all(isPhone ? 14 : 20),
      children: [card],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFAEB),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFEC84B)),
    ),
    child: Text(text),
  );
}

class _BalanceHint extends StatelessWidget {
  const _BalanceHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF344054),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.controller,
    this.errorText,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'$ ',
        errorText: errorText,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelFor,
    this.errorText,
    this.enabled = true,
  });
  final String label;
  final T? value;
  final List<T> values;
  final ValueChanged<T?> onChanged;
  final String Function(T value)? labelFor;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: values.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label, errorText: errorText),
      items: values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(labelFor?.call(v) ?? v.toString()),
            ),
          )
          .toList(),
      onChanged: values.isEmpty || !enabled ? null : onChanged,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.saving,
    required this.label,
    required this.onPressed,
  });
  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: saving ? null : onPressed,
      icon: saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
      label: Text(label),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAccountDialog(
  BuildContext context,
  BudgetApi api,
  VoidCallback refresh, {
  Map<String, dynamic>? account,
}) async {
  final name = TextEditingController(text: account?['name']?.toString() ?? '');
  final balance = TextEditingController(
    text: account?['balance']?.toString() ?? '0',
  );
  var type = account?['type']?.toString() ?? 'checking';
  var sourceMode = account?['source_mode']?.toString() ?? 'manual';
  final isEditing = account != null;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isEditing ? 'Edit Account' : 'New Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Type',
              value: type,
              values: const ['checking', 'savings', 'cash', 'other'],
              onChanged: (v) => setState(() => type = v ?? type),
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Balance management',
              value: sourceMode,
              values: const ['manual', 'bank_connected'],
              labelFor: (value) =>
                  value == 'manual' ? 'Manual' : 'Bank connected',
              onChanged: (v) => setState(() => sourceMode = v ?? sourceMode),
            ),
            const SizedBox(height: 12),
            _MoneyField(label: 'Balance', controller: balance),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final payload = {
                'name': name.text,
                'type': type,
                'source_mode': sourceMode,
                'balance': parseMoney(balance.text),
                'is_active': account?['is_active'] ?? true,
              };
              if (isEditing) {
                await api.put('/api/accounts/${account['id']}', payload);
              } else {
                await api.post('/api/accounts', payload);
              }
              refresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
    ),
  );
}

Future<void> deleteAccount(
  BuildContext context,
  BudgetApi api,
  VoidCallback refresh,
  Map<String, dynamic> account,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Account'),
      content: Text(
        'Delete ${account['name']}? Accounts with chunks or activity cannot be deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await api.delete('/api/accounts/${account['id']}');
    refresh();
    if (context.mounted) toast(context, 'Account deleted');
  } catch (error) {
    if (context.mounted) toast(context, error.toString());
  }
}

Future<void> showChunkDialog(
  BuildContext context,
  BudgetApi api,
  VoidCallback refresh,
  List<Map<String, dynamic>> accounts, {
  required List<Map<String, dynamic>> paycheckProfiles,
  Map<String, dynamic>? chunk,
}) async {
  final name = TextEditingController(text: chunk?['name']?.toString() ?? '');
  final amount = TextEditingController(
    text: chunk?['amount_per_paycheck']?.toString() ?? '',
  );
  final loanBalance = TextEditingController(
    text: chunk?['loan_balance']?.toString() ?? '',
  );
  final loanRate = TextEditingController(
    text: chunk?['loan_interest_rate']?.toString() ?? '',
  );
  var accountId = chunk?['account_id'] as int? ?? accounts.first['id'] as int;
  var paycheckProfileId = chunk?['paycheck_profile_id'] as int?;
  var chunkType = chunk?['chunk_type']?.toString() ?? 'standard';
  final isEditing = chunk != null;
  var submitted = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isEditing ? 'Edit Chunk' : 'New Chunk'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: submitted && name.text.trim().isEmpty
                      ? 'Required'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              _DropdownField(
                label: 'Chunk type',
                value: chunkType,
                values: const ['standard', 'loan'],
                labelFor: (value) => value == 'loan' ? 'Loan' : 'Standard',
                onChanged: (v) => setState(() => chunkType = v ?? chunkType),
                enabled: !isEditing,
              ),
              if (chunkType != 'loan') ...[
                const SizedBox(height: 12),
                _DropdownField<int>(
                  label: 'Account',
                  value: accountId,
                  values: accounts.map((a) => a['id'] as int).toList(),
                  labelFor: (id) => accounts
                      .firstWhere((a) => a['id'] == id)['name']
                      .toString(),
                  onChanged: (v) => setState(() => accountId = v ?? accountId),
                ),
              ],
              const SizedBox(height: 12),
              _MoneyField(
                label: 'Amount per paycheck',
                controller: amount,
                onChanged: (_) => setState(() {}),
                errorText: submitted
                    ? amount.text.trim().isEmpty
                          ? 'Required'
                          : parseMoney(amount.text) < 0
                          ? 'Must be zero or more'
                          : null
                    : null,
              ),
              if (parseMoney(amount.text) > 0) ...[
                const SizedBox(height: 12),
                _DropdownField<int>(
                  label: 'Assigned paycheck',
                  value: paycheckProfileId,
                  values: paycheckProfiles
                      .map((profile) => profile['id'] as int)
                      .toList(),
                  labelFor: (id) => paycheckProfiles
                      .firstWhere((profile) => profile['id'] == id)['name']
                      .toString(),
                  onChanged: (v) => setState(() => paycheckProfileId = v),
                  errorText: submitted && paycheckProfileId == null
                      ? 'Required'
                      : null,
                ),
              ],
              if (chunkType == 'loan') ...[
                const SizedBox(height: 12),
                _MoneyField(
                  label: 'Current loan balance',
                  controller: loanBalance,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loanRate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Interest rate APR %',
                  ),
                ),
                const SizedBox(height: 12),
                const _BalanceHint(
                  text:
                      'Beta loan chunks estimate balance by applying interest once per paycheck period, then subtracting the paycheck amount.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              setState(() => submitted = true);
              final amountPerPaycheck = parseMoney(amount.text);
              if (name.text.trim().isEmpty ||
                  amount.text.trim().isEmpty ||
                  amountPerPaycheck < 0 ||
                  (amountPerPaycheck > 0 && paycheckProfileId == null)) {
                return;
              }
              final payload = {
                'name': name.text,
                'account_id': chunkType == 'loan' ? null : accountId,
                'paycheck_profile_id': amountPerPaycheck > 0
                    ? paycheckProfileId
                    : null,
                'chunk_type': chunkType,
                'amount_per_paycheck': amountPerPaycheck,
                'balance': chunk?['balance'] ?? 0,
                'loan_balance':
                    chunkType == 'loan' && loanBalance.text.isNotEmpty
                    ? parseMoney(loanBalance.text)
                    : null,
                'loan_interest_rate':
                    chunkType == 'loan' && loanRate.text.isNotEmpty
                    ? parseMoney(loanRate.text)
                    : null,
                'is_active': chunk?['is_active'] ?? true,
              };
              if (isEditing) {
                await api.put('/api/chunks/${chunk['id']}', payload);
              } else {
                await api.post('/api/chunks', payload);
              }
              refresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
    ),
  );
}

List<Map<String, dynamic>> listOfMaps(dynamic value) {
  if (value is List) {
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
}

double parseMoney(String value) {
  final normalized = value
      .replaceAll(',', '')
      .replaceAll(r'$', '')
      .replaceAll('(', '-')
      .replaceAll(')', '')
      .trim();
  return double.tryParse(normalized) ?? 0;
}

String movementLabel(String value) {
  return switch (value) {
    'outside_account' => 'Outside account',
    _ => value[0].toUpperCase() + value.substring(1),
  };
}

String money(dynamic value) {
  final number = value is num
      ? value
      : num.tryParse(value?.toString() ?? '') ?? 0;
  if (number == 0) return r'$ -';
  final formatted = NumberFormat('#,##0.00', 'en_US').format(number.abs());
  return number < 0 ? '\$ ($formatted)' : '\$ $formatted';
}

String formatDateTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return value?.toString() ?? '';
  return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
}

String balanceBeforeAfterText(dynamic before, dynamic after) {
  if (before == null && after == null) return 'Not recorded';
  return '${money(before)} before -> ${money(after)} after';
}

Future<void> showPaycheckDetails(
  BuildContext context,
  Map<String, dynamic> paycheck,
  BudgetApi api,
  VoidCallback refresh,
  bool canEdit,
) async {
  final allocations = listOfMaps(paycheck['allocations']);
  final shouldRevert = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Paycheck Details'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine(
                label: 'Paycheck profile',
                value:
                    paycheck['paycheck_profile_name']?.toString() ??
                    'Deleted paycheck profile',
              ),
              _DetailLine(
                label: 'Deposit account',
                value: paycheck['account_name']?.toString() ?? 'Unknown',
              ),
              _DetailLine(
                label: 'Added',
                value: formatDateTime(paycheck['created_at']),
              ),
              _DetailLine(
                label: 'Amount',
                value: money(paycheck['net_amount']),
              ),
              _DetailLine(
                label: 'Allocated',
                value: money(paycheck['allocated_amount']),
              ),
              _DetailLine(
                label: 'Unallocated',
                value: money(paycheck['unallocated_amount']),
              ),
              if (paycheck['is_reverted'] == true)
                _DetailLine(
                  label: 'Reverted',
                  value: formatDateTime(paycheck['reverted_at']),
                ),
              const SizedBox(height: 12),
              const Text(
                'Chunk Allocations',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (allocations.isEmpty) const Text('No chunks were allocated.'),
              for (final allocation in allocations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(allocation['chunk_name'].toString()),
                  subtitle: Text(
                    '${allocation['chunk_type']?.toString() == 'loan' ? 'Loan payment' : allocation['account_name']?.toString() ?? 'Unknown account'}\n'
                    '${allocation['chunk_type']?.toString() == 'loan' ? balanceBeforeAfterText(allocation['loan_balance_before'], allocation['loan_balance_after']) : balanceBeforeAfterText(allocation['balance_before'], allocation['balance_after'])}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    money(allocation['amount']),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (canEdit && paycheck['is_reverted'] != true)
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.undo),
            label: const Text('Revert'),
          ),
      ],
    ),
  );
  if (shouldRevert != true || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Revert Paycheck?'),
      content: const Text(
        'This removes this paycheck and its chunk allocations from the current balances. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Revert Paycheck'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await api.post('/api/paychecks/${paycheck['id']}/revert', {});
    refresh();
    if (context.mounted) toast(context, 'Paycheck reverted');
  } catch (error) {
    if (context.mounted) toast(context, error.toString());
  }
}

void showTransferDetails(
  BuildContext context,
  Map<String, dynamic> movement,
  List<Map<String, dynamic>> accounts,
  List<Map<String, dynamic>> chunks,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Transfer Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLine(
            label: 'From',
            value: movementEndpointName(
              movement['source_type'],
              movement['source_id'],
              accounts,
              chunks,
            ),
          ),
          if (movement['movement_type'] != 'purchase_transaction')
            _DetailLine(
              label: 'To',
              value: movementEndpointName(
                movement['destination_type'],
                movement['destination_id'],
                accounts,
                chunks,
              ),
            ),
          _DetailLine(label: 'Amount', value: money(movement['amount'])),
          _DetailLine(
            label: 'Source',
            value: balanceBeforeAfterText(
              movement['source_balance_before'],
              movement['source_balance_after'],
            ),
          ),
          if (movement['movement_type'] != 'purchase_transaction')
            _DetailLine(
              label: 'Dest.',
              value: balanceBeforeAfterText(
                movement['destination_balance_before'],
                movement['destination_balance_after'],
              ),
            ),
          _DetailLine(
            label: 'Note',
            value: movement['note'].toString().isEmpty
                ? 'None'
                : movement['note'].toString(),
          ),
          _DetailLine(
            label: 'Date',
            value: formatDateTime(movement['created_at']),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

String movementEndpointName(
  dynamic type,
  dynamic id,
  List<Map<String, dynamic>> accounts,
  List<Map<String, dynamic>> chunks,
) {
  final value = type?.toString() ?? '';
  if (value == 'outside_account') return 'Outside account';
  if (value == 'chunk') {
    final chunk = chunks.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == id,
      orElse: () => null,
    );
    return chunk == null ? 'Chunk #$id' : '${chunk['name']} chunk';
  }
  if (value == 'unallocated' || value == 'account') {
    final account = accounts.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == id,
      orElse: () => null,
    );
    return account == null
        ? 'Account #$id unallocated'
        : '${account['name']} unallocated';
  }
  return movementLabel(value);
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
