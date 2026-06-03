import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ChunkyCatBudgApp());
}

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

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
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
          isDense: true,
        ),
      ),
      home: const BudgetHome(),
    );
  }
}

class BudgetApi {
  Uri _uri(String path) {
    if (apiBaseUrl.isNotEmpty) {
      return Uri.parse('$apiBaseUrl$path');
    }
    return Uri.base.resolve(path.startsWith('/') ? path.substring(1) : path);
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

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = body is Map && body['detail'] != null ? body['detail'].toString() : response.body;
      throw ApiException(message);
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
}

class BudgetHome extends StatefulWidget {
  const BudgetHome({super.key});

  @override
  State<BudgetHome> createState() => _BudgetHomeState();
}

class _BudgetHomeState extends State<BudgetHome> {
  final api = BudgetApi();
  var selected = 0;
  late Future<Map<String, dynamic>> summaryFuture = _loadSummary();

  final screens = const [
    ('Dashboard', Icons.dashboard_outlined),
    ('Paycheck Setup', Icons.payments_outlined),
    ('Accounts', Icons.account_balance_wallet_outlined),
    ('Chunks', Icons.savings_outlined),
    ('Add Paycheck', Icons.add_circle_outline),
    ('Transfers', Icons.swap_horiz_outlined),
    ('Transactions', Icons.receipt_long_outlined),
    ('Settings', Icons.settings_outlined),
  ];

  Future<Map<String, dynamic>> _loadSummary() async {
    return Map<String, dynamic>.from(await api.get('/api/dashboard/summary'));
  }

  void refresh() {
    setState(() => summaryFuture = _loadSummary());
  }

  void openScreen(int index) {
    setState(() => selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: summaryFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting && data == null;
        final error = snapshot.error;
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
                      );

            if (isDesktop) {
              return _DesktopShell(
                screens: screens,
                selected: selected,
                onSelect: openScreen,
                child: child,
              );
            }
            return _PhoneShell(
              selected: selected,
              onSelect: openScreen,
              child: child,
            );
          },
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.screens,
    required this.selected,
    required this.onSelect,
    required this.child,
  });

  final List<(String, IconData)> screens;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(screens: screens, selected: selected, onSelect: onSelect),
          Expanded(child: SafeArea(child: child)),
        ],
      ),
    );
  }
}

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.selected,
    required this.onSelect,
    required this.child,
  });

  static const routes = [0, 4, 5, 2, 8];

  final int selected;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final navIndex = routes.contains(selected) ? routes.indexOf(selected) : routes.length - 1;
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (index) => onSelect(routes[index]),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Paycheck'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Move'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Accounts'),
          NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'More'),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.screens, required this.selected, required this.onSelect});
  final List<(String, IconData)> screens;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Text('ChunkyCat Budget', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: screens.length,
                itemBuilder: (context, index) {
                  final item = screens[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: NavigationDrawerDestination(
                      icon: Icon(item.$2),
                      label: Text(item.$1),
                      selectedIcon: Icon(item.$2),
                    ).buildListTile(context, selected: selected == index, onTap: () => onSelect(index)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on NavigationDrawerDestination {
  Widget buildListTile(BuildContext context, {required bool selected, required VoidCallback onTap}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: .11) : Colors.transparent,
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
  });

  final int selected;
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;
  final ValueChanged<int> goTo;

  @override
  Widget build(BuildContext context) {
    return switch (selected) {
      0 => DashboardScreen(data: data, refresh: refresh, goTo: goTo),
      1 => PaycheckSetupScreen(data: data, api: api, refresh: refresh),
      2 => AccountsScreen(data: data, api: api, refresh: refresh),
      3 => ChunksScreen(data: data, api: api, refresh: refresh),
      4 => AddPaycheckScreen(data: data, api: api, refresh: refresh),
      5 => TransfersScreen(data: data, api: api, refresh: refresh),
      6 => TransactionsScreen(data: data, api: api, refresh: refresh),
      8 => MobileMoreScreen(goTo: goTo),
      _ => SettingsScreen(api: api),
    };
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.data, required this.refresh, required this.goTo});
  final Map<String, dynamic> data;
  final VoidCallback refresh;
  final ValueChanged<int> goTo;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final totals = Map<String, dynamic>.from(data['totals'] ?? {});
    final accounts = List<Map<String, dynamic>>.from((data['accounts'] ?? []).map((e) => Map<String, dynamic>.from(e)));
    final chunks = List<Map<String, dynamic>>.from((data['chunks'] ?? []).map((e) => Map<String, dynamic>.from(e)));
    final movements = List<Map<String, dynamic>>.from((data['recent_money_movements'] ?? []).map((e) => Map<String, dynamic>.from(e)));

    return _Page(
      title: 'Dashboard',
      actions: [
        IconButton(onPressed: refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
      ],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _ResponsiveGrid(
            minWidth: 210,
            children: [
              _MetricCard(label: 'Account Balance', value: money(totals['account_balance']), icon: Icons.account_balance_wallet_outlined),
              _MetricCard(label: 'Allocated', value: money(totals['allocated_balance']), icon: Icons.savings_outlined),
              _MetricCard(label: 'Unallocated', value: money(totals['unallocated_balance']), icon: Icons.inventory_2_outlined),
            ],
          ),
          const SizedBox(height: 16),
          _DashboardActions(isPhone: isPhone, goTo: goTo),
          const SizedBox(height: 20),
          _SectionTitle('Accounts'),
          _DataCard(
            emptyText: 'No accounts yet',
            children: accounts.map((a) {
              return _ListRow(
                title: a['name'].toString(),
                subtitle: 'Allocated ${money(a['allocated_balance'])}  |  Unallocated ${money(a['unallocated_balance'])}',
                trailing: money(a['balance']),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Chunks'),
          _DataCard(
            emptyText: 'No chunks yet',
            children: chunks.map((c) {
              return _ListRow(
                title: c['name'].toString(),
                subtitle: '${c['account_name']}  |  ${money(c['amount_per_paycheck'])} per paycheck',
                trailing: money(c['balance']),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Recent Transfers'),
          _DataCard(
            emptyText: 'No transfers logged',
            children: movements.map((m) {
              return _ListRow(
                title: '${m['source_type']} to ${m['destination_type']}',
                subtitle: m['note'].toString().isEmpty ? m['created_at'].toString() : m['note'].toString(),
                trailing: money(m['amount']),
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
          FilledButton.icon(onPressed: () => goTo(4), icon: const Icon(Icons.add), label: const Text('Add Paycheck')),
          OutlinedButton.icon(onPressed: () => goTo(5), icon: const Icon(Icons.swap_horiz), label: const Text('Move Money')),
          OutlinedButton.icon(onPressed: () => goTo(2), icon: const Icon(Icons.add_card), label: const Text('Account')),
          OutlinedButton.icon(onPressed: () => goTo(3), icon: const Icon(Icons.playlist_add), label: const Text('Chunk')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => goTo(4),
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
            label: const Text('Move Money'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => goTo(2),
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
                  onPressed: () => goTo(3),
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

class PaycheckSetupScreen extends StatefulWidget {
  const PaycheckSetupScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  State<PaycheckSetupScreen> createState() => _PaycheckSetupScreenState();
}

class _PaycheckSetupScreenState extends State<PaycheckSetupScreen> {
  final gross = TextEditingController();
  final net = TextEditingController();
  var mode = 'expected';
  var frequency = 'biweekly';
  var saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.data['paycheck_profile'];
    if (profile is Map) {
      gross.text = '${profile['gross_pay_amount'] ?? ''}';
      net.text = '${profile['net_pay_amount'] ?? ''}';
      mode = profile['net_pay_mode']?.toString() ?? mode;
      frequency = profile['pay_frequency']?.toString() ?? frequency;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Paycheck Setup',
      child: _FormCard(
        children: [
          _MoneyField(label: 'Gross pay amount', controller: gross),
          _MoneyField(label: 'Net pay amount', controller: net),
          _DropdownField(label: 'Net pay mode', value: mode, values: const ['manual', 'expected', 'estimated'], onChanged: (v) => setState(() => mode = v ?? mode)),
          _DropdownField(label: 'Pay frequency', value: frequency, values: const ['weekly', 'biweekly', 'semimonthly', 'monthly', 'custom'], onChanged: (v) => setState(() => frequency = v ?? frequency)),
          _SubmitButton(
            saving: saving,
            label: 'Save Profile',
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/paycheck-profile', {
        'gross_pay_amount': parseMoney(gross.text),
        'net_pay_amount': parseMoney(net.text),
        'net_pay_mode': mode,
        'pay_frequency': frequency,
      });
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
}

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final accounts = listOfMaps(data['accounts']);
    return _Page(
      title: 'Accounts',
      actions: [FilledButton.icon(onPressed: () => showAccountDialog(context, api, refresh), icon: const Icon(Icons.add), label: const Text('New'))],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _DataCard(
            emptyText: 'Create a real-world account to hold paycheck money',
            children: accounts.map((a) {
              return _ListRow(
                title: a['name'].toString(),
                subtitle: '${a['type']}  |  Unallocated ${money(a['unallocated_balance'])}',
                trailing: money(a['balance']),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class ChunksScreen extends StatelessWidget {
  const ChunksScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final chunks = listOfMaps(data['chunks']);
    final accounts = listOfMaps(data['accounts']);
    return _Page(
      title: 'Chunks',
      actions: [FilledButton.icon(onPressed: accounts.isEmpty ? null : () => showChunkDialog(context, api, refresh, accounts), icon: const Icon(Icons.add), label: const Text('New'))],
      child: ListView(
        padding: EdgeInsets.all(isPhone ? 14 : 20),
        children: [
          _DataCard(
            emptyText: accounts.isEmpty ? 'Create an account before adding chunks' : 'Create chunks that apply once per paycheck',
            children: chunks.map((c) {
              return _ListRow(
                title: c['name'].toString(),
                subtitle: '${c['account_name']}  |  ${money(c['amount_per_paycheck'])} per paycheck',
                trailing: money(c['balance']),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class AddPaycheckScreen extends StatefulWidget {
  const AddPaycheckScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  State<AddPaycheckScreen> createState() => _AddPaycheckScreenState();
}

class _AddPaycheckScreenState extends State<AddPaycheckScreen> {
  var mode = 'expected';
  int? accountId;
  final custom = TextEditingController();
  var saving = false;

  @override
  Widget build(BuildContext context) {
    final accounts = listOfMaps(widget.data['accounts']);
    accountId ??= accounts.isNotEmpty ? accounts.first['id'] as int : null;
    final profile = widget.data['paycheck_profile'];
    return _Page(
      title: 'Add Paycheck',
      child: _FormCard(
        children: [
          if (profile == null) const _Notice('Create a paycheck profile before adding a paycheck.'),
          if (accounts.isEmpty) const _Notice('Create an account before adding a paycheck.'),
          _DropdownField<int>(
            label: 'Deposit account',
            value: accountId,
            values: accounts.map((a) => a['id'] as int).toList(),
            labelFor: (id) => accounts.firstWhere((a) => a['id'] == id)['name'].toString(),
            onChanged: (v) => setState(() => accountId = v),
          ),
          _DropdownField(label: 'Amount', value: mode, values: const ['expected', 'custom'], labelFor: (v) => v == 'expected' ? 'Use expected net pay' : 'Use custom amount', onChanged: (v) => setState(() => mode = v ?? mode)),
          if (mode == 'custom') _MoneyField(label: 'Custom amount', controller: custom),
          _SubmitButton(
            saving: saving,
            label: 'Add Paycheck',
            onPressed: profile == null || accountId == null ? null : _add,
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    setState(() => saving = true);
    try {
      final result = await widget.api.post('/api/paychecks/add', {
        'amount_mode': mode,
        'custom_amount': mode == 'custom' ? parseMoney(custom.text) : null,
        'account_id': accountId,
      });
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Paycheck added. Unallocated: ${money(result['unallocated_amount'])}');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  var sourceType = 'unallocated';
  var destinationType = 'chunk';
  int? sourceId;
  int? destinationId;
  final amount = TextEditingController();
  final note = TextEditingController();
  var saving = false;

  @override
  Widget build(BuildContext context) {
    final accounts = listOfMaps(widget.data['accounts']);
    final chunks = listOfMaps(widget.data['chunks']);
    sourceId ??= sourceType == 'chunk' && chunks.isNotEmpty ? chunks.first['id'] as int : accounts.isNotEmpty ? accounts.first['id'] as int : null;
    destinationId ??= destinationType == 'chunk' && chunks.isNotEmpty ? chunks.first['id'] as int : accounts.isNotEmpty ? accounts.first['id'] as int : null;

    return _Page(
      title: 'Transfers',
      child: ListView(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 20),
        children: [
          _FormCard(
            children: [
              _DropdownField(label: 'From', value: sourceType, values: const ['chunk', 'unallocated'], onChanged: (v) => setState(() { sourceType = v ?? sourceType; sourceId = null; })),
              _EntityDropdown(label: 'Source', type: sourceType, id: sourceId, accounts: accounts, chunks: chunks, onChanged: (v) => setState(() => sourceId = v)),
              _DropdownField(
                label: 'To',
                value: destinationType,
                values: const ['chunk', 'account', 'unallocated', 'outside_account'],
                labelFor: movementLabel,
                onChanged: (v) => setState(() { destinationType = v ?? destinationType; destinationId = null; }),
              ),
              if (destinationType != 'outside_account') _EntityDropdown(label: 'Destination', type: destinationType == 'chunk' ? 'chunk' : 'unallocated', id: destinationId, accounts: accounts, chunks: chunks, onChanged: (v) => setState(() => destinationId = v)),
              _MoneyField(label: 'Amount', controller: amount),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
              _SubmitButton(saving: saving, label: 'Log Movement', onPressed: sourceId == null ? null : _save),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('Movement Log'),
          _DataCard(
            emptyText: 'No movements yet',
            children: listOfMaps(widget.data['recent_money_movements']).map((m) {
              return _ListRow(title: '${m['source_type']} to ${m['destination_type']}', subtitle: m['note'].toString(), trailing: money(m['amount']));
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/money-movements', {
        'source_type': sourceType,
        'source_id': sourceId,
        'destination_type': destinationType,
        'destination_id': destinationType == 'outside_account' ? null : destinationId,
        'amount': parseMoney(amount.text),
        'note': note.text,
      });
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Movement logged');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.data, required this.api, required this.refresh});
  final Map<String, dynamic> data;
  final BudgetApi api;
  final VoidCallback refresh;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late Future<List<Map<String, dynamic>>> transactions = _load();
  int? accountId;
  var allocationType = 'unallocated';
  final amount = TextEditingController();
  final description = TextEditingController();
  var saving = false;

  Future<List<Map<String, dynamic>>> _load() async => listOfMaps(await widget.api.get('/api/transactions'));

  @override
  Widget build(BuildContext context) {
    final accounts = listOfMaps(widget.data['accounts']);
    accountId ??= accounts.isNotEmpty ? accounts.first['id'] as int : null;
    return _Page(
      title: 'Transactions',
      child: ListView(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 20),
        children: [
          _FormCard(
            children: [
              _DropdownField<int>(
                label: 'Account',
                value: accountId,
                values: accounts.map((a) => a['id'] as int).toList(),
                labelFor: (id) => accounts.firstWhere((a) => a['id'] == id)['name'].toString(),
                onChanged: (v) => setState(() => accountId = v),
              ),
              _MoneyField(label: 'Amount', controller: amount),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              _DropdownField(label: 'Allocation', value: allocationType, values: const ['chunk', 'unallocated', 'outside_account'], onChanged: (v) => setState(() => allocationType = v ?? allocationType)),
              _SubmitButton(saving: saving, label: 'Add Transaction', onPressed: accountId == null ? null : _save),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle('Transactions'),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: transactions,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? [];
              return _DataCard(
                emptyText: snapshot.connectionState == ConnectionState.waiting ? 'Loading transactions' : 'No transactions yet',
                children: rows.map((t) => _ListRow(title: t['description'].toString(), subtitle: t['allocation_type'].toString(), trailing: money(t['amount']))).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/transactions', {
        'account_id': accountId,
        'amount': parseMoney(amount.text),
        'description': description.text,
        'allocation_type': allocationType,
        'allocation_id': null,
      });
      setState(() => transactions = _load());
      widget.refresh();
      if (!mounted) return;
      toast(context, 'Transaction added');
    } catch (error) {
      if (!mounted) return;
      toast(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final BudgetApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> data = _load();
  final userEmail = TextEditingController();
  final userName = TextEditingController();
  final profileName = TextEditingController();
  final inviteEmail = TextEditingController();
  int? ownerUserId;
  int? inviteProfileId;
  int? inviterUserId;
  var inviteRole = 'read_only';
  var saving = false;

  Future<Map<String, List<Map<String, dynamic>>>> _load() async {
    final users = listOfMaps(await widget.api.get('/api/users'));
    final profiles = listOfMaps(await widget.api.get('/api/budget-profiles'));
    final invitations = listOfMaps(await widget.api.get('/api/invitations'));
    return {'users': users, 'profiles': profiles, 'invitations': invitations};
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
          final profiles = snapshot.data?['profiles'] ?? [];
          final invitations = snapshot.data?['invitations'] ?? [];
          ownerUserId ??= users.isNotEmpty ? users.first['id'] as int : null;
          inviterUserId ??= users.isNotEmpty ? users.first['id'] as int : null;
          inviteProfileId ??= profiles.isNotEmpty ? profiles.first['id'] as int : null;

          return ListView(
            padding: EdgeInsets.all(isPhone ? 14 : 20),
            children: [
              const _Notice('Users can belong to zero or more budget profiles. The user who creates a profile is its admin.'),
              const SizedBox(height: 14),
              _SectionTitle('Create User'),
              _SettingsCard(
                children: [
                  TextField(controller: userEmail, decoration: const InputDecoration(labelText: 'Email')),
                  TextField(controller: userName, decoration: const InputDecoration(labelText: 'Display name')),
                  _SubmitButton(saving: saving, label: 'Create User', onPressed: _createUser),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle('Create Budget Profile'),
              _SettingsCard(
                children: [
                  TextField(controller: profileName, decoration: const InputDecoration(labelText: 'Profile name')),
                  _DropdownField<int>(
                    label: 'Admin user',
                    value: ownerUserId,
                    values: users.map((u) => u['id'] as int).toList(),
                    labelFor: (id) => users.firstWhere((u) => u['id'] == id)['email'].toString(),
                    onChanged: (v) => setState(() => ownerUserId = v),
                  ),
                  _SubmitButton(saving: saving, label: 'Create Profile', onPressed: ownerUserId == null ? null : _createProfile),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle('Invite User'),
              _SettingsCard(
                children: [
                  TextField(controller: inviteEmail, decoration: const InputDecoration(labelText: 'Invite email')),
                  _DropdownField<int>(
                    label: 'Budget profile',
                    value: inviteProfileId,
                    values: profiles.map((p) => p['id'] as int).toList(),
                    labelFor: (id) => profiles.firstWhere((p) => p['id'] == id)['name'].toString(),
                    onChanged: (v) => setState(() => inviteProfileId = v),
                  ),
                  _DropdownField<int>(
                    label: 'Inviting admin',
                    value: inviterUserId,
                    values: users.map((u) => u['id'] as int).toList(),
                    labelFor: (id) => users.firstWhere((u) => u['id'] == id)['email'].toString(),
                    onChanged: (v) => setState(() => inviterUserId = v),
                  ),
                  _DropdownField(
                    label: 'Role',
                    value: inviteRole,
                    values: const ['admin', 'read_only'],
                    labelFor: (role) => role == 'admin' ? 'Admin' : 'Read only',
                    onChanged: (v) => setState(() => inviteRole = v ?? inviteRole),
                  ),
                  _SubmitButton(
                    saving: saving,
                    label: 'Create Invitation',
                    onPressed: inviteProfileId == null || inviterUserId == null ? null : _invite,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle('Users'),
              _DataCard(
                emptyText: snapshot.connectionState == ConnectionState.waiting ? 'Loading users' : 'No users yet',
                children: users.map((u) => _ListRow(title: u['email'].toString(), subtitle: u['display_name'].toString(), trailing: '#${u['id']}')).toList(),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Budget Profiles'),
              _DataCard(
                emptyText: 'No budget profiles yet',
                children: profiles.map((p) => _ListRow(title: p['name'].toString(), subtitle: 'Owner user #${p['owner_user_id']}', trailing: '#${p['id']}')).toList(),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Invitations'),
              _DataCard(
                emptyText: 'No invitations yet',
                children: invitations.map((i) => _ListRow(title: i['email'].toString(), subtitle: '${i['role']}  |  ${i['status']}', trailing: '#${i['id']}')).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createUser() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/users', {'email': userEmail.text, 'display_name': userName.text});
      userEmail.clear();
      userName.clear();
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

  Future<void> _createProfile() async {
    setState(() => saving = true);
    try {
      await widget.api.post('/api/budget-profiles', {'name': profileName.text, 'owner_user_id': ownerUserId});
      profileName.clear();
      reload();
      if (!mounted) return;
      toast(context, 'Budget profile created');
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
      await widget.api.post('/api/budget-profiles/$inviteProfileId/invitations', {
        'email': inviteEmail.text,
        'role': inviteRole,
        'invited_by_user_id': inviterUserId,
      });
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: child)).toList(),
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
          _MoreTile(icon: Icons.payments_outlined, title: 'Paycheck Setup', onTap: () => goTo(1)),
          _MoreTile(icon: Icons.savings_outlined, title: 'Chunks', onTap: () => goTo(3)),
          _MoreTile(icon: Icons.receipt_long_outlined, title: 'Transactions', onTap: () => goTo(6)),
          _MoreTile(icon: Icons.settings_outlined, title: 'Settings', onTap: () => goTo(7)),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.title, required this.onTap});
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
  const _EntityDropdown({required this.label, required this.type, required this.id, required this.accounts, required this.chunks, required this.onChanged});
  final String label;
  final String type;
  final int? id;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> chunks;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = type == 'chunk' ? chunks : accounts;
    return _DropdownField<int>(
      label: label,
      value: id,
      values: values.map((v) => v['id'] as int).toList(),
      labelFor: (value) => values.firstWhere((v) => v['id'] == value)['name'].toString(),
      onChanged: onChanged,
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions = const []});
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
          padding: EdgeInsets.fromLTRB(isPhone ? 14 : 20, isPhone ? 12 : 18, isPhone ? 14 : 20, isPhone ? 10 : 14),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(child: Text(title, style: TextStyle(fontSize: isPhone ? 22 : 24, fontWeight: FontWeight.w800))),
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
  const _MetricCard({required this.label, required this.value, required this.icon});
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
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF667085))),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
          ? Padding(padding: const EdgeInsets.all(18), child: Text(emptyText, style: const TextStyle(color: Color(0xFF667085))))
          : Column(children: children),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, required this.subtitle, required this.trailing});
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.all(isPhone ? 14 : 20),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isPhone ? double.infinity : 620),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(isPhone ? 14 : 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: child)).toList()),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFFAEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFEC84B))),
        child: Text(text),
      );
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, prefixText: r'$ '),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({required this.label, required this.value, required this.values, required this.onChanged, this.labelFor});
  final String label;
  final T? value;
  final List<T> values;
  final ValueChanged<T?> onChanged;
  final String Function(T value)? labelFor;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: values.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: values.map((v) => DropdownMenuItem(value: v, child: Text(labelFor?.call(v) ?? v.toString()))).toList(),
      onChanged: values.isEmpty ? null : onChanged,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.saving, required this.label, required this.onPressed});
  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: saving ? null : onPressed,
      icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
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
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

Future<void> showAccountDialog(BuildContext context, BudgetApi api, VoidCallback refresh) async {
  final name = TextEditingController();
  final balance = TextEditingController(text: '0');
  var type = 'checking';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            _DropdownField(label: 'Type', value: type, values: const ['checking', 'savings', 'cash', 'other'], onChanged: (v) => setState(() => type = v ?? type)),
            const SizedBox(height: 12),
            _MoneyField(label: 'Balance', controller: balance),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await api.post('/api/accounts', {'name': name.text, 'type': type, 'balance': parseMoney(balance.text), 'is_active': true});
              refresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showChunkDialog(BuildContext context, BudgetApi api, VoidCallback refresh, List<Map<String, dynamic>> accounts) async {
  final name = TextEditingController();
  final amount = TextEditingController();
  var accountId = accounts.first['id'] as int;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New Chunk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            _DropdownField<int>(
              label: 'Account',
              value: accountId,
              values: accounts.map((a) => a['id'] as int).toList(),
              labelFor: (id) => accounts.firstWhere((a) => a['id'] == id)['name'].toString(),
              onChanged: (v) => setState(() => accountId = v ?? accountId),
            ),
            const SizedBox(height: 12),
            _MoneyField(label: 'Amount per paycheck', controller: amount),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await api.post('/api/chunks', {
                'name': name.text,
                'account_id': accountId,
                'amount_per_paycheck': parseMoney(amount.text),
                'balance': 0,
                'is_active': true,
              });
              refresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
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
  return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
}

String movementLabel(String value) {
  return switch (value) {
    'outside_account' => 'Outside account',
    _ => value[0].toUpperCase() + value.substring(1),
  };
}

String money(dynamic value) {
  final number = value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
  return '\$${number.toStringAsFixed(2)}';
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
