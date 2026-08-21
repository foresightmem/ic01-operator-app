class CalibrationJsonObjectAssembler {
  final _buffer = StringBuffer();

  List<String> addChunk(String chunk) {
    if (chunk.isEmpty) return const [];

    final trimmed = chunk.trimLeft();
    if (_buffer.isNotEmpty && trimmed.startsWith('{"type"')) {
      final pending = _buffer.toString();
      if (_extractCompleteObjects(pending).isEmpty) {
        _buffer.clear();
      }
    }

    _buffer.write(chunk);
    final buffered = _buffer.toString();
    final objects = _extractCompleteObjects(buffered);
    if (objects.isEmpty) return const [];

    _buffer.clear();
    if (objects.remaining.isNotEmpty) {
      _buffer.write(objects.remaining);
    }
    return objects.values;
  }

  void clear() => _buffer.clear();
}

class _ExtractionResult {
  const _ExtractionResult(this.values, this.remaining);

  final List<String> values;
  final String remaining;

  bool get isEmpty => values.isEmpty;
}

_ExtractionResult _extractCompleteObjects(String input) {
  final values = <String>[];
  var start = -1;
  var depth = 0;
  var inString = false;
  var escaped = false;
  var consumedUntil = 0;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (start < 0) {
      if (char == '{') {
        start = i;
        depth = 1;
      } else {
        consumedUntil = i + 1;
      }
      continue;
    }

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char == '\\') {
      escaped = inString;
      continue;
    }

    if (char == '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        values.add(input.substring(start, i + 1));
        consumedUntil = i + 1;
        start = -1;
      }
    }
  }

  return _ExtractionResult(values, input.substring(consumedUntil));
}
