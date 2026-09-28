import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../contracts.dart';

enum GatewayStatus { connecting, online, reconnecting, closed }

/// The result of a command: the server applied it, refused it (with a Persian reason), or the
/// connection dropped before it answered.
sealed class CommandOutcome {
  const CommandOutcome();
}

class Accepted extends CommandOutcome {
  const Accepted();
}

class Refused extends CommandOutcome {
  const Refused(this.error);
  final GatewayError error;
}

class NoAnswer extends CommandOutcome {
  const NoAnswer();
}

/// A WebSocket-like channel. Injected so tests drive the client without a network.
abstract class GatewayChannel {
  Stream<Object?> get stream;
  void send(String data);
  Future<void> close([int? code]);

  /// The close code once the stream is done.
  int? get closeCode;
}

typedef GatewayConnector = Future<GatewayChannel> Function(Uri url);

class _WebSocketGatewayChannel implements GatewayChannel {
  _WebSocketGatewayChannel(this._ws);
  final WebSocketChannel _ws;

  @override
  Stream<Object?> get stream => _ws.stream;
  @override
  void send(String data) => _ws.sink.add(data);
  @override
  Future<void> close([int? code]) => _ws.sink.close(code);
  @override
  int? get closeCode => _ws.closeCode;
}

Future<GatewayChannel> connectWebSocket(Uri url) async {
  final ws = WebSocketChannel.connect(url);
  await ws.ready;
  return _WebSocketGatewayChannel(ws);
}

/// Adapts a [StreamChannel] (tests) to [GatewayChannel].
class StreamGatewayChannel implements GatewayChannel {
  StreamGatewayChannel(this._channel);
  final StreamChannel<Object?> _channel;
  @override
  int? closeCode;

  @override
  Stream<Object?> get stream => _channel.stream;
  @override
  void send(String data) => _channel.sink.add(data);
  @override
  Future<void> close([int? code]) async {
    closeCode = code;
    await _channel.sink.close();
  }
}

/// The classroom WebSocket, from the client's side (ADR-0010).
///
/// - Says hello with a ticket, and on every reconnect with the last sequence number it applied,
///   so the server replays only what was missed.
/// - Reconnects with backoff after network loss, fetching a fresh ticket each time (tickets
///   live two minutes).
/// - Does **not** reconnect after the server says goodbye for good: removed, ended, or joined
///   from another device. Those arrive on [closures].
class GatewayClient {
  GatewayClient({
    required this.url,
    required this.freshTicket,
    String? firstTicket,
    GatewayConnector? connect,
    this.ackTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 25),
  }) : _connect = connect ?? connectWebSocket,
       _ticket = firstTicket;

  final Uri url;

  /// Joins again for a new ticket — the only credential the gateway accepts.
  final Future<String> Function() freshTicket;
  final GatewayConnector _connect;
  final Duration ackTimeout;
  final Duration pingInterval;

  String? _ticket;
  GatewayChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  int _counter = 0;
  bool _closed = false;
  bool _authRetried = false;
  int? lastSeq;

  final _messages = StreamController<ServerMessage>.broadcast();
  final _closures = StreamController<GatewayError>.broadcast();
  final _pending = <String, Completer<CommandOutcome>>{};
  final status = ValueNotifier(GatewayStatus.connecting);

  /// Welcome, events and previews, in order.
  Stream<ServerMessage> get messages => _messages.stream;

  /// Why the server ended the connection for good.
  Stream<GatewayError> get closures => _closures.stream;

  static const _terminal = {
    GatewayCloseCodes.removed,
    GatewayCloseCodes.joinedElsewhere,
    GatewayCloseCodes.classEnded,
    GatewayCloseCodes.protocolError,
  };

  Future<void> open() => _open();

  Future<void> _open() async {
    if (_closed) return;
    status.value = _attempt == 0
        ? GatewayStatus.connecting
        : GatewayStatus.reconnecting;
    try {
      final ticket = _ticket ?? await freshTicket();
      _ticket = null; // single use: a reconnect always fetches a new one
      final channel = await _connect(url);
      if (_closed) {
        await channel.close(1000);
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onDone(channel.closeCode),
        onError: (_) => _onDone(channel.closeCode),
      );
      channel.send(jsonEncode(ClientMessages.hello(ticket, lastSeq)));
      _ping?.cancel();
      _ping = Timer.periodic(pingInterval, (_) => _send(ClientMessages.ping));
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onData(Object? data) {
    final ServerMessage msg;
    try {
      msg = ServerMessage.fromJson(asJson(jsonDecode(data as String)));
    } on Object {
      return; // a message this build does not understand is skipped, not fatal
    }
    switch (msg) {
      case Welcome(:final seq):
        _attempt = 0;
        _authRetried = false;
        lastSeq = max(lastSeq ?? 0, seq);
        status.value = GatewayStatus.online;
      case EventMessage(:final event):
        lastSeq = max(lastSeq ?? 0, event.seq);
      case Ack(:final id):
        _pending.remove(id)?.complete(const Accepted());
        return;
      case Nack(:final id, :final error):
        _pending.remove(id)?.complete(Refused(error));
        return;
      case Pong():
        return;
      case Bye(:final error):
        _closures.add(error);
      case EphemeralMessage():
        break;
    }
    _messages.add(msg);
  }

  void _onDone(int? code) {
    _ping?.cancel();
    _subscription?.cancel();
    _channel = null;
    _failPending();
    if (_closed) return;
    if (code != null && _terminal.contains(code)) {
      _closed = true;
      status.value = GatewayStatus.closed;
      return;
    }
    if (code == GatewayCloseCodes.unauthenticated && _authRetried) {
      // A fresh ticket was refused too: the account lost access; stop.
      _closed = true;
      status.value = GatewayStatus.closed;
      return;
    }
    if (code == GatewayCloseCodes.unauthenticated) _authRetried = true;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    status.value = GatewayStatus.reconnecting;
    final delay = Duration(
      milliseconds: min(10000, 500 * pow(2, _attempt).toInt()),
    );
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, _open);
  }

  void _failPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const NoAnswer());
    }
    _pending.clear();
  }

  bool _send(Json message) {
    final channel = _channel;
    if (channel == null) return false;
    channel.send(jsonEncode(message));
    return true;
  }

  /// Sends a command and waits for the server's verdict.
  Future<CommandOutcome> send(ClassroomCommand command) {
    final id = 'c${++_counter}';
    if (status.value != GatewayStatus.online ||
        !_send(ClientMessages.command(id, command))) {
      return Future.value(const NoAnswer());
    }
    final completer = Completer<CommandOutcome>();
    _pending[id] = completer;
    return completer.future.timeout(
      ackTimeout,
      onTimeout: () {
        _pending.remove(id);
        return const NoAnswer();
      },
    );
  }

  /// A whiteboard preview batch: fire and forget.
  void sendEphemeral(BoardProgress progress) {
    if (status.value == GatewayStatus.online) {
      _send(ClientMessages.ephemeral(progress));
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    status.value = GatewayStatus.closed;
    await _channel?.close(1000);
    _failPending();
    await _messages.close();
    await _closures.close();
  }
}
