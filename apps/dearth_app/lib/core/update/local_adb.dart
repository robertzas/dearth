import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AdbException implements Exception {
  AdbException(this.message);
  final String message;

  @override
  String toString() => 'ADB: $message';
}

/// Just enough of the ADB host protocol to run one shell command on this
/// device's own adbd, for frames whose ROM leaves network ADB open without
/// authorization (the JT215M: root, port 5555). That's how a display under
/// FreeKiosk installs its own updates without a prompt (SPEC §15.3): Dearth
/// isn't Device Owner, and lock task keeps Android's installer off the
/// screen. Devices that ask for authorization (every phone) aren't
/// supported: [shell] fails, and the app uses Android's installer instead.
///
/// The protocol (AOSP `adb/protocol.txt`): 24-byte little-endian headers
/// (command, arg0, arg1, data length, data checksum, command ^ 0xffffffff),
/// CNXN to connect, OPEN a `shell:` service, WRTE/OKAY for its output, CLSE.
class LocalAdb {
  LocalAdb({this.host = '127.0.0.1', this.port = 5555, this.connectTimeout = const Duration(seconds: 3)});
  final String host;
  final int port;
  final Duration connectTimeout;

  static const _cnxn = 0x4e584e43;
  static const _auth = 0x48545541;
  static const _open = 0x4e45504f;
  static const _okay = 0x59414b4f;
  static const _clse = 0x45534c43;
  static const _wrte = 0x45545257;
  static const _localId = 1;

  /// Runs [command] in adbd's shell and returns what it printed. Throws an
  /// [AdbException] when adbd isn't there, asks for authorization, or
  /// doesn't finish within [timeout].
  Future<String> shell(String command, {Duration timeout = const Duration(seconds: 20)}) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException catch (e) {
      throw AdbException('nothing on $host:$port (${e.osError?.message ?? e.message})');
    }
    final reader = _Reader(socket);
    try {
      return await _session(socket, reader, command).timeout(timeout, onTimeout: () => throw AdbException('no answer in ${timeout.inSeconds} s'));
    } finally {
      socket.destroy();
      unawaited(reader.cancel());
    }
  }

  Future<String> _session(Socket socket, _Reader reader, String command) async {
    socket.add(packet(_cnxn, 0x01000000, 256 * 1024, utf8.encode('host::\x00')));
    final hello = await reader.next();
    if (hello.command == _auth) throw AdbException('adbd asks for authorization');
    if (hello.command != _cnxn) throw AdbException('unexpected answer to CNXN');
    socket.add(packet(_open, _localId, 0, utf8.encode('shell:$command\x00')));
    final out = BytesBuilder(copy: false);
    int? remote;
    while (true) {
      final p = await reader.next();
      switch (p.command) {
        case _okay:
          remote = p.arg0;
        case _wrte:
          out.add(p.data);
          socket.add(packet(_okay, _localId, p.arg0, const []));
        case _clse:
          if (remote != null) socket.add(packet(_clse, _localId, remote, const []));
          return utf8.decode(out.takeBytes(), allowMalformed: true);
      }
    }
  }

  /// One message: the header, then [data].
  static Uint8List packet(int command, int arg0, int arg1, List<int> data) {
    final b = ByteData(24 + data.length);
    var sum = 0;
    for (final x in data) {
      sum = (sum + x) & 0xffffffff;
    }
    b
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, data.length, Endian.little)
      ..setUint32(16, sum, Endian.little)
      ..setUint32(20, command ^ 0xffffffff, Endian.little);
    final bytes = b.buffer.asUint8List();
    bytes.setRange(24, bytes.length, data);
    return bytes;
  }
}

class AdbPacket {
  AdbPacket(this.command, this.arg0, this.arg1, this.data);
  final int command;
  final int arg0;
  final int arg1;
  final Uint8List data;
}

/// Whole messages out of the socket's chunks.
class _Reader {
  _Reader(Stream<Uint8List> s) : _it = StreamIterator(s);
  final StreamIterator<Uint8List> _it;
  Uint8List _pending = Uint8List(0);

  Future<Uint8List> _take(int n) async {
    while (_pending.length < n) {
      if (!await _it.moveNext()) throw AdbException('adbd closed the connection');
      _pending = Uint8List.fromList([..._pending, ..._it.current]);
    }
    final out = Uint8List.fromList(_pending.sublist(0, n));
    _pending = _pending.sublist(n);
    return out;
  }

  Future<AdbPacket> next() async {
    final h = ByteData.sublistView(await _take(24));
    final length = h.getUint32(12, Endian.little);
    if (length > 1024 * 1024) throw AdbException('message too large');
    return AdbPacket(h.getUint32(0, Endian.little), h.getUint32(4, Endian.little), h.getUint32(8, Endian.little), length == 0 ? Uint8List(0) : await _take(length));
  }

  Future<void> cancel() => _it.cancel();
}
