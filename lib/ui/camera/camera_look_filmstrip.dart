import 'package:flutter/material.dart';

const _accent = Color(0xFFFF6A00);

class CameraLookFilmstripItem {
  const CameraLookFilmstripItem({
    required this.id,
    required this.label,
    required this.index,
  });

  final String id;
  final String label;
  final int index;
}

class CameraLookFilmstrip extends StatelessWidget {
  const CameraLookFilmstrip({
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final List<CameraLookFilmstripItem> items;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  static const _palettes = <List<Color>>[
    [Color(0xFF343434), Color(0xFF111111)],
    [Color(0xFF7E715F), Color(0xFF314450)],
    [Color(0xFF8C5D34), Color(0xFF44653D)],
    [Color(0xFF826C65), Color(0xFF53606F)],
    [Color(0xFF95653C), Color(0xFF24323B)],
    [Color(0xFF5A6D58), Color(0xFF3C373B)],
    [Color(0xFF6D5368), Color(0xFF343A4A)],
    [Color(0xFF8A7656), Color(0xFF485660)],
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = item.id == selectedId;
          final palette = _palettes[item.index % _palettes.length];
          return Semantics(
            button: true,
            selected: selected,
            label: item.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => onSelected(item.id) : null,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                scale: selected ? 1 : 0.94,
                child: SizedBox(
                  width: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 76 : 68,
                        height: selected ? 76 : 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? _accent : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                          boxShadow: selected
                              ? const [
                                  BoxShadow(
                                    color: Color(0x55FF6A00),
                                    blurRadius: 14,
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: palette,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: -12,
                                bottom: -18,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                              if (item.id.isEmpty || item.id == 'original')
                                const Center(
                                  child: Icon(
                                    Icons.circle_outlined,
                                    color: Colors.white70,
                                    size: 26,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 22 : 0,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
