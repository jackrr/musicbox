import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/sequencer_provider.dart';

class PadPage extends ConsumerStatefulWidget {
  const PadPage({super.key});

  @override
  ConsumerState<PadPage> createState() => _PadPageState();
}

class _PadPageState extends ConsumerState<PadPage> {
  bool _recordMode = false;

  void _onPadTap(int trackId) {
    final engine   = ref.read(engineProvider);
    final playhead = ref.read(playheadProvider).value ?? -1;

    engine.noteOn(trackId, 60, 100);

    if (_recordMode && playhead >= 0) {
      // Write a step at the current playhead position
      final project = ref.read(projectProvider).value;
      if (project != null) {
        ref.read(sequencerProvider.notifier).setStep(
          trackId, playhead,
          StepData(active: true, pitch: 60, velocity: 0.8),
        );
      }
    }
  }

  void _onPadRelease(int trackId) {
    ref.read(engineProvider).noteOff(trackId, 60);
  }

  void _addLayout(BuildContext context) async {
    final nameCtrl = TextEditingController(text: 'Layout');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New Layout', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Layout name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final layout = PadLayout(
        name: nameCtrl.text.trim().isEmpty ? 'Layout' : nameCtrl.text.trim(),
        cells: PadLayout.defaultLayout().cells,
      );
      ref.read(projectProvider.notifier).addPadLayout(layout);
    }
  }

  void _reorderCell(int layoutIdx, int fromIdx, int toIdx, List<PadCell> cells) {
    if (fromIdx == toIdx) return;
    final updated = List<PadCell>.from(cells);
    final item = updated.removeAt(fromIdx);
    updated.insert(toIdx > fromIdx ? toIdx - 1 : toIdx, item);
    // Update each cell's position via project notifier
    for (var i = 0; i < updated.length; i++) {
      ref.read(projectProvider.notifier).updatePadCell(layoutIdx, i, updated[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: projectAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (project) {
            final layoutIdx = project.activePadLayout
                .clamp(0, project.padLayouts.length - 1);
            final layout = project.padLayouts[layoutIdx];

            return Column(
              children: [
                // Layout picker row
                _LayoutPicker(
                  layouts:       project.padLayouts,
                  activeIdx:     layoutIdx,
                  recordMode:    _recordMode,
                  onSelect:      (i) => ref.read(projectProvider.notifier).setActivePadLayout(i),
                  onAdd:         () => _addLayout(context),
                  onToggleRecord: () => setState(() => _recordMode = !_recordMode),
                ),

                const Divider(height: 1, color: Colors.white12),

                // Pad grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _PadGrid(
                      layout:      layout,
                      layoutIdx:   layoutIdx,
                      onTap:       _onPadTap,
                      onRelease:   _onPadRelease,
                      onReorder:   (from, to) =>
                          _reorderCell(layoutIdx, from, to, layout.cells),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout picker strip
// ---------------------------------------------------------------------------

class _LayoutPicker extends StatelessWidget {
  final List<PadLayout> layouts;
  final int activeIdx;
  final bool recordMode;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onToggleRecord;

  const _LayoutPicker({
    required this.layouts,
    required this.activeIdx,
    required this.recordMode,
    required this.onSelect,
    required this.onAdd,
    required this.onToggleRecord,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Scrollable layout tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: layouts.length,
              itemBuilder: (_, i) {
                final selected = i == activeIdx;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected ? Colors.greenAccent.withAlpha(30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected ? Colors.greenAccent : Colors.white24,
                      ),
                    ),
                    child: Text(
                      layouts[i].name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.greenAccent : Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Add layout button
          IconButton(
            icon: const Icon(Icons.add, size: 18, color: Colors.white38),
            tooltip: 'New layout',
            onPressed: onAdd,
          ),
          // Record mode toggle
          GestureDetector(
            onTap: onToggleRecord,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: recordMode ? Colors.redAccent.withAlpha(40) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: recordMode ? Colors.redAccent : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record,
                    size: 10,
                    color: recordMode ? Colors.redAccent : Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    'REC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: recordMode ? Colors.redAccent : Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pad grid with long-press drag to reorder
// ---------------------------------------------------------------------------

class _PadGrid extends StatelessWidget {
  final PadLayout layout;
  final int layoutIdx;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onRelease;
  final void Function(int from, int to) onReorder;

  const _PadGrid({
    required this.layout,
    required this.layoutIdx,
    required this.onTap,
    required this.onRelease,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableGridView(
      cells: layout.cells,
      onTap: onTap,
      onRelease: onRelease,
      onReorder: onReorder,
    );
  }
}

// ---------------------------------------------------------------------------
// Reorderable 2×N grid
// ---------------------------------------------------------------------------

class ReorderableGridView extends StatefulWidget {
  final List<PadCell> cells;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onRelease;
  final void Function(int from, int to) onReorder;

  const ReorderableGridView({
    super.key,
    required this.cells,
    required this.onTap,
    required this.onRelease,
    required this.onReorder,
  });

  @override
  State<ReorderableGridView> createState() => _ReorderableGridViewState();
}

class _ReorderableGridViewState extends State<ReorderableGridView> {
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    const columns = 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = (constraints.maxWidth - (columns - 1) * 12) / columns;
        final rows = (widget.cells.length / columns).ceil();

        return SizedBox(
          height: rows * (cellSize / 1.4) + (rows - 1) * 12,
          child: Stack(
            children: [
              // Grid positions
              for (var i = 0; i < widget.cells.length; i++)
                _gridPosition(i, cellSize, columns,
                  _PadTile(
                    cell:       widget.cells[i],
                    isDragging: _dragging == i,
                    onTap:      () => widget.onTap(widget.cells[i].trackId),
                    onRelease:  () => widget.onRelease(widget.cells[i].trackId),
                    onDragStart: () => setState(() => _dragging = i),
                    onDragEnd:   (_) => setState(() => _dragging = null),
                    onAccept:   (fromIdx) {
                      widget.onReorder(fromIdx, i);
                      setState(() => _dragging = null);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _gridPosition(int index, double cellSize, int columns, Widget child) {
    const crossSpacing = 12.0;
    const mainSpacing  = 12.0;
    final col = index % columns;
    final row = index ~/ columns;
    final cellHeight = cellSize / 1.4;

    return Positioned(
      left:  col * (cellSize + crossSpacing),
      top:   row * (cellHeight + mainSpacing),
      width: cellSize,
      height: cellHeight,
      child: child,
    );
  }
}

class _PadTile extends StatefulWidget {
  final PadCell cell;
  final bool isDragging;
  final VoidCallback onTap;
  final VoidCallback onRelease;
  final VoidCallback onDragStart;
  final void Function(DraggableDetails) onDragEnd;
  final ValueChanged<int> onAccept;

  const _PadTile({
    required this.cell,
    required this.isDragging,
    required this.onTap,
    required this.onRelease,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onAccept,
  });

  @override
  State<_PadTile> createState() => _PadTileState();
}

class _PadTileState extends State<_PadTile> {
  bool _pressed = false;
  final _dragKey = GlobalKey();

  Color get _color => Color(widget.cell.colorValue);

  @override
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onRelease();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onRelease();
      },
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) => widget.onAccept(details.data),
        builder: (ctx, candidateData, rejectedData) {
          final isTarget = candidateData.isNotEmpty;
          return AnimatedContainer(
            key: _dragKey,
            duration: const Duration(milliseconds: 80),
            decoration: BoxDecoration(
              color: _pressed
                  ? _color.withAlpha(120)
                  : isTarget
                      ? _color.withAlpha(60)
                      : _color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _pressed || isTarget ? _color : _color.withAlpha(100),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_note, color: _color, size: 28),
                const SizedBox(height: 4),
                Text(
                  widget.cell.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _color,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return LongPressDraggable<int>(
      data: widget.cell.trackId,
      onDragStarted: widget.onDragStart,
      onDragEnd: widget.onDragEnd,
      feedback: SizedBox(
        width: 100, height: 70,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: _color.withAlpha(80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _color, width: 2),
            ),
            child: Center(
              child: Text(widget.cell.label,
                style: TextStyle(
                  color: _color, fontWeight: FontWeight.bold,
                  fontSize: 14)),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.2, child: tile),
      child: tile,
    );
  }
}
