// ignore_for_file: public_member_api_docs
/// シグナリング接続時に指定する simulcast_request_rid に該当する enum。
enum SimulcastRequestRid {
  /// none
  none('none'),

  /// r0
  r0('r0'),

  /// r1
  r1('r1'),

  /// r2
  r2('r2');

  /// @nodoc
  const SimulcastRequestRid(this.value);

  final String value;

  static SimulcastRequestRid? fromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final rid in values) {
      if (rid.value == value) {
        return rid;
      }
    }
    return null;
  }
}

/// シグナリング接続時に指定する spotlight 用 RID に該当する enum。
enum SpotlightRid {
  /// none
  none('none'),

  /// r0
  r0('r0'),

  /// r1
  r1('r1'),

  /// r2
  r2('r2');

  /// @nodoc
  const SpotlightRid(this.value);

  final String value;

  static SpotlightRid? fromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final rid in values) {
      if (rid.value == value) {
        return rid;
      }
    }
    return null;
  }
}
