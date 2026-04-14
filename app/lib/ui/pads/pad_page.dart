import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/sequencer_provider.dart';

const int    kPadColumns  = 2;
const double kPadGap      = 10.0;
const double kCellAspect  = 1.5; // width : height for a 1×1 cell

class PadPage extends ConsumerStatefulWidget {
  const PadPage({super.key});

  @override
  ConsumerState<PadPage> createState() => _PadPageState();
}

class _PadPageState extends ConsumerState<PadPage> {
  bool _editMode   = false;
  bool _recordMode = false;

  void _onPadDown(int trackId) {
    final engine   = ref.read(engineProvider);
    final playhead = ref.read(playheadProvider).value ?? -1;
    engine.noteOn(trackId, 60, 100);
    if (_recordMode && playhead >= 0) {
      ref.read(sequencerProvider.notifier).setStep(
        trackId, playhead,
        StepData(active: true, pitch: 60, velocity: 0.8),
      );
    }
  }

  void _onPadUp(int trackId) =>
      ref.read(engineProvider).noteOff(trackId, 60);

  void _addLayout(BuildContext context) async {
    final ctrl = TextEditingController(text: 'Layout');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New Layout', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Layout name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add', style: TextStyle(color: Colors.greenAccent))),
        ],
      ),
    );
    if (ok == true) {
      final name = ctrl.text.trim().isEmpty ? 'Layout' : ctrl.text.trim();
      ref.read(projectProvider.notifier).addPadLayout(
        PadLayout(name: name, cells: PadLayout.defaultLayout().cells),
      );
    }
  }

  void _editCell(BuildContext context, int layoutIdx, int cellIdx, PadCell cell) async {
    final result = await showDialog<PadCell>(
      context: context,
      builder: (ctx) => _CellEditor(cell: cell),
    );
    if (result != null) {
      ref.read(projectProvider.notifier).updatePadCell(layoutIdx, cellIdx, result);
    }
  }

  void _swapCells(int layoutIdx, int fromTrackId, int toIdx) {
    final project = ref.read(projectProvider).value;
    if (project == null) return;
    final li = layoutIdx.clamp(0, project.padLayouts.length - 1);
    final cells = List<PadCell>.from(project.padLayouts[li].cells);
    final fromIdx = cells.indexWhere((c) => c.trackId == fromTrackId);
    if (fromIdx < 0 || toIdx < 0 || fromIdx >= cells.length || toIdx >= cells.length) return;
    final tmp       = cells[fromIdx];
    cells[fromIdx]  = cells[toIdx];
    cells[toIdx]    = tmp;
    for (var i = 0; i < cells.length; i++) {
      ref.read(projectProvider.notifier).updatePadCell(li, i, cells[i]);
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
          error:   (e, _) => Center(child: Text('$e')),
          data: (project) {
            final layoutIdx = project.activePadLayout
                .clamp(0, project.padLayouts.length - 1);
            final layout = project.padLayouts[layoutIdx];

            return Column(
              children: [
                _LayoutPicker(
                  layouts:        project.padLayouts,
                  activeIdx:      layoutIdx,
                  editMode:       _editMode,
                  recordMode:     _recordMode,
                  onSelect:       (i) => ref.read(projectProvider.notifier)
                                           .setActivePadLayout(i),
                  onAdd:          () => _addLayout(context),
                  onToggleEdit:   () => setState(() => _editMode = !_editMode),
                  onToggleRecord: () => setState(() => _recordMode = !_recordMode),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: _PadGrid(
                      layout:    layout,
                      layoutIdx: layoutIdx,
                      editMode:  _editMode,
                      onDown:    _onPadDown,
                      onUp:      _onPadUp,
                      onEdit:    (ci, cell) =>
                          _editCell(context, layoutIdx, ci, cell),
                      onSwap:    (fromTid, toIdx) =>
                          _swapCells(layoutIdx, fromTid, toIdx),
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
  final int  activeIdx;
  final bool editMode;
  final bool recordMode;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onToggleEdit;
  final VoidCallback onToggleRecord;

  const _LayoutPicker({
    required this.layouts,
    required this.activeIdx,
    required this.editMode,
    required this.recordMode,
    required this.onSelect,
    required this.onAdd,
    required this.onToggleEdit,
    required this.onToggleRecord,
  });

  Widget _chip({
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: active ? color : Colors.white38),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: active ? color : Colors.white38,
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Layout tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: layouts.length,
              itemBuilder: (_, i) {
                final sel = i == activeIdx;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? Colors.greenAccent.withAlpha(30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: sel ? Colors.greenAccent : Colors.white24),
                    ),
                    child: Text(layouts[i].name,
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: sel ? Colors.greenAccent : Colors.white38,
                        letterSpacing: 1,
                      )),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18, color: Colors.white38),
            tooltip: 'New layout',
            onPressed: onAdd,
          ),
          _chip(
            label: 'EDIT',
            active: editMode,
            color: Colors.amberAccent,
            icon: Icons.edit_outlined,
            onTap: onToggleEdit,
          ),
          _chip(
            label: 'REC',
            active: recordMode,
            color: Colors.redAccent,
            icon: Icons.fiber_manual_record,
            onTap: onToggleRecord,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CSS-grid-style auto-placement
// ---------------------------------------------------------------------------

class _Placement {
  final int row, col;
  const _Placement(this.row, this.col);
}

List<_Placement> _computePlacements(List<PadCell> cells) {
  final occupied = <int>[0];

  bool canPlace(int row, int col, int cs, int rs) {
    if (col + cs > kPadColumns) return false;
    while (occupied.length <= row + rs - 1) { occupied.add(0); }
    for (var r = row; r < row + rs; r++) {
      for (var c = col; c < col + cs; c++) {
        if ((occupied[r] >> c) & 1 != 0) return false;
      }
    }
    return true;
  }

  void mark(int row, int col, int cs, int rs) {
    while (occupied.length <= row + rs - 1) { occupied.add(0); }
    for (var r = row; r < row + rs; r++) {
      for (var c = col; c < col + cs; c++) {
        occupied[r] |= (1 << c);
      }
    }
  }

  final placements = <_Placement>[];
  for (final cell in cells) {
    final cs = cell.colSpan.clamp(1, kPadColumns);
    final rs = cell.rowSpan.clamp(1, 8);
    var found = false;
    for (var row = 0; !found; row++) {
      for (var col = 0; col <= kPadColumns - cs; col++) {
        if (canPlace(row, col, cs, rs)) {
          placements.add(_Placement(row, col));
          mark(row, col, cs, rs);
          found = true;
          break;
        }
      }
    }
  }
  return placements;
}

// ---------------------------------------------------------------------------
// Pad grid
// ---------------------------------------------------------------------------

class _PadGrid extends StatelessWidget {
  final PadLayout layout;
  final int       layoutIdx;
  final bool      editMode;
  final ValueChanged<int> onDown;
  final ValueChanged<int> onUp;
  final void Function(int cellIdx, PadCell cell) onEdit;
  final void Function(int fromTrackId, int toIdx) onSwap;

  const _PadGrid({
    required this.layout,
    required this.layoutIdx,
    required this.editMode,
    required this.onDown,
    required this.onUp,
    required this.onEdit,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final cells      = layout.cells;
    final placements = _computePlacements(cells);

    if (cells.isEmpty) return const SizedBox.shrink();

    final numRows = Iterable.generate(cells.length)
        .map((i) => placements[i].row + cells[i].rowSpan.clamp(1, 8))
        .reduce((a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - (kPadColumns - 1) * kPadGap) / kPadColumns;
        final cellH = cellW / kCellAspect;

        return SizedBox(
          width:  constraints.maxWidth,
          height: numRows * cellH + (numRows - 1) * kPadGap,
          child: Stack(
            children: [
              for (var i = 0; i < cells.length; i++)
                _placed(
                  i, cells[i], placements[i], cellW, cellH, cells),
            ],
          ),
        );
      },
    );
  }

  Widget _placed(int idx, PadCell cell, _Placement p,
                 double cellW, double cellH, List<PadCell> cells) {
    final cs = cell.colSpan.clamp(1, kPadColumns);
    final rs = cell.rowSpan.clamp(1, 8);
    return Positioned(
      left:   p.col * (cellW + kPadGap),
      top:    p.row * (cellH + kPadGap),
      width:  cs * cellW + (cs - 1) * kPadGap,
      height: rs * cellH + (rs - 1) * kPadGap,
      child: _PadTile(
        cell:     cell,
        editMode: editMode,
        onDown:   () => onDown(cell.trackId),
        onUp:     () => onUp(cell.trackId),
        onEdit:   () => onEdit(idx, cell),
        onDrop:   (fromTid) => onSwap(fromTid, idx),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual pad tile
//
// PLAY MODE  — uses raw Listener (bypasses gesture arena).
//              noteOn fires on first pointer contact; noteOff on release/cancel.
//
// EDIT MODE  — tap opens the cell editor.
//              long-press + drag reorders pads (LongPressDraggable).
// ---------------------------------------------------------------------------

class _PadTile extends StatefulWidget {
  final PadCell     cell;
  final bool        editMode;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onEdit;
  final ValueChanged<int> onDrop;  // called with dragged trackId

  const _PadTile({
    required this.cell,
    required this.editMode,
    required this.onDown,
    required this.onUp,
    required this.onEdit,
    required this.onDrop,
  });

  @override
  State<_PadTile> createState() => _PadTileState();
}

class _PadTileState extends State<_PadTile> {
  bool _pressed = false;

  Color get _color => Color(widget.cell.colorValue);

  Widget _visual({bool isTarget = false, bool showEditIcon = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      decoration: BoxDecoration(
        color: _pressed
            ? _color.withAlpha(130)
            : isTarget
                ? _color.withAlpha(70)
                : _color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _pressed || isTarget ? _color : _color.withAlpha(110),
          width: 2,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, color: _color, size: 26),
              const SizedBox(height: 4),
              Text(
                widget.cell.label,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold,
                  color: _color, letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (showEditIcon)
            Positioned(
              right: 6, top: 6,
              child: Icon(Icons.edit_outlined,
                size: 13, color: _color.withAlpha(180)),
            ),
        ],
      ),
    );
  }

  Widget _dragFeedback() => Material(
    color: Colors.transparent,
    child: Container(
      width: 110, height: 72,
      decoration: BoxDecoration(
        color: _color.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color, width: 2),
      ),
      child: Center(
        child: Text(widget.cell.label,
          style: TextStyle(
            color: _color, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // ── PLAY MODE ────────────────────────────────────────────────────────────
    // Listener fires immediately on pointer contact and never competes in the
    // gesture arena, so noteOn/noteOff are always reliable regardless of how
    // fast or many fingers tap.
    if (!widget.editMode) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          setState(() => _pressed = true);
          widget.onDown();
        },
        onPointerUp: (_) {
          setState(() => _pressed = false);
          widget.onUp();
        },
        onPointerCancel: (_) {
          setState(() => _pressed = false);
          widget.onUp();
        },
        child: _visual(),
      );
    }

    // ── EDIT MODE ────────────────────────────────────────────────────────────
    // GestureDetector.onTap opens the editor.
    // LongPressDraggable lets you drag to reorder.
    return LongPressDraggable<int>(
      data: widget.cell.trackId,
      delay: const Duration(milliseconds: 350),
      feedback: _dragFeedback(),
      childWhenDragging: Opacity(
        opacity: 0.15,
        child: _visual(showEditIcon: true),
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != widget.cell.trackId,
        onAcceptWithDetails:     (d) => widget.onDrop(d.data),
        builder: (ctx, candidates, _) => GestureDetector(
          onTap: widget.onEdit,
          child: _visual(
            isTarget:     candidates.isNotEmpty,
            showEditIcon: true,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cell editor dialog
// ---------------------------------------------------------------------------

class _CellEditor extends StatefulWidget {
  final PadCell cell;
  const _CellEditor({required this.cell});

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final TextEditingController _labelCtrl;
  late int _colorValue;
  late int _colSpan;
  late int _rowSpan;

  static const _presetColors = [
    0xFF69F0AE, 0xFF4FC3F7, 0xFFFFB74D, 0xFFCE93D8,
    0xFFEF9A9A, 0xFFA5D6A7, 0xFFFFF176, 0xFFB0BEC5,
    0xFFFF8A65, 0xFF80DEEA, 0xFFF48FB1, 0xFFE6EE9C,
  ];

  @override
  void initState() {
    super.initState();
    _labelCtrl  = TextEditingController(text: widget.cell.label);
    _colorValue = widget.cell.colorValue;
    _colSpan    = widget.cell.colSpan.clamp(1, kPadColumns);
    _rowSpan    = widget.cell.rowSpan.clamp(1, 4);
  }

  @override
  void dispose() { _labelCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Edit Pad', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            TextField(
              controller: _labelCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Label',
                labelStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 16),

            // Color
            const Text('Color', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _presetColors.map((c) {
                final sel = c == _colorValue;
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Size
            const Text('Size', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            _SizePicker(
              colSpan: _colSpan,
              rowSpan: _rowSpan,
              onChanged: (cs, rs) => setState(() { _colSpan = cs; _rowSpan = rs; }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, widget.cell.copyWith(
            label:      _labelCtrl.text.trim().isEmpty
                            ? widget.cell.label
                            : _labelCtrl.text.trim(),
            colorValue: _colorValue,
            colSpan:    _colSpan,
            rowSpan:    _rowSpan,
          )),
          child: const Text('Save', style: TextStyle(color: Colors.greenAccent)),
        ),
      ],
    );
  }
}

class _SizePicker extends StatelessWidget {
  final int colSpan, rowSpan;
  final void Function(int cs, int rs) onChanged;

  const _SizePicker({
    required this.colSpan, required this.rowSpan, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const sizes = [(1, 1), (2, 1), (1, 2), (2, 2)];
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: sizes.map(((int, int) s) {
        final (cs, rs) = s;
        final sel = cs == colSpan && rs == rowSpan;
        return GestureDetector(
          onTap: () => onChanged(cs, rs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width:  cs * 32.0 + (cs - 1) * 4.0,
            height: rs * 22.0 + (rs - 1) * 4.0,
            decoration: BoxDecoration(
              color: sel ? Colors.greenAccent.withAlpha(40) : Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: sel ? Colors.greenAccent : Colors.white24,
                width: sel ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text('$cs×$rs',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: sel ? Colors.greenAccent : Colors.white38,
                )),
            ),
          ),
        );
      }).toList(),
    );
  }
}
