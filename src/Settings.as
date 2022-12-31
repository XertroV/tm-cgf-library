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

[Setting category="Tic Tac Go" name="Hide Player Events in Game Log?"]
bool S_TTG_HidePlayerEvents = false;

[Setting category="Tic Tac Go" name="Autostart Maps?"]
bool S_TTG_AutostartMap = false;

[SettingsTab name="Changelog" order="99"]
void Render_Settings_Changelog() {
    UI::Markdown(" # " + Meta::ExecutingPlugin().Version + """

 ## Server Play

 This update brings the ability to host games on a server. All players can see each others' cars.

 - Add change log in plugin settings & via button in lobby
 - Add preparation status messages to inform users of room set up progress (CGF + TTG)
 - Implement server mode for TTG
 - Add DNF button (TTG); only shows up in server mode
 - Auto DNF someone on disconnection from game room (TTG)
 - Add load error notifications, particularly for map packs atm (TTG + CGF)
 - Lobby feedback if permissions check will fail when the game starts (TTG)
 - Add auth error state and page in case openplanet auth times out (TTG + CGF)
 - Add visual indicator for when it's your turn. (TTG)
 - Bump limit to 64 players (TTG)
 - Add teams scores total to UIs (TTG)
 - Add a rematch button when the game is over (TTG + CGF)
 - Load maps from TMX url instead of CGF mirror (TTG)
 - Fix hang when going back to main menu while in-game menu is open (TTG)
 - Fix reconnect bug when exiting main window during authentication (CGF)
 - Implement editing game options while in-room before the game has started (TTG + CGF)
 - Fix bug where maps weren't cleared properly (TTG)
 - Fix bug where a map from the prior game could not be selected when 'cannot pick last round's square' option enabled (TTG)
 - Improve timer method to use exact times instead of estimating (TTG)

 # 0.1.24

 - Add support for map packs (TTG + support via CGF)
 - Add a dark gray bg color to inputs so they're easier to see (TTG)
 - Customize map loading screen (TTG)
 - Add a game-version check for game clients (TTG)
 - Team leader demotion if the player disconnects (TTG + support via CGF)
 - Introduce 'Game Master' events to add things like player disconnection to game log (CGF)
 - Re-balance scoring in teams mode to favor the smaller team when teams are unequal (TTG)
 - Change default game mode options to favor faster, more strategic games (TTG)
 - Tweak create room UI to make mode options more obvious (TTG)
 - Don't quit the map when the player scores, let them keep playing while other players are yet to finish (TTG)
 - Show all players on score boards even if they haven't finished (TTG; teams and battle mode)
    """);
}
