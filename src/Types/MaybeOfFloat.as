class MaybeOfFloat {
  /* Properties // Mixin: Default Properties */
  private float _val;
  private bool _hasVal;

  /* Methods // Mixin: JMaybes */
  MaybeOfFloat(float val) {
    _hasVal = true;
    _val = val;
  }

  MaybeOfFloat() {
    _hasVal = false;
  }

  MaybeOfFloat(const Json::Value@ j) {
    if (j is null || j.GetType() % Json::Type::Null == 0) {
      _hasVal = false;
    } else {
      _hasVal = true;
      _val = float(j);
    }
  }

  bool opEquals(const MaybeOfFloat@ &in other) {
    if (IsJust()) {
      return other.IsJust() && (_val == other.val);
    }
    return other.IsNothing();
  }

  const string ToString() {
    string ret = 'MaybeOfFloat(';
    if (IsJust()) {
      ret += '' + _val;
    }
    return ret + ')';
  }

  const string ToRowString() {
    if (!_hasVal) {
      return 'null,';
    }
    return '' + _val + ',';
  }

  private const string TRS_WrapString(const string &in s) {
    string _s = s.Replace('\n', '\\n').Replace('\r', '\\r');
    string ret = '(' + _s.Length + ':' + _s + ')';
    if (ret.Length != (3 + _s.Length + ('' + _s.Length).Length)) {
      throw('bad string length encoding. expected: ' + (3 + _s.Length + ('' + _s.Length).Length) + '; but got ' + ret.Length);
    }
    return ret;
  }

  Json::Value@ ToJson() {
    if (IsNothing()) {
      return Json::Value(); // json null
    }
    return Json::Value(_val);
  }

  float get_val() const {
    if (!_hasVal) {
      throw('Attempted to access .val of a Nothing');
    }
    return _val;
  }

  float GetOr(float _default) {
    return _hasVal ? _val : _default;
  }

  bool IsJust() const {
    return _hasVal;
  }

  bool IsSome() const {
    return IsJust();
  }

  bool IsNothing() const {
    return !_hasVal;
  }

  bool IsNone() const {
    return IsNothing();
  }
}
