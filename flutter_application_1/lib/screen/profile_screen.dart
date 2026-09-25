import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool editing = false;

  final TextEditingController nameController =
      TextEditingController(text: 'Social9 User');

  final TextEditingController emailController =
      TextEditingController(text: 'user@example.com');

  final TextEditingController usernameController =
      TextEditingController(text: 'social9user');

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  void saveProfile() {
    setState(() {
      editing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully'),
      ),
    );
  }

  Widget profileField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: editing && enabled,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget connectedAccount({
    required String name,
    required IconData icon,
    required String status,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(status),
        trailing: const Icon(
          Icons.check_circle,
          color: Colors.green,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            tooltip: editing ? 'Cancel' : 'Edit Profile',
            icon: Icon(
              editing ? Icons.close : Icons.edit,
            ),
            onPressed: () {
              setState(() {
                editing = !editing;
              });
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            // PROFILE PHOTO
            const Center(
              child: CircleAvatar(
                radius: 55,
                child: Icon(
                  Icons.person,
                  size: 60,
                ),
              ),
            ),

            const SizedBox(height: 15),

            const Center(
              child: Text(
                'Social9 User',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 5),

            const Center(
              child: Text(
                'Manage your Social9 account',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // PERSONAL INFORMATION
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            profileField(
              label: 'Name',
              controller: nameController,
              icon: Icons.person,
            ),

            profileField(
              label: 'Email',
              controller: emailController,
              icon: Icons.email,
              enabled: false,
            ),

            profileField(
              label: 'Username',
              controller: usernameController,
              icon: Icons.alternate_email,
            ),

            if (editing)
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'Save Profile',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  onPressed: saveProfile,
                ),
              ),

            const SizedBox(height: 30),

            // CONNECTED ACCOUNTS
            const Text(
              'Connected Accounts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            connectedAccount(
              name: 'Instagram',
              icon: Icons.camera_alt,
              status: 'Connected',
            ),

            connectedAccount(
              name: 'LinkedIn',
              icon: Icons.work,
              status: 'Connected',
            ),

            connectedAccount(
              name: 'Facebook',
              icon: Icons.facebook,
              status: 'Not connected',
            ),

            const SizedBox(height: 20),

            // ACCOUNT INFORMATION
            const Text(
              'Account',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.security,
                ),
                title: const Text(
                  'Account Security',
                ),
                subtitle: const Text(
                  'Manage your account security',
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                ),
                onTap: () {},
              ),
            ),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.notifications,
                ),
                title: const Text(
                  'Notifications',
                ),
                subtitle: const Text(
                  'Manage notification preferences',
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                ),
                onTap: () {},
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

