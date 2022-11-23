class Message {
  /* Properties // Mixin: Default Properties */
  private string _type;
  private Json::Value@ _payload;
  private string _visibility;
  private User@ _from;
  private float _ts;

  /* Methods // Mixin: Default Constructor */
  Message(const string &in type, Json::Value@ payload, const string &in visibility, User@ from, float ts) {
    this._type = type;
    @this._payload = payload;
    this._visibility = visibility;
    @this._from = from;
    this._ts = ts;
  }

  /* Methods // Mixin: ToFrom JSON Object */
  Message(const Json::Value@ j) {
    this._type = string(j["type"]);
    @this._payload = j["payload"];
    this._visibility = string(j["visibility"]);
    @this._from = User(j["from"]);
    this._ts = float(j["ts"]);
  }

  Json::Value@ ToJson() {
    Json::Value@ j = Json::Object();
    j["type"] = _type;
    j["payload"] = _payload;
    j["visibility"] = _visibility;
    j["from"] = _from;
    j["ts"] = _ts;
    return j;
  }

  void OnFromJsonError(const Json::Value@ j) const {
    warn('Parsing json failed: ' + Json::Write(j));
    throw('Failed to parse JSON: ' + getExceptionInfo());
  }

  /* Methods // Mixin: Getters */
  const string get_type() const {
    return this._type;
  }

  Json::Value@ get_payload() const {
    return this._payload;
  }

  const string get_visibility() const {
    return this._visibility;
  }

  User@ get_from() const {
    return this._from;
  }

  float get_ts() const {
    return this._ts;
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'Message('
      + string::Join({'type=' + type, 'payload=' + Json::Write(payload), 'visibility=' + visibility, 'from=' + from.ToString(), 'ts=' + tostring(ts)}, ', ')
      + ')';
  }

  /* Methods // Mixin: Op Eq */
  bool opEquals(const Message@ &in other) {
    if (other is null) {
      return false; // this obj can never be null.
    }
    return true
      && _type == other.type
      && _payload == other.payload
      && _visibility == other.visibility
      && _from == other.from
      && _ts == other.ts
      ;
  }
}
