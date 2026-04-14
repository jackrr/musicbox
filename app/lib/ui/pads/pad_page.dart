import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/sequencer_provider.dart';

// Fixed number of columns in every pad layout.
const int kPadColumns = 2;
const double kPadGap  = 10.0;
// Visual aspect ratio for a 1×1 cell (width : height).
const double kCellAspect = 1.5;

class PadPage extends ConsumerStatefulWidget {
  const PadPage({super.key});

  @override
  ConsumerState<PadPage> createState() => _PadPageState();
}

class _PadPageState extends ConsumerState<PadPage> {
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

  void _onPadUp(int trackId) {
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
      final name = nameCtrl.text.trim().isEmpty ? 'Layout' : nameCtrl.text.trim();
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

  void _swapCells(int layoutIdx, int fromIdx, int toIdx) {
    final project = ref.read(projectProvider).value;
    if (project == null) return;
    final layoutIndex = layoutIdx.clamp(0, project.padLayouts.length - 1);
    final cells = List<PadCell>.from(project.padLayouts[layoutIndex].cells);
    if (fromIdx < 0 || toIdx < 0 || fromIdx >= cells.length || toIdx >= cells.length) return;
    final tmp = cells[fromIdx];
    cells[fromIdx] = cells[toIdx];
    cells[toIdx]   = tmp;
    for (var i = 0; i < cells.length; i++) {
      ref.read(projectProvider.notifier).updatePadCell(layoutIndex, i, cells[i]);
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
                _LayoutPicker(
                  layouts:        project.padLayouts,
                  activeIdx:      layoutIdx,
                  recordMode:     _recordMode,
                  onSelect:       (i) => ref.read(projectProvider.notifier)
                                           .setActivePadLayout(i),
                  onAdd:          () => _addLayout(context),
                  onToggleRecord: () => setState(() => _recordMode = !_recordMode),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _PadGrid(
                      layout:    layout,
                      layoutIdx: layoutIdx,
                      onDown:    _onPadDown,
                      onUp:      _onPadUp,
                      onEdit:    (cellIdx, cell) =>
                          _editCell(context, layoutIdx, cellIdx, cell),
                      onSwap:    (a, b) => _swapCells(layoutIdx, a, b),
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
                      color: sel
                          ? Colors.greenAccent.withAlpha(30)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: sel ? Colors.greenAccent : Colors.white24,
                      ),
                    ),
                    child: Text(
                      layouts[i].name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: sel ? Colors.greenAccent : Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
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
          GestureDetector(
            onTap: onToggleRecord,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: recordMode
                    ? Colors.redAccent.withAlpha(40)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: recordMode ? Colors.redAccent : Colors.white24),
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
// Grid layout engine
//
// Computes CSS-grid-style auto-placement for variable-span cells.
// Returns a list of (row, col, colSpan, rowSpan) placements in cell order.
// ---------------------------------------------------------------------------

class _Placement {
  final int row, col;
  const _Placement(this.row, this.col);
}

List<_Placement> _computePlacements(List<PadCell> cells) {
  // occupied[row] is a bitmask of occupied columns (up to kPadColumns bits)
  final occupied = <int>[0]; // one row initially

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
// Pad grid widget
// ---------------------------------------------------------------------------

class _PadGrid extends StatelessWidget {
  final PadLayout layout;
  final int layoutIdx;
  final ValueChanged<int> onDown;
  final ValueChanged<int> onUp;
  final void Function(int cellIdx, PadCell cell) onEdit;
  final void Function(int fromIdx, int toIdx) onSwap;

  const _PadGrid({
    required this.layout,
    required this.layoutIdx,
    required this.onDown,
    required this.onUp,
    required this.onEdit,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final cells      = layout.cells;
    final placements = _computePlacements(cells);
    final numRows    = placements.isEmpty
        ? 1
        : placements.map((p) {
            final i = placements.indexOf(p);
            return p.row + cells[i].rowSpan.clamp(1, 8);
          }).reduce((a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth  = constraints.maxWidth;
        final cellW = (totalWidth - (kPadColumns - 1) * kPadGap) / kPadColumns;
        final cellH = cellW / kCellAspect;
        final totalHeight = numRows * cellH + (numRows - 1) * kPadGap;

        return SizedBox(
          width:  totalWidth,
          height: totalHeight,
          child: Stack(
            children: [
              for (var i = 0; i < cells.length; i++)
                _positionedPad(
                  index:     i,
                  cell:      cells[i],
                  placement: placements[i],
                  cellW:     cellW,
                  cellH:     cellH,
                  cells:     cells,
                  placements: placements,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedPad({
    required int index,
    required PadCell cell,
    required _Placement placement,
    required double cellW,
    required double cellH,
    required List<PadCell> cells,
    required List<_Placement> placements,
  }) {
    final cs = cell.colSpan.clamp(1, kPadColumns);
    final rs = cell.rowSpan.clamp(1, 8);
    final left   = placement.col * (cellW + kPadGap);
    final top    = placement.row * (cellH + kPadGap);
    final width  = cs * cellW + (cs - 1) * kPadGap;
    final height = rs * cellH + (rs - 1) * kPadGap;

    return Positioned(
      left: left, top: top,
      width: width, height: height,
      child: _PadTile(
        cell:      cell,
        cellIndex: index,
        allCells:  cells,
        placements: placements,
        onDown:    () => onDown(cell.trackId),
        onUp:      () => onUp(cell.trackId),
        onEdit:    () => onEdit(index, cell),
        onDrop:    (fromTrackId) {
          // Find cell index by trackId
          final fromIdx = cells.indexWhere((c) => c.trackId == fromTrackId);
          if (fromIdx >= 0) onSwap(fromIdx, index);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual draggable pad tile
// ---------------------------------------------------------------------------

class _PadTile extends StatefulWidget {
  final PadCell cell;
  final int cellIndex;
  final List<PadCell> allCells;
  final List<_Placement> placements;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onEdit;
  final ValueChanged<int> onDrop; // called with the dragged trackId

  const _PadTile({
    required this.cell,
    required this.cellIndex,
    required this.allCells,
    required this.placements,
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

  @override
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onDown();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onUp();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onUp();
      },
      onLongPress: widget.onEdit,
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != widget.cell.trackId,
        onAcceptWithDetails: (d) => widget.onDrop(d.data),
        builder: (ctx, candidates, _) {
          final isTarget = candidates.isNotEmpty;
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_note, color: _color, size: 26),
                const SizedBox(height: 4),
                Text(
                  widget.cell.label,
                  style: TextStyle(
                    fontSize: 13,
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
      delay: const Duration(milliseconds: 400),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: Container(
            width:  110,
            height: 70,
            decoration: BoxDecoration(
              color: _color.withAlpha(90),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _color, width: 2),
            ),
            child: Center(
              child: Text(
                widget.cell.label,
                style: TextStyle(
                  color: _color, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.2, child: tile),
      child: tile,
    );
  }
}

// ---------------------------------------------------------------------------
// Cell editor dialog — edit label, color, colSpan, rowSpan
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
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

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

            // Color picker
            const Text('Color', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _presetColors.map((c) {
                final selected = c == _colorValue;
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Size picker
            const Text('Size', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
            _SizePicker(
              colSpan: _colSpan,
              rowSpan: _rowSpan,
              onChanged: (cs, rs) => setState(() {
                _colSpan = cs;
                _rowSpan = rs;
              }),
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
          onPressed: () => Navigator.pop(
            context,
            widget.cell.copyWith(
              label:      _labelCtrl.text.trim().isEmpty
                              ? widget.cell.label
                              : _labelCtrl.text.trim(),
              colorValue: _colorValue,
              colSpan:    _colSpan,
              rowSpan:    _rowSpan,
            ),
          ),
          child: const Text('Save', style: TextStyle(color: Colors.greenAccent)),
        ),
      ],
    );
  }
}

// Grid showing all supported size combinations (1×1, 1×2, 2×1, 2×2).
class _SizePicker extends StatelessWidget {
  final int colSpan;
  final int rowSpan;
  final void Function(int cs, int rs) onChanged;

  const _SizePicker({
    required this.colSpan,
    required this.rowSpan,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Offer sizes: 1×1, 2×1 (wide), 1×2 (tall), 2×2 (large)
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
              child: Text(
                '$cs×$rs',
                style: TextStyle(
                  fontSize: 10,
                  color: sel ? Colors.greenAccent : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
