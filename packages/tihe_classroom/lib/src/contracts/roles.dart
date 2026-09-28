import 'json.dart';

/// Roles inside one class (docs/11-live-classroom.md §3). Persian labels are what the UI shows.
enum ClassRole {
  host('host', 'میزبان', 4),
  cohost('cohost', 'دستیار', 3),
  presenter('presenter', 'ارائه‌دهنده', 2),
  participant('participant', 'شرکت‌کننده', 1),
  recorder('recorder', 'ضبط', 0);

  const ClassRole(this.wire, this.labelFa, this.rank);
  final String wire;
  final String labelFa;
  final int rank;

  static ClassRole fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);

  bool outranks(ClassRole other) => other != recorder && rank > other.rank;
}

const assignableRoles = [
  ClassRole.host,
  ClassRole.cohost,
  ClassRole.presenter,
  ClassRole.participant,
];

enum Capability {
  publishAudio('publish.audio', 'میکروفون'),
  publishVideo('publish.video', 'دوربین'),
  publishScreen('publish.screen', 'اشتراک صفحه'),
  whiteboardDraw('whiteboard.draw', 'نوشتن روی تخته'),
  whiteboardManage('whiteboard.manage', 'مدیریت تخته'),
  chatSend('chat.send', 'ارسال پیام'),
  handRaise('hand.raise', 'بالا بردن دست'),
  participantsManage('participants.manage', 'مدیریت شرکت‌کنندگان'),
  rolesAssign('roles.assign', 'تعیین نقش'),
  layoutChange('layout.change', 'تغییر چیدمان'),
  recordingControl('recording.control', 'کنترل ضبط'),
  classEnd('class.end', 'پایان کلاس');

  const Capability(this.wire, this.labelFa);
  final String wire;
  final String labelFa;

  static Capability fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);
}

/// What a host may hand to one person (services/live GRANTABLE_CAPABILITIES).
const grantableCapabilities = [
  Capability.publishAudio,
  Capability.publishVideo,
  Capability.publishScreen,
  Capability.whiteboardDraw,
  Capability.whiteboardManage,
  Capability.chatSend,
  Capability.handRaise,
];

List<Capability> capsFromJson(Object? json) => [
  for (final c in json as List) Capability.fromWire(c),
];
List<String> capsToJson(List<Capability> caps) => [
  for (final c in caps) c.wire,
];

class RoomPolicy {
  const RoomPolicy({
    required this.participantsCanUnmute,
    required this.participantsCanStartVideo,
    required this.participantsCanShareScreen,
    required this.participantsCanDraw,
    required this.participantsCanChat,
    required this.handRaiseEnabled,
    required this.locked,
  });

  factory RoomPolicy.fromJson(Json j) => RoomPolicy(
    participantsCanUnmute: j['participantsCanUnmute'] as bool,
    participantsCanStartVideo: j['participantsCanStartVideo'] as bool,
    participantsCanShareScreen: j['participantsCanShareScreen'] as bool,
    participantsCanDraw: j['participantsCanDraw'] as bool,
    participantsCanChat: j['participantsCanChat'] as bool,
    handRaiseEnabled: j['handRaiseEnabled'] as bool,
    locked: j['locked'] as bool,
  );

  final bool participantsCanUnmute;
  final bool participantsCanStartVideo;
  final bool participantsCanShareScreen;
  final bool participantsCanDraw;
  final bool participantsCanChat;
  final bool handRaiseEnabled;
  final bool locked;

  Json toJson() => {
    'participantsCanUnmute': participantsCanUnmute,
    'participantsCanStartVideo': participantsCanStartVideo,
    'participantsCanShareScreen': participantsCanShareScreen,
    'participantsCanDraw': participantsCanDraw,
    'participantsCanChat': participantsCanChat,
    'handRaiseEnabled': handRaiseEnabled,
    'locked': locked,
  };
}

/// Persian labels for the host's policy toggles, in the order the host menu shows them.
const policyLabelsFa = {
  'participantsCanUnmute': 'روشن کردن میکروفون',
  'participantsCanStartVideo': 'روشن کردن دوربین',
  'participantsCanShareScreen': 'اشتراک صفحه',
  'participantsCanDraw': 'نوشتن روی تخته',
  'participantsCanChat': 'گفتگو',
  'handRaiseEnabled': 'بالا بردن دست',
  'locked': 'قفل ورود به کلاس',
};
