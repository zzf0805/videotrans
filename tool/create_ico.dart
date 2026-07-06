import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.length < 3 || args.length.isEven) {
    stderr.writeln(
      'Usage: dart tool/create_ico.dart output.ico size png [size png ...]',
    );
    exit(64);
  }

  final output = File(args[0]);
  final entries = <_IconEntry>[];
  for (var i = 1; i < args.length; i += 2) {
    final size = int.parse(args[i]);
    final bytes = File(args[i + 1]).readAsBytesSync();
    entries.add(_IconEntry(size: size, bytes: bytes));
  }

  final data = BytesBuilder();
  _writeUint16(data, 0);
  _writeUint16(data, 1);
  _writeUint16(data, entries.length);

  var imageOffset = 6 + entries.length * 16;
  for (final entry in entries) {
    data.addByte(entry.size >= 256 ? 0 : entry.size);
    data.addByte(entry.size >= 256 ? 0 : entry.size);
    data.addByte(0);
    data.addByte(0);
    _writeUint16(data, 1);
    _writeUint16(data, 32);
    _writeUint32(data, entry.bytes.length);
    _writeUint32(data, imageOffset);
    imageOffset += entry.bytes.length;
  }

  for (final entry in entries) {
    data.add(entry.bytes);
  }
  output.writeAsBytesSync(data.toBytes(), flush: true);
}

void _writeUint16(BytesBuilder data, int value) {
  data.addByte(value & 0xff);
  data.addByte((value >> 8) & 0xff);
}

void _writeUint32(BytesBuilder data, int value) {
  data.addByte(value & 0xff);
  data.addByte((value >> 8) & 0xff);
  data.addByte((value >> 16) & 0xff);
  data.addByte((value >> 24) & 0xff);
}

class _IconEntry {
  const _IconEntry({required this.size, required this.bytes});

  final int size;
  final Uint8List bytes;
}
