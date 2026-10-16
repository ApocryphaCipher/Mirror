# Mirror

**Look inside your *Master of Magic* saves, and change them.**

Mirror opens a save file from the classic 1994 DOS game and shows you the whole world in your browser: both planes, every city, army, tower and lair, drawn with the game's own art. Then it lets you change things: reshape the land, move a city, give a wizard more gold, hand a hero a new sword. Save the result as a new file and load it in the game.

![Mirror's map page showing Arcanus from a save, with the wizard links, layer toggles and the Surveyor readout](docs/images/mirror-map.jpg)

![Mirror's wizard page for Freya: fame, gold, mana, books, retorts, research and known spells, on her green banner colour](docs/images/mirror-wizard.jpg)

## What you can do

- **Explore the map.** Zoom and pan Arcanus and Myrror, hover any tile to see what it is, and switch layers on and off (units, cities, fog of war and more).
- **Edit the map.** Paint terrain, lay roads, move cities and armies, and open any city, lair or node to change what's in it. Undo and redo everything.
- **Edit the wizards.** Gold, mana, spell books, retorts, spells, relations, global enchantments, heroes and their artifacts.
- **Open and save without copying files.** Pick your game folder once and click the slot you want to open. When you're done, click a slot under **Save to** at the top of the page. Replacing a full slot asks first and keeps the old save as a backup.

Every kind of edit has been checked by loading the result in the real game.

## Get it running

You need **your own copy of the game**. Mirror can't include it. The GOG version works, and the Steam version works for viewing and editing (see [Good to know](#good-to-know)). You also need [Elixir](https://elixir-lang.org/install.html) 1.20 with Erlang/OTP 29, or Docker.

```bash
git clone https://github.com/ApocryphaCipher/Mirror.git
cd Mirror
mix setup
mix mirror.import_game "/path/to/your/Master of Magic"   # a folder or a .zip
bash scripts/dev_server.sh
```

Open <http://localhost:4000> in **Chrome or Edge**, click **Choose folder** and pick the folder your game saves into. The slots with a save in them turn green; click one to open it. To open a different save later, click the logo to come back to this page. Press Ctrl-C to stop the server.

Other browsers can't pick a folder. There you can open a save by its path in the Lab (the **Lab** link at the top): type the path of a save (for example `~/.mirror/game/SAVE1.GAM`) and press **Load**.

The import step copies just the files Mirror needs, and your saves, into `~/.mirror/game`. It's safe to run again; it won't overwrite a save you've edited. (The game folder you pick in the browser is where your saves live, which can be your real game folder; `~/.mirror/game` is where Mirror keeps its copy of the game's data files.)

**On Windows** (tried on Windows 11, PowerShell), the same steps with these differences. The full write-up is in [docs/reference/windows-setup.md](docs/reference/windows-setup.md).

- Install [Git](https://git-scm.com/download/win) (the heroicons dependency is fetched from GitHub), Elixir 1.20 and Erlang/OTP 29. A version manager such as [mise](https://mise.jdx.dev/) does both per user: `mise install erlang@29.1 elixir@1.20.4-otp-29`. Node.js is optional (it adds the client's JavaScript tests).
- Tell Git to leave line endings alone before cloning: `git config --global core.autocrlf input`. With the default `true`, files are checked out with CRLF and `mix format --check-formatted` fails.
- `mix setup` works as it is (it downloads the Windows Tailwind and esbuild itself). Give `mix mirror.import_game` the folder in quotes, for example `mix mirror.import_game "E:\SteamLibrary\steamapps\common\Master of Magic Classic\Master of Magic Official Release"`. The game files go to `C:\Users\<you>\.mirror\game`.
- `scripts/dev_server.sh` is a bash script and was not tried. In PowerShell run:

  ```powershell
  $env:MIRROR_MOM_PATH = "$env:USERPROFILE\.mirror\game"
  mix phx.server
  ```

- Choose the game folder on the start page. With Steam that is the install folder, which has `SAVE1.GAM` to `SAVE9.GAM` in it. (In the Lab's path box, a full path with backslashes works too.)

**Prefer Docker?**

```bash
docker compose up --build
```

That builds Mirror on your machine and serves it on port 4000, reading your game files from `~/.mirror/game`. To import them without Elixir installed:

```bash
docker compose run --rm -v "/path/to/install:/source:ro" app bin/mirror eval 'Mirror.GameFiles.import("/source", "/game")'
```

## Playing your edited save

Click a slot under **Save to** at the top of the page (slots 1 to 8). The game only loads `SAVE1.GAM` to `SAVE9.GAM`, and its Load screen shows slots 1 to 8 (slot 9 is the autosave, which Mirror can open but never writes to). Then load the slot in the game as usual.

When you replace a slot that already has a save, Mirror first copies the old one to `SAVEn.GAM.mirror-backup` in the same folder. The game ignores that file. The copy is made once, so it stays the save as the game wrote it; delete it if you want a fresh one next time.

## Good to know

- The GOG 1.31 version of the game is the one every edit was checked against. On the Steam version (Master of Magic Classic) the map draws, and a save edited in Mirror loads in the game with the edits in place. Three of the files Mirror reads (`MAPBACK.LBX`, `ITEMPOW.LBX`, `ITEMDATA.LBX`) differ from GOG's; they were tested on Windows with Steam and work as expected, so the import's warning about them can be ignored.
- Paint type keeps coasts and continents right. The raw tile tools (Cycle, Paint tile) don't, so use them with care.
- Time Stop can't be edited.

The full list is in the [release notes](docs/releases/v0.1.0.md).

## Under the hood

Mirror is a Phoenix LiveView app. The game's file formats are undocumented, so every format fact in the code was checked against the game itself, and the write-ups are in [docs/reference](docs/reference/). Project status, stories and session notes are in [docs/](docs/README.md).

## Contributing

Changes go through a pull request: branch, commit, open a PR, and CI must pass. The standards, for people and AI agents alike, are in [AGENTS.md](AGENTS.md). To run the tests:

```bash
mix test
```

## Licence

GPL-2.0, see [LICENSE](LICENSE). Parts of Mirror are ported from the GPLv2 MOMIME project, and the terrain table comes from [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic). Details are in [NOTICE.md](NOTICE.md). The game's own files aren't included and aren't covered.

Mirror is maintained by [Kevin Asbury](https://github.com/KevinAsbury).
