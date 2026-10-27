import 'package:flutter/material.dart';
import 'package:callnow_new/model/client_data_model.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initialize background call tracking service on startup
    _initCallTracker();
  }

  Future<void> _initCallTracker() async {
    final success = await CallTrackingService.initialize();
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Phone call tracking permissions needed to automatically log calls.',
          ),
          action: SnackBarAction(
            label: 'Enable',
            onPressed: () => CallTrackingService.initialize(),
          ),
        ),
      );
    }
  }

  static const List<Widget> _pages = <Widget>[
    DashboardPage(),
    ClientsPage(),
    EnquiriesPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk, size: 22),
            SizedBox(width: 8),
            Text('CallNow', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Live call tracking status badge in appbar
          ValueListenableBuilder<bool>(
            valueListenable: CallTrackingService.isTrackingActive,
            builder: (context, isActive, _) {
              return Tooltip(
                message: isActive
                    ? 'Background call tracking is running'
                    : 'Call tracking inactive. Tap to enable.',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ActionChip(
                    avatar: Icon(
                      Icons.circle,
                      size: 10,
                      color: isActive ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                    label: Text(
                      isActive ? 'Auto Log ON' : 'Auto Log OFF',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    onPressed: isActive
                        ? null
                        : () => CallTrackingService.initialize(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Enquiries',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DASHBOARD TAB
// -----------------------------------------------------------------------------
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Telecalling Activity Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2B29), Color(0xFF3E403C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Background Call Tracker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: CallTrackingService.isTrackingActive,
                        builder: (context, isActive, _) {
                          return Chip(
                            backgroundColor: isActive
                                ? Colors.green.withValues(alpha: 0.25)
                                : Colors.red.withValues(alpha: 0.25),
                            label: Text(
                              isActive ? 'ACTIVE' : 'INACTIVE',
                              style: TextStyle(
                                color: isActive ? Colors.greenAccent : Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Automatically detects call start, duration, and end events in the background, logging them directly to your CRM.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.wifi_tethering, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: CallTrackingService.lastCallEvent,
                          builder: (context, eventText, _) {
                            return Text(
                              eventText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Statistics Grid
          const Text(
            'Today\'s Telecalling Stats',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: CallTrackingService.totalCallsTracked,
                builder: (context, total, _) {
                  return _buildStatCard(
                    context,
                    title: 'Calls Logged',
                    value: total.toString(),
                    icon: Icons.phone_forwarded,
                    color: Colors.blue,
                  );
                },
              ),
              _buildStatCard(
                context,
                title: 'Pending Enquiries',
                value: '12',
                icon: Icons.assignment_late_outlined,
                color: Colors.orange,
              ),
              _buildStatCard(
                context,
                title: 'Clients Assigned',
                value: '48',
                icon: Icons.groups_outlined,
                color: Colors.purple,
              ),
              _buildStatCard(
                context,
                title: 'Conversion Rate',
                value: '24%',
                icon: Icons.trending_up,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick Action Banner
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.security, size: 36, color: Colors.blueGrey),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Background Call Permissions',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ensure phone state & call log permissions are always granted.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => CallTrackingService.initialize(),
                    child: const Text('Check'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Icon(icon, size: 20, color: color),
              ],
            ),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CLIENTS TAB (Interactive Dialer & Contact Cards)
// -----------------------------------------------------------------------------
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final TextEditingController _searchController = TextEditingController();

  // Initial sample leads for field agents
  final List<ClientDataModel> _clients = [
    ClientDataModel(
      id: '101',
      name: 'Rahul Sharma',
      mobile: '+919876543210',
      company: 'Tata Consultancy Services',
      package: 'Personal Loan ₹5L',
      status: 'HOT_LEAD',
      uploadDate: DateTime.now().subtract(const Duration(days: 1)),
      callBy: 'Agent 01',
      callTime: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    ClientDataModel(
      id: '102',
      name: 'Priya Verma',
      mobile: '+919812345678',
      company: 'Infosys Limited',
      package: 'Home Loan ₹35L',
      status: 'FOLLOW_UP',
      uploadDate: DateTime.now().subtract(const Duration(days: 2)),
      callBy: 'Agent 01',
      callTime: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    ClientDataModel(
      id: '103',
      name: 'Amit Patel',
      mobile: '+919900112233',
      company: 'HDFC Bank Ltd',
      package: 'Business Loan ₹15L',
      status: 'INTERESTED',
      uploadDate: DateTime.now().subtract(const Duration(days: 3)),
      callBy: 'Agent 01',
      callTime: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  late List<ClientDataModel> _filteredClients;

  @override
  void initState() {
    super.initState();
    _filteredClients = _clients;
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClients = _clients.where((client) {
        return client.name.toLowerCase().contains(query) ||
            client.mobile.contains(query) ||
            client.company.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by client name, mobile or company...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // Clients List
          Expanded(
            child: _filteredClients.isEmpty
                ? const Center(child: Text('No clients found matching search.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredClients.length,
                    itemBuilder: (context, index) {
                      final client = _filteredClients[index];
                      return _buildClientCard(context, client);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard(BuildContext context, ClientDataModel client) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    client.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${client.company} • ${client.package}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        client.mobile,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(client.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    client.status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(client.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Dialer & Messaging Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // WhatsApp Button
                OutlinedButton.icon(
                  onPressed: () => CallTrackingService.openWhatsApp(
                    client.mobile,
                    message:
                        'Hello ${client.name}, this is regarding your enquiry for ${client.package}. How can I assist you today?',
                  ),
                  icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                  label: const Text('WhatsApp', style: TextStyle(color: Colors.green)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),

                // Direct Call Button
                FilledButton.icon(
                  onPressed: () => CallTrackingService.makePhoneCall(client.mobile),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call Now'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'HOT_LEAD':
        return Colors.red;
      case 'FOLLOW_UP':
        return Colors.orange;
      case 'INTERESTED':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }
}

// -----------------------------------------------------------------------------
// ENQUIRIES TAB
// -----------------------------------------------------------------------------
class EnquiriesPage extends StatelessWidget {
  const EnquiriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Enquiry Pipeline',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'All loan enquiries will be synced and displayed here. Telecaller remarks and statuses are updated in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fetching enquiries from server...')),
                );
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync Enquiries'),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PROFILE TAB
// -----------------------------------------------------------------------------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const CircleAvatar(
            radius: 40,
            child: Icon(Icons.person, size: 48),
          ),
          const SizedBox(height: 12),
          const Text(
            'Field Agent',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text(
            'CallNow Telecalling Desk',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Phone Call State Permissions'),
                  subtitle: const Text('Check background permissions status'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => CallTrackingService.initialize(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change Password'),
                  subtitle: const Text('Update account security credentials'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password reset available in settings.')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('App Version'),
                  subtitle: const Text('CallNow 5.0 (Build with Background Call Tracking)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
