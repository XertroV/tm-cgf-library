class RoomInfo {
  /* Properties // Mixin: Default Properties */
  private string _name;
  private uint _n_teams;
  private uint _n_players;
  private uint _player_limit;
  private MaybeOfString@ _join_code;
  private bool _is_public;
  private uint _ready_count;

  /* Methods // Mixin: Default Constructor */
  RoomInfo(const string &in name, uint n_teams, uint n_players, uint player_limit, MaybeOfString@ join_code, bool is_public, uint ready_count) {
    this._name = name;
    this._n_teams = n_teams;
    this._n_players = n_players;
    this._player_limit = player_limit;
    @this._join_code = join_code;
    this._is_public = is_public;
    this._ready_count = ready_count;
  }

  /* Methods // Mixin: ToFrom JSON Object */
  RoomInfo(const Json::Value@ j) {
    this._name = string(j["name"]);
    this._n_teams = uint(j["n_teams"]);
    this._n_players = uint(j["n_players"]);
    this._player_limit = uint(j["player_limit"]);
    @this._join_code = MaybeOfString(j["join_code"]);
    this._is_public = bool(j["is_public"]);
    this._ready_count = uint(j["ready_count"]);
  }

  Json::Value@ ToJson() {
    Json::Value@ j = Json::Object();
    j["name"] = _name;
    j["n_teams"] = _n_teams;
    j["n_players"] = _n_players;
    j["player_limit"] = _player_limit;
    j["join_code"] = _join_code.ToJson();
    j["is_public"] = _is_public;
    j["ready_count"] = _ready_count;
    return j;
  }

  void OnFromJsonError(const Json::Value@ j) const {
    warn('Parsing json failed: ' + Json::Write(j));
    throw('Failed to parse JSON: ' + getExceptionInfo());
  }

  /* Methods // Mixin: Getters */
  const string get_name() const {
    return this._name;
  }

  uint get_n_teams() const {
    return this._n_teams;
  }

  uint get_n_players() const {
    return this._n_players;
  }

  uint get_player_limit() const {
    return this._player_limit;
  }

  MaybeOfString@ get_join_code() const {
    return this._join_code;
  }

  bool get_is_public() const {
    return this._is_public;
  }

  uint get_ready_count() const {
    return this._ready_count;
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'RoomInfo('
      + string::Join({'name=' + name, 'n_teams=' + tostring(n_teams), 'n_players=' + tostring(n_players), 'player_limit=' + tostring(player_limit), 'join_code=' + join_code.GetOr(""), 'is_public=' + tostring(is_public), 'ready_count=' + tostring(ready_count)}, ', ')
      + ')';
  }

  /* Methods // Mixin: Op Eq */
  bool opEquals(const RoomInfo@ &in other) {
    if (other is null) {
      return false; // this obj can never be null.
    }
    return true
      && _name == other.name
      && _n_teams == other.n_teams
      && _n_players == other.n_players
      && _player_limit == other.player_limit
      && _join_code == other.join_code
      && _is_public == other.is_public
      && _ready_count == other.ready_count
      ;
  }
}
