import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:permission_handler/permission_handler.dart';

class PageContacts extends StatefulWidget {
  const PageContacts({super.key});

  @override
  State<PageContacts> createState() => _PageContactsState();
}

class _PageContactsState extends State<PageContacts> {
  List<Contact>? _contacts;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchContacts();
    });
  }

  Future _fetchContacts() async {
    if (!await FlutterContacts.requestPermission()) {
      setState(() => _permissionDenied = true);
    } else {
      final contacts = await FlutterContacts.getContacts(
          withProperties: true, withThumbnail: true);
      setState(() => _contacts = contacts);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Pick a contact')), body: _body());
  }

  Widget _body() {
    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Permission required',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                openAppSettings(); // Open app settings on tap
              },
              child: const Text(
                "Grant permission",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );
    }
    if (_contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      itemCount: _contacts!.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        Contact contact = _contacts![index];
        final cs = Theme.of(context).colorScheme;
        final int length = _contacts!.length;

        return Padding(
          padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: index == 0 ? 4 : 0,
              bottom: index == length - 1 ? 0 : 3),
          child: Material(
            color: cs.onSurface.withValues(alpha: 0.04),
            borderRadius: listRowRadius(index, length),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop(contact);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _ContactAvatar(contact: contact),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.displayName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (contact.phones.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              contact.phones.first.number,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.6)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight,
                        size: 18,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Slightly-rounded-square avatar: photo when available, otherwise the
/// contact's first initial.
class _ContactAvatar extends StatelessWidget {
  final Contact contact;

  const _ContactAvatar({required this.contact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color = cs.tertiary;
    final String name = contact.displayName.trim();
    final String initials = name.isNotEmpty ? name[0].toUpperCase() : "?";

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: contact.thumbnail != null
            ? Image.memory(contact.thumbnail!, fit: BoxFit.cover)
            : ColoredBox(
                color: color.withValues(alpha: 0.15),
                child: Center(
                  child: Text(initials,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ),
      ),
    );
  }
}
