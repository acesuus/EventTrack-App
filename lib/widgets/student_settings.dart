import 'package:flutter/material.dart';

import 'student_ui.dart';
import 'student_avatar.dart';

class StudentSettingsContent extends StatelessWidget {
  const StudentSettingsContent({
    super.key,
    required this.name,
    required this.studentId,
    required this.email,
    required this.hasConsented,
    required this.deviceProtected,
    required this.onEdit,
    required this.onPrivacy,
    required this.onYourData,
    required this.onLocation,
    required this.onPermissions,
    required this.onLogout,
    this.program = '',
    this.yearBlock = '',
    this.photoBase64,
    this.onPhotoChange,
    this.onPhotoRemove,
    this.photoBusy = false,
  });

  final String name;
  final String studentId;
  final String email;
  final String program;
  final String yearBlock;
  final bool hasConsented;
  final bool deviceProtected;
  final VoidCallback onEdit;
  final VoidCallback onPrivacy;
  final VoidCallback onYourData;
  final VoidCallback onLocation;
  final VoidCallback onPermissions;
  final VoidCallback onLogout;
  final String? photoBase64;
  final VoidCallback? onPhotoChange;
  final VoidCallback? onPhotoRemove;
  final bool photoBusy;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
    children: [
      StudentSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StudentAvatar(name: name, photoBase64: photoBase64, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STUDENT ACCOUNT',
                        style: TextStyle(
                          color: StudentUi.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: const TextStyle(
                          color: StudentUi.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onPhotoChange != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: photoBusy ? null : onPhotoChange,
                      icon: photoBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: StudentUi.green,
                              ),
                            )
                          : const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(
                        photoBusy
                            ? 'Updating photo…'
                            : photoBase64 == null
                            ? 'Add photo'
                            : 'Change photo',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: StudentUi.green,
                      ),
                    ),
                    if (photoBase64 != null && onPhotoRemove != null)
                      TextButton(
                        onPressed: photoBusy ? null : onPhotoRemove,
                        style: TextButton.styleFrom(
                          foregroundColor: StudentUi.muted,
                        ),
                        child: const Text('Remove photo'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: StudentUi.line),
            const SizedBox(height: 20),
            _ProfileDetail(
              label: 'Student ID',
              value: studentId,
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 18),
            _ProfileDetail(
              label: 'School email',
              value: email.contains('@') ? email : 'Not added',
              icon: Icons.mail_outline,
            ),
            if (program.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              _ProfileDetail(
                label: 'Program',
                value: program,
                icon: Icons.school_outlined,
              ),
            ],
            if (yearBlock.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              _ProfileDetail(
                label: 'Year & block',
                value: yearBlock,
                icon: Icons.groups_outlined,
              ),
            ],
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: StudentUi.green,
                side: const BorderSide(color: StudentUi.green),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      const _SettingsHeading(
        title: 'Privacy & security',
        subtitle: 'Your consent and account protection',
      ),
      StudentSurface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _SettingsAction(
              icon: Icons.verified_user_outlined,
              title: 'Privacy notice',
              subtitle: hasConsented
                  ? 'Accepted · View your consent'
                  : 'Review and accept the privacy notice',
              onTap: onPrivacy,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: StudentUi.line),
            ),
            _SettingsAction(
              icon: Icons.shield_outlined,
              title: 'Your data',
              subtitle: 'See what EventTrack saves about you',
              onTap: onYourData,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: StudentUi.line),
            ),
            _SettingsAction(
              icon: deviceProtected
                  ? Icons.phonelink_lock_outlined
                  : Icons.phone_android_outlined,
              title: 'Device binding',
              subtitle: deviceProtected
                  ? 'Your account is linked to a registered device'
                  : 'A device will be linked when you join an event',
            ),
          ],
        ),
      ),
      const _SettingsHeading(
        title: 'App access',
        subtitle: 'Manage how attendance uses your location',
      ),
      StudentSurface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _SettingsAction(
              icon: Icons.location_on_outlined,
              title: 'Location settings',
              subtitle: 'Turn on your phone’s location services',
              onTap: onLocation,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: StudentUi.line),
            ),
            _SettingsAction(
              icon: Icons.tune,
              title: 'App permissions',
              subtitle: 'Manage EventTrack’s location access',
              onTap: onPermissions,
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout, size: 19),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFFB23A3A),
          side: const BorderSide(color: Color(0xFFE5CCCC)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Icon(icon, size: 20, color: StudentUi.muted),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: StudentUi.muted, fontSize: 12),
            ),
            const SizedBox(height: 5),
            SelectableText(
              value,
              style: const TextStyle(
                color: StudentUi.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12, left: 2, right: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: StudentUi.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: StudentUi.muted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 22, color: StudentUi.green),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: StudentUi.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: StudentUi.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, size: 20, color: StudentUi.muted),
            ],
          ],
        ),
      ),
    ),
  );
}
