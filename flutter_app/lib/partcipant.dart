import 'dart:async';
import 'dart:typed_data';

import 'package:peerdart/peerdart.dart';

class Participant {
  late final Peer _peer;

  Participant(String id) {
    _peer = Peer(id: id);
  }

  Future<Connection> connect(String id) async {
    final connection = _peer.connect(id);
    await connection.on("open").first;
    return Connection(connection);
  }

  Future<Connection> listen() async {
    final connection = await _peer.on<DataConnection>("connection").first;
    return Connection(connection);
  }
}

class Connection {
  final DataConnection _connection;

  Connection(this._connection) {
    _connection.on("close").listen((_) {
      print('Closed');
    });
  }

  Future<void> sendUint8List(Uint8List data) async {
    if (_connection.open) {
      await _connection.sendBinary(data);
    }
  }

  Future<void> send(dynamic data) => _connection.send(data);

  Stream<dynamic> get data => _connection.on("data");

  void close() {
    _connection.close();
  }
}
