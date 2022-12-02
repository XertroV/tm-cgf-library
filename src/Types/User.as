class User {
  /* Properties // Mixin: Default Properties */
  private string _uid;
  private string _username;
  private float _last_seen;
  private MaybeOfString@ _secret;

  /* Methods // Mixin: Default Constructor */
  User(const string &in uid, const string &in username, float last_seen, MaybeOfString@ secret) {
    this._uid = uid;
    this._username = username;
    this._last_seen = last_seen;
    @this._secret = secret;
  }

  /* Methods // Mixin: ToFrom JSON Object */
  User(const Json::Value@ j) {
    this._uid = string(j["uid"]);
    this._username = string(j["username"]);
    this._last_seen = float(j["last_seen"]);
    @this._secret = MaybeOfString(j["secret"]);
  }

  Json::Value@ ToJson() {
    Json::Value@ j = Json::Object();
    j["uid"] = _uid;
    j["username"] = _username;
    j["last_seen"] = _last_seen;
    j["secret"] = _secret.ToJson();
    return j;
  }

  void OnFromJsonError(const Json::Value@ j) const {
    warn('Parsing json failed: ' + Json::Write(j));
    throw('Failed to parse JSON: ' + getExceptionInfo());
  }

  /* Methods // Mixin: Getters */
  const string get_uid() const {
    return this._uid;
  }

  const string get_username() const {
    return this._username;
  }

  float get_last_seen() const {
    return this._last_seen;
  }

  MaybeOfString@ get_secret() const {
    return this._secret;
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'User('
      + string::Join({'uid=' + uid, 'username=' + username, 'last_seen=' + tostring(last_seen)}, ', ')
      + ')';
  }

  /* Methods // Mixin: Op Eq */
  bool opEquals(const User@ &in other) {
    if (other is null) {
      return false; // this obj can never be null.
    }
    return true
      && _uid == other.uid
      && _username == other.username
      ;
  }
}
