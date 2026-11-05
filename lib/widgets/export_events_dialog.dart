import 'package:flutter/material.dart';

enum ReportFormat { pdf, csv }

class ExportEventOption {
  const ExportEventOption({required this.id, required this.title});

  final String id;
  final String title;
}

class ExportSelection {
  const ExportSelection(this.eventIds, this.format);

  final List<String> eventIds;
  final ReportFormat format;
}

/// Keeps export choices separate from report generation and Firebase access.
class ExportEventsDialog extends StatefulWidget {
  const ExportEventsDialog({
    super.key,
    required this.events,
    required this.primaryColor,
  });

  final List<ExportEventOption> events;
  final Color primaryColor;

  @override
  State<ExportEventsDialog> createState() => _ExportEventsDialogState();
}

class _ExportEventsDialogState extends State<ExportEventsDialog> {
  static const _ink = Color(0xFF16372E);
  static const _muted = Color(0xFF667A72);
  static const _line = Color(0xFFE2EBE6);
  final Set<String> _selected = {};
  ReportFormat _format = ReportFormat.pdf;

  @override
  Widget build(BuildContext context) {
    final green = widget.primaryColor;
    final allSelected = _selected.length == widget.events.length;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.file_download_outlined,
                            color: green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Export reports',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              color: _ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF4F7F5),
                            foregroundColor: _muted,
                          ),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your event attendance, ready to share.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _sectionLabel('01', 'Select events'),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: green,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: widget.events.isEmpty
                              ? null
                              : () => setState(() {
                                  if (allSelected) {
                                    _selected.clear();
                                  } else {
                                    _selected.addAll(
                                      widget.events.map((e) => e.id),
                                    );
                                  }
                                }),
                          child: Text(allSelected ? 'Clear all' : 'Select all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (widget.events.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'No events available.',
                          style: TextStyle(color: _muted),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 252),
                        child: ListView.separated(
                          primary: false,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: widget.events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final event = widget.events[index];
                            final selected = _selected.contains(event.id);
                            return Material(
                              color: selected
                                  ? green.withValues(alpha: 0.07)
                                  : const Color(0xFFF8FAF9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: selected ? green : _line,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CheckboxListTile(
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selected.remove(event.id);
                                  } else {
                                    _selected.add(event.id);
                                  }
                                }),
                                activeColor: green,
                                checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFA5B6AD),
                                  width: 1.5,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 0,
                                ),
                                secondary: Icon(
                                  Icons.event_outlined,
                                  color: selected ? green : _muted,
                                  size: 21,
                                ),
                                title: Text(
                                  event.title,
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),
                    _sectionLabel('02', 'Choose format'),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _formatCard(
                            ReportFormat.pdf,
                            Icons.picture_as_pdf_outlined,
                            'PDF',
                            'Ready to print',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _formatCard(
                            ReportFormat.csv,
                            Icons.table_chart_outlined,
                            'CSV',
                            'For spreadsheets',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selected.isEmpty
                        ? 'Select at least one event to continue'
                        : '${_selected.length} ${_selected.length == 1 ? 'event' : 'events'} selected · ${_format.name.toUpperCase()} report',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            ExportSelection(
                              List.unmodifiable(_selected),
                              _format,
                            ),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFEBF0ED),
                      disabledForegroundColor: const Color(0xFF82948A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    label: Text('Export ${_format.name.toUpperCase()}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String number, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        number,
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _formatCard(
    ReportFormat format,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _format == format;
    final green = widget.primaryColor;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      excludeSemantics: true,
      onTap: () => setState(() => _format = format),
      child: Material(
        color: selected ? green.withValues(alpha: 0.07) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? green : _line,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _format = format),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: selected ? green : _muted, size: 23),
                    const Spacer(),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected ? green : _line,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
