class LobbyInfo {
  /* Properties // Mixin: Default Properties */
  private string _name;
  private uint _n_clients;
  private uint _n_rooms;
  private uint _n_public_rooms;
  private array<RoomInfo@> _rooms;

  /* Methods // Mixin: Default Constructor */
  LobbyInfo(const string &in name, uint n_clients, uint n_rooms, uint n_public_rooms, const RoomInfo@[] &in rooms) {
    this._name = name;
    this._n_clients = n_clients;
    this._n_rooms = n_rooms;
    this._n_public_rooms = n_public_rooms;
    this._rooms = rooms;
  }

  /* Methods // Mixin: ToFrom JSON Object */
  LobbyInfo(const Json::Value@ j) {
    this._name = string(j["name"]);
    this._n_clients = uint(j["n_clients"]);
    this._n_rooms = uint(j["n_rooms"]);
    this._n_public_rooms = uint(j["n_public_rooms"]);
    this._rooms = array<RoomInfo@>(j["rooms"].Length);
    for (uint i = 0; i < j["rooms"].Length; i++) {
      @this._rooms[i] = RoomInfo(j["rooms"][i]);
    }
  }

  Json::Value@ ToJson() {
    Json::Value@ j = Json::Object();
    j["name"] = _name;
    j["n_clients"] = _n_clients;
    j["n_rooms"] = _n_rooms;
    j["n_public_rooms"] = _n_public_rooms;
    Json::Value@ _tmp_rooms = Json::Array();
    for (uint i = 0; i < _rooms.Length; i++) {
      auto v = _rooms[i];
      _tmp_rooms.Add(v.ToJson());
    }
    j["rooms"] = _tmp_rooms;
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

  uint get_n_clients() const {
    return this._n_clients;
  }

  void set_n_clients(uint value) {
    this._n_clients = value;
  }

  uint get_n_rooms() const {
    return this._n_rooms;
  }

  uint get_n_public_rooms() const {
    return this._n_public_rooms;
  }

  const RoomInfo@[]@ get_rooms() const {
    return this._rooms;
  }

  /* Methods // Mixin: ToString */
  const string ToString() {
    return 'LobbyInfo('
      + string::Join({'name=' + name, 'n_clients=' + tostring(n_clients), 'n_rooms=' + tostring(n_rooms), 'n_public_rooms=' + tostring(n_public_rooms), 'rooms=' + TS_Array_RoomInfo(rooms)}, ', ')
      + ')';
  }

  const string PrettyString() {
    return name + " | Clients: " + n_clients + " | Public Rooms: " + n_public_rooms;
  }

  private const string TS_Array_RoomInfo(const array<RoomInfo@> &in arr) {
    string ret = '{';
    for (uint i = 0; i < arr.Length; i++) {
      if (i > 0) ret += ', ';
      ret += arr[i].ToString();
    }
    return ret + '}';
  }

  // custom additions

  // update from json to avoid allocating and freeing memory
  void UpdateFrom(const Json::Value@ j) {
    this._name = string(j["name"]);
    this._n_clients = uint(j["n_clients"]);
    this._n_rooms = uint(j["n_rooms"]);
    this._n_public_rooms = uint(j["n_public_rooms"]);
    this._rooms.Resize(j["rooms"].Length);
    for (uint i = 0; i < j["rooms"].Length; i++) {
      @this._rooms[i] = RoomInfo(j["rooms"][i]);
    }
  }

  void AddRoom(const Json::Value@ j) {
    this._rooms.InsertLast(RoomInfo(j));
  }

  void RetireRoom(const Json::Value@ j) {
    string name = j['name'];
    for (uint i = 0; i < _rooms.Length; i++) {
      if (_rooms[i].name == name) {
        _rooms.RemoveAt(i);
        break;
      }
    }
  }
}
