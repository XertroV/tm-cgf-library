[Setting category="General" name="Server Hostname"]
string S_Host = "cgf.xk.io";
// string S_Host = "localhost";

[Setting category="General" name="Server Port"]
uint16 S_Port = 15277;

#if SIG_DEVELOPER
[Setting category="General" name="Local Dev?"]
#endif
bool S_LocalDev = false;

#if SIG_DEVELOPER
[Setting category="General" name="Legacy Auth?" description="Only works with a dev server."]
#endif
bool S_LegacyAuth = false;



// [Setting category="Tic Tac Go" name="Timer Pos (in map)"]
// vec2 S_TimerPosition = vec2(0, 200);

[Setting category="Tic Tac Go" name="Hide Chat Always?"]
bool S_TTG_HideChat = false;

[Setting category="Tic Tac Go" name="Hide Lobby/Room Chat?"]
bool S_TTG_HideLobbyChat = false;

[Setting category="Tic Tac Go" name="Hide Room Names?"]
bool S_TTG_HideRoomNames = false;
