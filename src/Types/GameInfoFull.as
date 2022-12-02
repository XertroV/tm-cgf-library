class GameInfoFull {
  /* Properties // Mixin: Default Properties */
  private array<User@> _players;
  private uint _n_game_msgs;
  private string[][] _teams;
  private array<int> _map_list;
  private string _room;
  private string _lobby;

  /* Methods // Mixin: Default Constructor */
  GameInfoFull(const User@[] &in players, uint n_game_msgs, const string[][] &in teams, const int[] &in map_list, const string &in room, const string &in lobby) {
    this._players = players;
    this._n_game_msgs = n_game_msgs;
    this._teams = teams;
    this._map_list = map_list;
    this._room = room;
    this._lobby = lobby;
  }

  /* Methods // Mixin: ToFrom JSON Object */
  GameInfoFull(const Json::Value@ j) {
    this._players = array<User@>(j["players"].Length);
    for (uint i = 0; i < j["players"].Length; i++) {
      @this._players[i] = User(j["players"][i]);
    }
    this._n_game_msgs = uint(j["n_game_msgs"]);
    this._teams = array<array<string>>(j["teams"].Length);
    for (uint i = 0; i < j["teams"].Length; i++) {
      auto team = j["teams"][i];
      for (uint pn = 0; pn < team.Length; pn++) {
        this._teams[i].InsertLast(string(team[pn]));
      }
    }
    this._map_list = array<int>(j["map_list"].Length);
    for (uint i = 0; i < j["map_list"].Length; i++) {
      this._map_list[i] = int(j["map_list"][i]);
    }
    this._room = string(j["room"]);
    this._lobby = string(j["lobby"]);
  }

  /* Methods // Mixin: Getters */
  const User@[]@ get_players() const {
    return this._players;
  }

  uint get_n_game_msgs() const {
    return this._n_game_msgs;
  }

  const string[][]@ get_teams() const {
    return this._teams;
  }

  const int[]@ get_map_list() const {
    return this._map_list;
  }

  const string get_room() const {
    return this._room;
  }

  const string get_lobby() const {
    return this._lobby;
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'GameInfoFull('
      + string::Join({'players=' + TS_Array_User(players), 'n_game_msgs=' + tostring(n_game_msgs), 'map_list=' + TS_Array_int(map_list), 'room=' + room, 'lobby=' + lobby}, ', ')
      + ')';
  }

  private const string TS_Array_User(const array<User@> &in arr) {
    string ret = '{';
    for (uint i = 0; i < arr.Length; i++) {
      if (i > 0) ret += ', ';
      ret += arr[i].ToString();
    }
    return ret + '}';
  }

  private const string TS_Array_string(const string[] &in arr) {
    string ret = '{';
    for (uint i = 0; i < arr.Length; i++) {
      if (i > 0) ret += ', ';
      ret += arr[i];
    }
    return ret + '}';
  }

  private const string TS_Array_int(const array<int> &in arr) {
    string ret = '{';
    for (uint i = 0; i < arr.Length; i++) {
      if (i > 0) ret += ', ';
      ret += tostring(arr[i]);
    }
    return ret + '}';
  }
}
