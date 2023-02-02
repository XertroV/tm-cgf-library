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

[Setting category="Tic Tac Go" name="Autostart Maps? (Local Mode)"]
bool S_TTG_AutostartMap = false;

[Setting category="Tic Tac Go" name="Font Selection"]
FontChoice S_TTG_FontChoice = FontChoice::Normal;

[Setting category="Tic Tac Go" name="Game Window Background Opacity" min=0.9 max=1.0]
float S_TTG_BG_Opacity = 0.97;



#if DEV
[Setting category="Tic Tac Go" name="Show Game Debug Info?"]
#endif
bool S_TTG_DrawGameDebugInfo = false;

[SettingsTab name="Changelog" order="99"]
void Render_Settings_Changelog() {
    UI::Markdown(" # " + Meta::ExecutingPlugin().Version + """

 - Fix compile error on non-edge versions of openplanet.
 - Auto-expand compact UI on game end.

 # 0.2.1

 - Completely refactor the challenge loop (loading map, measuring time, voting on servers, etc).
 - Add team colors to TTG board.
 - Use textures for o/x symbols.
 - Change winning squares indicator to a line instead of coloring squares.
 - Any unrevealed maps are now revealed when the game ends.
 - Records made visible when you finish a map. Chrono made visible when round over.
 - Move TTG to the 'Game' category in the Plugins menu.
 - Clear temporarily cached maps on plugin load (so it clears maps cached during the last session). Maps are pre-cached to improve load times (esp. on servers).
 - (Dev) Remove CGF debug client menu entry.
 - Remove menu page management (bug now fixed by Nadeo).
 - Add large/small game UI modes.
 - Will no longer exit and rejoin a server if already in the right one.

 ### Settings

 - Add font choices: Normal, Droid Sans, and Droid Sans Smaller.
 - Add option for changing the game window background opacity.
    """);

    if (UI::BeginCombo("Font Choice", tostring(S_TTG_FontChoice))) {
        if (UI::Selectable(tostring(FontChoice(0)), 0 == int(S_TTG_FontChoice)))
            S_TTG_FontChoice = FontChoice(0);
        if (UI::Selectable(tostring(FontChoice(1)), 1 == int(S_TTG_FontChoice)))
            S_TTG_FontChoice = FontChoice(1);
        if (UI::Selectable(tostring(FontChoice(2)), 2 == int(S_TTG_FontChoice)))
            S_TTG_FontChoice = FontChoice(2);
        UI::EndCombo();
    }
    S_TTG_BG_Opacity = UI::SliderFloat("Game Window BG Opacity", S_TTG_BG_Opacity, 0.9, 1.0);
    UI::Text("");

    UI::Markdown("""
 ### Fixes

 - Fix server-mode voting (it works now).
 - Fix bug where time would erroneously be added for some players in local mode.
 - Fix crash starting a map in local mode (this affected v0.1.60, but only started appearing after the mid-Jan update).

 # 0.1.60

 - Remove useless fonts (saves ~3s load time)

 # 0.1.58

 - Refactor voting code to be more tolerant of latency -- less manual voting should be required.

 # 0.1.56

 - Disable blackout feature
 - Fix null pointer exception when leaving map
 - Create a new TTG game data structure on entering a room instead of resetting the old one
 - Fix yield in UI code that caused a plugin crash

 # 0.1.54

 ## Server Play

 This update brings the ability to host games on a server. All players can see each others' cars.

 - Add patch notes accessible via lobby button & in plugin settings
 - Add preparation status messages to inform users of room set up progress (CGF + TTG)
 - Implement server mode for (TTG + CGF)
 - Add DNF button (TTG)
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
 - Add TOTD and Royal Trailing map sources (TTG + CGF)
 - Pre-download maps for faster load times (TTG + CGF) -- saved in `Maps\CGF-TMX`

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
