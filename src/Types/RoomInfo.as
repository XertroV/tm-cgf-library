class RoomInfo {
  /* Properties // Mixin: Default Properties */
  private string _name;
  private uint _n_teams;
  private uint _n_players;
  private uint _player_limit;
  private MaybeOfString@ _join_code;
  private bool _is_public;
  private uint _ready_count;
  private uint _n_maps;
  private uint _min_secs;
  private uint _max_secs;
  private float _game_start_time;
  private bool _started;
  // note: game_opts will always be a mapping of string => string
  private const Json::Value@ _game_opts;

  /* Methods // Mixin: Default Constructor */
  RoomInfo(
    const string &in name, uint n_teams, uint n_players, uint player_limit,
    MaybeOfString@ join_code, bool is_public, uint ready_count,
    uint n_maps, uint min_secs, uint max_secs, float game_start_time, bool started,
    Json::Value@ game_opts
  ) {
    this._name = name;
    this._n_teams = n_teams;
    this._n_players = n_players;
    this._player_limit = player_limit;
    @this._join_code = join_code;
    this._is_public = is_public;
    this._ready_count = ready_count;
    this._n_maps = n_maps;
    this._min_secs = min_secs;
    this._max_secs = max_secs;
    this._game_start_time = game_start_time;
    this._started = started;
    @this._game_opts = game_opts;
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
    this._n_maps = uint(j["n_maps"]);
    this._min_secs = uint(j["min_secs"]);
    this._max_secs = uint(j["max_secs"]);
    this._game_start_time = float(j["game_start_time"]);
    this._started = bool(j["started"]);
    @this._game_opts = j["game_opts"];
    if (_game_opts.GetType() != Json::Type::Object) throw("Invalid game_opts: not an obj");
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
    j["n_maps"] = _n_maps;
    j["min_secs"] = _min_secs;
    j["max_secs"] = _max_secs;
    j["game_opts"] = _game_opts;
    j["game_start_time"] = _game_start_time;
    j["started"] = _started;
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

  void set_n_players(uint value) {
    this._n_players = value;
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

  uint get_n_maps() const {
    return this._n_maps;
  }

  uint get_min_secs() const {
    return this._min_secs;
  }

  uint get_max_secs() const {
    return this._max_secs;
  }

  float get_game_start_time() const {
    return this._game_start_time;
  }

  bool get_started() const {
    return this._started;
  }

  /**
   * custom options for the game able to be set from the client UI (not enforced by the server)
   *
   * note: game_opts will always be a mapping of string => string
   */
  const Json::Value@ get_game_opts() const {
    return this._game_opts;
  }

  // Custom props

  bool get_HasStarted() const {
    return this.started; // || (0 < game_start_time && game_start_time < float(Time::Stamp));
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'RoomInfo('
      + string::Join({
        'name=' + name, 'n_teams=' + tostring(n_teams), 'n_players=' + tostring(n_players),
        'player_limit=' + tostring(player_limit), 'join_code=' + join_code.GetOr(""), 'is_public=' + tostring(is_public),
        'ready_count=' + tostring(ready_count),
        'n_maps=' + n_maps, 'min_secs=' + min_secs, 'max_secs=' + max_secs
      }, ', ')
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
      && _n_maps == other.n_maps
      && _min_secs == other.min_secs
      && _max_secs == other.max_secs
      ;
  }
}
