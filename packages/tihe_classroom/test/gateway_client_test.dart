import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// A server end the test drives by hand.
class FakeServer {
  final connections = <FakeChannel>[];
  final received = <Json>[];

  Future<GatewayChannel> connect(Uri url) async {
    final controller = StreamChannelController<Object?>(sync: true);
    controller.local.stream.listen(
      (raw) => received.add(asJson(jsonDecode(raw as String))),
    );
    final channel = FakeChannel(controller);
    connections.add(channel);
    return channel;
  }

  FakeChannel get current => connections.last;

  void send(Json message) =>
      current.controller.local.sink.add(jsonEncode(message));

  void welcome(int seq) => send({
    't': 'welcome',
    'you': {'userId': 'usr_01J8ZB00000000000000000003', 'role': 'participant'},
    'seq': seq,
    'snapshot': null,
    'replay': const [],
  });

  /// The server closes the current socket with [code].
  Future<void> close(int code) async {
    current.closeCode = code;
    await current.controller.local.sink.close();
  }
}

class FakeChannel implements GatewayChannel {
  FakeChannel(this.controller);
  final StreamChannelController<Object?> controller;

  @override
  int? closeCode;
  @override
  Stream<Object?> get stream => controller.foreign.stream;
  @override
  void send(String data) => controller.foreign.sink.add(data);
  @override
  Future<void> close([int? code]) => controller.foreign.sink.close();
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakeServer server;
  late GatewayClient client;
  late int tickets;

  setUp(() {
    server = FakeServer();
    tickets = 0;
    client = GatewayClient(
      url: Uri.parse('ws://live.test/v1/live/ws'),
      firstTicket: 'ticket-0',
      freshTicket: () async => 'ticket-${++tickets}',
      connect: server.connect,
      ackTimeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() => client.close());

  test('says hello with its ticket, and goes online on welcome', () async {
    await client.open();
    expect(server.received.single, {
      't': 'hello',
      'ticket': 'ticket-0',
      'lastSeq': null,
    });
    expect(client.status.value, GatewayStatus.connecting);
    server.welcome(19);
    await settle();
    expect(client.status.value, GatewayStatus.online);
    expect(client.lastSeq, 19);
  });

  test('resolves a command with the server\'s ack or refusal', () async {
    await client.open();
    server.welcome(1);
    await settle();

    final accepted = client.send(const RaiseHand());
    await settle();
    final id = server.received.last['id'];
    server.send({'t': 'ack', 'id': id});
    expect(await accepted, isA<Accepted>());

    final refused = client.send(const SendChat('x'));
    await settle();
    server.send({
      't': 'nack',
      'id': server.received.last['id'],
      'error': {
        'code': 'CAPABILITY_MISSING',
        'message': 'no',
        'messageFa': 'اجازه ندارید',
      },
    });
    final outcome = await refused;
    expect(
      outcome,
      isA<Refused>().having(
        (r) => r.error.messageFa,
        'messageFa',
        'اجازه ندارید',
      ),
    );
  });

  test(
    'a command gets no answer when offline or when the server stays silent',
    () async {
      expect(await client.send(const RaiseHand()), isA<NoAnswer>());
      await client.open();
      server.welcome(1);
      await settle();
      expect(await client.send(const RaiseHand()), isA<NoAnswer>());
    },
  );

  test('tracks the last sequence number from events', () async {
    await client.open();
    server.welcome(5);
    server.send({
      't': 'evt',
      'seq': 9,
      'at': '2026-09-27T07:00:00.000Z',
      'evt': {
        'type': 'wb.page.selected',
        'pageId': 'wbp_01J8ZD00000000000000000001',
      },
    });
    await settle();
    expect(client.lastSeq, 9);
  });

  test(
    'after a network drop it reconnects with a fresh ticket and its last sequence',
    () async {
      await client.open();
      server.welcome(12);
      await settle();
      await server.close(1006);
      await settle();
      expect(client.status.value, GatewayStatus.reconnecting);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(server.connections, hasLength(2));
      expect(server.received.last, {
        't': 'hello',
        'ticket': 'ticket-1',
        'lastSeq': 12,
      });
    },
  );

  test('does not reconnect after being removed, and reports why', () async {
    final closures = <GatewayError>[];
    client.closures.listen(closures.add);
    await client.open();
    server.welcome(3);
    server.send({
      't': 'bye',
      'error': {
        'code': 'REMOVED_FROM_CLASS',
        'message': 'removed',
        'messageFa': 'میزبان شما را خارج کرد',
      },
    });
    await settle();
    await server.close(GatewayCloseCodes.removed);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(closures.single.code, 'REMOVED_FROM_CLASS');
    expect(client.status.value, GatewayStatus.closed);
    expect(server.connections, hasLength(1));
  });

  test('gives up when a fresh ticket is refused too', () async {
    await client.open();
    await server.close(GatewayCloseCodes.unauthenticated);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(server.connections, hasLength(2));
    await server.close(GatewayCloseCodes.unauthenticated);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(client.status.value, GatewayStatus.closed);
    expect(server.connections, hasLength(2));
  });
}
