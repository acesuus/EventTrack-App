import 'package:flutter/material.dart';

abstract final class StudentUi {
  static const green = Color(0xFF1E7F5A);
  static const ink = Color(0xFF0C2D48);
  static const muted = Color(0xFF63716B);
  static const background = Color(0xFFF5F7F6);
  static const line = Color(0xFFE0E6E2);

  /// Shared app theme so default widgets (spinners, dialogs, text buttons) use the brand green.
  static final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green),
  );
}

class StudentSurface extends StatelessWidget {
  const StudentSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: StudentUi.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class StudentDetailLine extends StatelessWidget {
  const StudentDetailLine({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: StudentUi.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: StudentUi.muted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class StudentEventDetails extends StatelessWidget {
  const StudentEventDetails({
    super.key,
    required this.title,
    required this.venue,
    required this.time,
    required this.date,
    this.address = '',
  });
  final String title;
  final String venue;
  final String time;
  final String date;
  final String address;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(
            color: StudentUi.ink,
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.schedule, size: 20, color: StudentUi.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    color: StudentUi.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: const TextStyle(
                    color: StudentUi.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 20,
            color: StudentUi.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue,
                  style: const TextStyle(
                    color: StudentUi.muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (address.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: const TextStyle(
                      color: StudentUi.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class StudentEventCard extends StatelessWidget {
  const StudentEventCard({
    super.key,
    required this.details,
    required this.status,
    this.statusDetail,
    required this.isActive,
    required this.buttonLabel,
    this.onJoin,
    this.attendance,
  });
  final StudentEventDetails details;
  final String status;
  final String? statusDetail;
  final bool isActive;
  final String buttonLabel;
  final VoidCallback? onJoin;
  final Widget? attendance;

  @override
  Widget build(BuildContext context) => StudentSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        details,
        const Padding(
          padding: EdgeInsets.only(top: 20, bottom: 16),
          child: Divider(height: 1, color: StudentUi.line),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActive ? Icons.check_circle_outline : Icons.schedule,
                  size: 17,
                  color: isActive ? StudentUi.green : StudentUi.muted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isActive ? StudentUi.green : StudentUi.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (statusDetail != null)
              Text(
                statusDetail!,
                style: const TextStyle(color: StudentUi.muted, fontSize: 12),
              ),
          ],
        ),
        if (attendance != null) ...[const SizedBox(height: 16), attendance!],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onJoin,
          style: FilledButton.styleFrom(
            backgroundColor: StudentUi.green,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFEDF0EE),
            disabledForegroundColor: StudentUi.muted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: Text(buttonLabel)),
              if (onJoin != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward, size: 19),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class StudentTrackingStatus extends StatelessWidget {
  const StudentTrackingStatus({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.checking = false,
  });
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool checking;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: checking
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StudentUi.green,
                ),
              )
            : Icon(icon, color: color, size: 23),
      ),
      const SizedBox(width: 12),
      Expanded(
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
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                color: StudentUi.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
