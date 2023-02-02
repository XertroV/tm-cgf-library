# Tic Tac GO!

Tic Tac GO! (TTG) is a multiplayer game for 2 teams (up to 64 players total). Two team capitans make tic-tac-toe moves using modified rules (including stealing quares) -- their team must win the map (finish first) to claim the map. Games are played on a 3x3 grid of random maps, or maps from a map pack.

Server play is supported (since everyone plays the same map at the same time).

Modes:
- Standard: a 1v1 game of TTG
- Teams: up to 64 players on 2 teams, scored like matchmaking.
- Battle Mode: up to 64 players on 2 teams, first time to X finshes wins.
- Single player: demo/testing mode, basically (still works on a server).



License: Public Domain

Authors: XertroV

Suggestions/feedback: @XertroV on Openplanet discord

Code/issues: [https://github.com/XertroV/tm-cgf-library](https://github.com/XertroV/tm-cgf-library)

GL HF


<!--
The CGF is a multiplayer library for community games. It handles: TCP connections, lobbies, rooms, chat, map selection, teams, authentication, etc.

Tic Tac GO! is the bundled demo game and is functional.

Watch the trailer: [https://youtu.be/POLv0doWaIc](https://youtu.be/POLv0doWaIc)

Thanks to AgentWhiskey for permission to use clips from his intro to [Sapphire](https://trackmania.exchange/tracks/view/78349/sapphire).

Example games via AR_Down (before and after timestamp): [https://www.twitch.tv/videos/1679338531?t=1h48m23s](https://www.twitch.tv/videos/1679338531?t=1h48m23s)

### About the CGF

Consider a community game like [Bingo](https://openplanet.dev/plugin/trackmaniabingo). To make a game like that, a plugin dev not only has to write the game itself, but also the server software, a TCP transport layer, user authentication, message parsing, lobby infrastructure, getting random maps from TMX, etc.

The purpose of the CGF is to handle all those *other* things, letting commuity game developers to focus on the actual game, and not all the extra bits.

**The CGF will be under heavy active development over the next month (dec / early jan 2023) if there is interest. Collaboration and feedback are welcome! Please message @XertroV. Links to source code below.**

The CGF isn't available to other plugins yet -- there's work left to do with the architecture and API for other plugins (among other things). However, this release is indicative of the final design, and will give plugin developers an idea of how it will eventually work.

The goal of the CGF is that other plugins can simply create a `CGF::Client()`, give it a game engine, and all of the other under-the-hood stuff is just there in the background, for free. (Including auto-reconnect and auto-rejoin game.)

Since the main goal of the CGF is to provide a *generic* interface that *any* community game can use, game logic is naturally abstracted away from the core architecture. The idea is that games are (data-wise) a sequence of game events, and the game state is the result of applying each of those game events in turn. This is a flexible and reliable foundation -- all clients will recieve the game events in the same sequence, so state can be deterministically calculated. It also means that games are 'replayable' (in the technical sense) -- when someone rejoins a game the server will simply replay all the game events to catch the client back up to date.

The server itself has a somewhat arbitrary limit of 16 teams and 64 players, though limits are set a bit lower at the moment to be conservative. To give you an idea of how flexible the CGF will be: one idea I have for a community game is a territory/exploration game (a bit like Risk) played with 4 teams of 16 players each on a 7x7 ish grid. Another is speed chess combined with random maps (idk might be fun).

The server architecture is also quite simple, and designed to support *multiple* different server options hosted by different ppl (although, no cross-server gameplay). This means that other ppl can run their own CGF servers. I hope that we'll get to the point where there is a nice drop down with multiple options, and if one server isn't working for you and your friends, then you can easily swap to another.

Users are authenticated via OpenPlanet's new Auth API.

For plugin devs, if you are interested in seeing what a game looks like, check out [the code on github](https://github.com/XertroV/tm-cgf-library/tree/master/src/TTG) -- The three main files to check are `TTG_Game.as` (lobby/room UI and client management), `TicTacGo.as`, which is the game UI and some auxiliary state, and `TTGState.as` which is the game state logic proper.

Server code: [https://github.com/XertroV/cgf-server/](https://github.com/XertroV/cgf-server/)


















o:

- team chat `/t`

- room reuse? or mb auto-join new room?

-

- (mb, not sure) alt turn order: 1,1,2,2,1,1,2,2,...


(auto cancel skin downloads)



- notification sound or visual indicator when it's your turn
- team score totals so you can tell who's winning easily

- admin, force game start
- auto assign to teams
- visibility of main window in-map

- cannot claim last claimed
- 1st round is for center square, winner claims
- battle mode scoring
- chat msgs less than 1 char?
- teams mode in general
- teams scoring check
- auto dnf notice
- game resolved notice (timeout 3s)



- DNRC command (do not reconnect)
- games
  - game engine
  - elo / ranked?


bans

server version test!

game options:

- stealing maps
- enable/disable records
- auto DNF
- give-up = DNF? (respawns okay)
- battle mode (1 leader per team, up to 64 players over 2 teams; todo: figure out scoring / win condition)
-




done: hide lobby names?, auth



done: color test in chat

room chat

initial window dimensions


todo:

add NEW_ROOM msg / handler

on room join - check if game has started and make sure player is one of the players

options:
room timeout
auto dnf

96MS2Q

-->
