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
  private string _max_difficulty;
  private float _game_start_time;
  private int _map_pack;
  private bool _started;
  private bool _use_club_room;
  private string _join_link;
  // note: game_opts will always be a mapping of string => string
  private const Json::Value@ _game_opts;
  bool _use_totd = false;
  bool maps_loaded = false;

  /* Methods // Mixin: Default Constructor */
  RoomInfo(
    const string &in name, uint n_teams, uint n_players, uint player_limit,
    MaybeOfString@ join_code, bool is_public, uint ready_count,
    uint n_maps, uint min_secs, uint max_secs, float game_start_time, bool started,
    const string &in max_difficulty,
    Json::Value@ game_opts,
    int map_pack = -1, bool use_club_room = false,
    const string &in join_link = "",
    bool use_totd = false
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
    this._max_difficulty = max_difficulty;
    this._map_pack = map_pack;
    this._game_start_time = game_start_time;
    this._started = started;
    this._use_club_room = use_club_room;
    this._join_link = join_link;
    @this._game_opts = game_opts;
    this._use_totd = use_totd;
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
    this._max_difficulty = string(j.Get("max_difficulty", "Unknown (bug)"));
    auto tmpMapPack = j['map_pack'];
    this._map_pack = tmpMapPack.GetType() == Json::Type::Null ? -1 : int(tmpMapPack);
    this._game_start_time = float(j["game_start_time"]);
    this._started = bool(j["started"]);
    this.maps_loaded = bool(j.Get("maps_loaded", false));
    this._use_club_room = bool(j.Get("use_club_room", false));
    this._use_totd = bool(j.Get("use_totd", false));
    this._join_link = string(j.Get("cr_join_link", ""));
    @this._game_opts = j.Get("game_opts", Json::Object());
    if (_game_opts.GetType() != Json::Type::Object) throw("Invalid game_opts: not an obj");
  }

  // Json::Value@ ToJson() {
  //   Json::Value@ j = Json::Object();
  //   j["name"] = _name;
  //   j["n_teams"] = _n_teams;
  //   j["n_players"] = _n_players;
  //   j["player_limit"] = _player_limit;
  //   j["join_code"] = _join_code.ToJson();
  //   j["is_public"] = _is_public;
  //   j["ready_count"] = _ready_count;
  //   j["n_maps"] = _n_maps;
  //   j["min_secs"] = _min_secs;
  //   j["max_secs"] = _max_secs;
  //   j["max_difficulty"] = _max_difficulty;
  //   j["map_pack"] = _map_pack >= 0 ? Json::Value(_map_pack) : Json::Value();
  //   j["game_opts"] = _game_opts;
  //   j["game_start_time"] = _game_start_time;
  //   j["maps_loaded"] = this.maps_loaded;
  //   j["started"] = _started;
  //   return j;
  // }

  // void OnFromJsonError(const Json::Value@ j) const {
  //   warn('Parsing json failed: ' + Json::Write(j));
  //   throw('Failed to parse JSON: ' + getExceptionInfo());
  // }

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

  const string get_max_difficulty() const {
    return this._max_difficulty;
  }

  float get_game_start_time() const {
    return this._game_start_time;
  }

  bool get_started() const {
    return this._started;
  }

  int get_map_pack() const {
    return this._map_pack;
  }

  bool get_use_club_room() const {
    return this._use_club_room;
  }

  bool get_use_totd() const {
    return this._use_totd;
  }

  const string get_join_link() const {
    return this._join_link;
  }

  void set_join_link(const string &in value) {
    this._join_link = value;
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

  bool get_WaitingForServer() const {
    return this._use_club_room && this._join_link.Length == 0;
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
}
