import 'json.dart';

/// Stage layouts on a 12 × 12 grid, measured from the start edge (docs/11 §5). Mirrors
/// packages/contracts/src/live/layout.ts; the presets are checked against
/// fixtures/live/layout-presets.json.
const layoutGrid = 12;
const maxPods = 8;

enum PodKind {
  speaker('speaker', 'ارائه‌دهنده'),
  gallery('gallery', 'تصاویر'),
  screen('screen', 'اشتراک صفحه'),
  whiteboard('whiteboard', 'تخته سفید'),
  chat('chat', 'گفتگو'),
  participants('participants', 'شرکت‌کنندگان'),
  hands('hands', 'دست‌های بالا');

  const PodKind(this.wire, this.labelFa);
  final String wire;
  final String labelFa;

  static PodKind fromWire(Object? wire) => byWire(values, wire, (v) => v.wire);

  /// Pods that show class content, as opposed to people.
  bool get isMedia =>
      this == speaker ||
      this == gallery ||
      this == screen ||
      this == whiteboard;
}

class Pod {
  const Pod({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory Pod.fromJson(Json j) => Pod(
    id: j['id'] as String,
    kind: PodKind.fromWire(j['kind']),
    x: j['x'] as int,
    y: j['y'] as int,
    w: j['w'] as int,
    h: j['h'] as int,
  );

  final String id;
  final PodKind kind;
  final int x;
  final int y;
  final int w;
  final int h;

  int get area => w * h;

  Pod copyWith({int? x, int? y, int? w, int? h}) => Pod(
    id: id,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
  );

  bool overlaps(Pod o) =>
      x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;

  Json toJson() => {
    'id': id,
    'kind': kind.wire,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
  };

  @override
  bool operator ==(Object other) =>
      other is Pod &&
      other.id == id &&
      other.kind == kind &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(id, kind, x, y, w, h);
}

enum LayoutPreset {
  lecture('lecture'),
  presentation('presentation'),
  whiteboard('whiteboard'),
  discussion('discussion'),
  split('split'),
  qa('qa');

  const LayoutPreset(this.wire);
  final String wire;

  static LayoutPreset fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);
}

class Layout {
  const Layout({
    required this.id,
    required this.name,
    required this.preset,
    required this.pods,
  });

  factory Layout.fromJson(Json j) => Layout(
    id: j['id'] as String,
    name: j['name'] as String,
    preset: j['preset'] == null ? null : LayoutPreset.fromWire(j['preset']),
    pods: [for (final p in asJsonList(j['pods'])) Pod.fromJson(p)],
  );

  final String id;
  final String name;
  final LayoutPreset? preset;
  final List<Pod> pods;

  Pod? pod(PodKind kind) {
    for (final p in pods) {
      if (p.kind == kind) return p;
    }
    return null;
  }

  Json toJson() => {
    'id': id,
    'name': name,
    'preset': preset?.wire,
    'pods': [for (final p in pods) p.toJson()],
  };
}

/// Every reason a layout is unusable — the same rules as the server's `layoutProblems`, shown
/// live in the layout editor. Messages are Persian because the teacher reads them.
List<String> layoutProblems(List<Pod> pods) {
  final problems = <String>[];
  if (pods.isEmpty) problems.add('چیدمان باید دست‌کم یک بخش داشته باشد.');
  if (pods.length > maxPods) problems.add('حداکثر $maxPods بخش مجاز است.');
  final kinds = <PodKind>{};
  for (final p in pods) {
    if (!kinds.add(p.kind)) problems.add('بخش «${p.kind.labelFa}» تکراری است.');
    if (p.x < 0 ||
        p.y < 0 ||
        p.x + p.w > layoutGrid ||
        p.y + p.h > layoutGrid) {
      problems.add('بخش «${p.kind.labelFa}» از صفحه بیرون زده است.');
    }
  }
  for (var i = 0; i < pods.length; i++) {
    for (var j = i + 1; j < pods.length; j++) {
      if (pods[i].overlaps(pods[j])) {
        problems.add(
          '«${pods[i].kind.labelFa}» و «${pods[j].kind.labelFa}» روی هم افتاده‌اند.',
        );
      }
    }
  }
  return problems;
}

Pod _pod(PodKind kind, int x, int y, int w, int h) =>
    Pod(id: kind.wire, kind: kind, x: x, y: y, w: w, h: h);

/// The six recommended layouts — identical to LAYOUT_PRESETS in packages/contracts.
final Map<LayoutPreset, Layout> layoutPresets = {
  LayoutPreset.lecture: Layout(
    id: 'lecture',
    name: 'سخنرانی',
    preset: LayoutPreset.lecture,
    pods: [
      _pod(PodKind.speaker, 0, 0, 8, 12),
      _pod(PodKind.chat, 8, 0, 4, 7),
      _pod(PodKind.participants, 8, 7, 4, 5),
    ],
  ),
  LayoutPreset.presentation: Layout(
    id: 'presentation',
    name: 'ارائه',
    preset: LayoutPreset.presentation,
    pods: [
      _pod(PodKind.screen, 0, 0, 9, 12),
      _pod(PodKind.speaker, 9, 0, 3, 4),
      _pod(PodKind.chat, 9, 4, 3, 8),
    ],
  ),
  LayoutPreset.whiteboard: Layout(
    id: 'whiteboard',
    name: 'تخته سفید',
    preset: LayoutPreset.whiteboard,
    pods: [
      _pod(PodKind.whiteboard, 0, 0, 9, 12),
      _pod(PodKind.speaker, 9, 0, 3, 4),
      _pod(PodKind.chat, 9, 4, 3, 8),
    ],
  ),
  LayoutPreset.discussion: Layout(
    id: 'discussion',
    name: 'گفتگو',
    preset: LayoutPreset.discussion,
    pods: [
      _pod(PodKind.gallery, 0, 0, 9, 12),
      _pod(PodKind.chat, 9, 0, 3, 7),
      _pod(PodKind.hands, 9, 7, 3, 5),
    ],
  ),
  LayoutPreset.split: Layout(
    id: 'split',
    name: 'ترکیبی',
    preset: LayoutPreset.split,
    pods: [
      _pod(PodKind.screen, 0, 0, 6, 8),
      _pod(PodKind.whiteboard, 6, 0, 6, 8),
      _pod(PodKind.speaker, 0, 8, 3, 4),
      _pod(PodKind.gallery, 3, 8, 6, 4),
      _pod(PodKind.chat, 9, 8, 3, 4),
    ],
  ),
  LayoutPreset.qa: Layout(
    id: 'qa',
    name: 'پرسش و پاسخ',
    preset: LayoutPreset.qa,
    pods: [
      _pod(PodKind.speaker, 0, 0, 7, 8),
      _pod(PodKind.gallery, 0, 8, 7, 4),
      _pod(PodKind.hands, 7, 0, 5, 5),
      _pod(PodKind.chat, 7, 5, 5, 7),
    ],
  ),
};

/// What each preset is for, shown under its thumbnail in the layout picker.
const layoutPresetHintsFa = {
  LayoutPreset.lecture: 'تصویر استاد در مرکز توجه',
  LayoutPreset.presentation: 'اسلاید یا نرم‌افزار، با تصویر کوچک استاد',
  LayoutPreset.whiteboard: 'حل مسئله روی تخته',
  LayoutPreset.discussion: 'گفت‌وگوی گروهی با دوربین‌ها',
  LayoutPreset.split: 'یادداشت روی تخته کنار اسلاید',
  LayoutPreset.qa: 'پرسش و پاسخ پایان کلاس',
};
