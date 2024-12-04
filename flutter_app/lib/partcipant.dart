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

  void send(dynamic data) => _connection.send(data);

  Future<void> sendUint8List(Uint8List data) async {
    if (_connection.open) {
      await _connection.sendBinary(data);
    }
  }

  Stream<dynamic> get data => _connection.on("data");

  Stream<Uint8List> get binaryStream => _connection.on("binary");

  void close() {
    _connection.close();
  }
}
