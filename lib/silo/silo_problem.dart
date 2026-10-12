import 'dart:convert';

class SiloProblemError {
  final String location;
  final String code;
  final String detail;

  const SiloProblemError({required this.location, required this.code, this.detail = ''});
}

/// RFC 9457 problem body. Every Silo v2 error response carries one.
class SiloProblem {
  final String type;
  final String title;
  final int status;
  final String detail;
  final String? instance;
  final List<SiloProblemError> errors;

  const SiloProblem({
    required this.type,
    required this.title,
    required this.status,
    this.detail = '',
    this.instance,
    this.errors = const [],
  });

  String get code {
    var trimmed = type;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.substring(trimmed.lastIndexOf('/') + 1);
  }

  /// Null when [body] is not a problem document, matching Silo's
  /// decode-or-null in `toApiV2Error`.
  static SiloProblem? tryParse(String? body) {
    if (body == null || body.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final type = decoded['type'];
    final title = decoded['title'];
    final status = decoded['status'];
    if (type is! String || title is! String || status is! int) return null;
    final errors = <SiloProblemError>[];
    final rawErrors = decoded['errors'];
    if (rawErrors is List) {
      for (final raw in rawErrors) {
        if (raw is! Map) return null;
        final location = raw['location'];
        final code = raw['code'];
        if (location is! String || code is! String) return null;
        final detail = raw['detail'];
        errors.add(SiloProblemError(location: location, code: code, detail: detail is String ? detail : ''));
      }
    }
    final detail = decoded['detail'];
    final instance = decoded['instance'];
    return SiloProblem(
      type: type,
      title: title,
      status: status,
      detail: detail is String ? detail : '',
      instance: instance is String ? instance : null,
      errors: errors,
    );
  }
}

/// A Silo call answered with a status its caller does not accept.
class SiloApiException implements Exception {
  final int status;
  final SiloProblem? problem;

  const SiloApiException(this.status, [this.problem]);

  @override
  String toString() => 'SiloApiException($status${problem == null ? '' : ' ${problem!.code}'})';
}
