# Game audio

All playback uses ordinary `AudioStreamPlayer` nodes through the `GameAudio`
autoload in `src/autoloads/game_audio.gd`. There is no positional attenuation or
panning. Playback type remains the platform default so Web exports use Godot's
sample playback path. No audio-bus effects or threaded Web export are required.

## Sound mapping

| Source | Event |
| --- | --- |
| `sword_swing_light_1.wav` | First animation-authored hitbox opening of an accepted light attack |
| `sword_swing_heavy_1.wav` | First animation-authored hitbox opening of an accepted heavy attack |
| `hit_light_2.wav` | Resolved light hit that removes health |
| `hit_2.wav` | Resolved heavy hit that removes health |
| `hit_blocked_1.mp3` | Resolved block, shared by all shields |
| `defensive_stance_break.wav` | Player stamina or enemy guard exhausted by a block |
| `dodge.wav` | Accepted dodge, shared by all directions and fighters |
| `body_fall.wav` | Character defeat (starts with the death animation) |
| `footstep_walk.wav` | Grounded movement, with a faster cadence and +2 dB while running |
| `ui_hover.wav` | Enabled button mouse hover immediately, or keyboard focus after input |
| `ui_confirm.wav` | Button activation |
| `equipment_equip.wav` | Confirmed equipment reward |
| `duel_start.wav` | Start/retry of a duel |
| `duel_win.wav` | Soldier/Guardian defeat, immediately on the finishing hit; does not replay at the reward screen |
| `run_victory.mp3` | Champion result screen |
| `run_defeat.wav` | Player defeat screen |
| `arena_ambience_loop.wav` | Arena ambience during a duel and its ending animation |
| `flags_loop.wav` | Quiet second ambience layer during a duel and its ending animation |
| `menu_music.mp3` | Looping main-menu music |
| `combat_music.mp3` | Looping music during duels, ending animations, and upgrade selection; continues into the next duel |

No separate jump, landing, armor-only hit, stamina-denied, or vocal clips were
provided, so those events have no dedicated cue. Blocks that also deal health
damage play both the block and damage layers; a defense break adds its cue.
Rejected attacks/hits/dodges do not play success sounds.

## Tuning

- Edit `SOUNDS` in `game_audio.gd` to change each cue's source, volume in dB,
  pitch variation, and playback start offset. Edit `AMBIENCE_LEVELS` for loops.
- `MUSIC_LEVELS` controls the dedicated music player: menu at -20 dB, combat at
  -24 dB. Both MP3 imports loop from the beginning. Starting/retrying a duel
  switches to combat music; returning to the main menu restores menu music.
  Upgrade selection and the next duel preserve the same music playback without
  restarting it. Final victory and defeat screens stop music for their stingers.
  Requesting the same currently playing track does not restart it. Browser
  autoplay rules may delay initial menu music until the first click or keypress.
- Source recordings remain unchanged. WAV import sidecars enable peak
  normalization and explicitly disable looping for effects. Only the two
  ambience imports enable forward looping. Commit the `.import` sidecars.
- The footstep starts at 0.28 s to skip its recorded lead-in; equip starts at
  0.18 s. Keep these offsets in sync if replacing recordings. Their tails are
  preserved.
- Footsteps use actual horizontal distance after collision movement: no steps
  while idle, airborne, dodging, staggered, defeated, or pressing into a wall.
  They use distance-based cadence rather than new animation method tracks.
- There are 12 shared effect voices, 4 UI/reward voices, one stinger voice, one
  music voice, and two ambience voices. Music uses its original pitch.
- Scene changes stop old world sounds and stingers. UI confirmations survive
  menu deletion. Result screens stop ambience; retries restart it. Automatic
  initial menu focus is silent. Mouse hover has no first-click gate; browsers
  may still require user activation before allowing audible playback.

## Verification

From the project directory:

```sh
godot --headless --path . --script res://tools/validate_character_scene_contract.gd -- --audio-only
```

This exercises cue imports, loop bounds, non-spatial players, duplicate event
protection, actual movement, attack windows, damage/block/break routing, dodge,
death, voice caps, UI transitions, rewards, all three duel results, and retry.
It does not assess subjective mixing or the seam quality of generated loops.

Implementation validation (2026-09-15): the audio suite passed 101 checks. A
debug Web export built and ran in the browser; the Web Audio context was running,
sample playback was observed, and footsteps used their 0.28-second offset.
The existing full suite produced 1,467 checks with 18 failures, identical to a
copy of the working tree with the audio changes removed. Those failures concern
existing weapon progression values and the end-of-duel timer expectation.
Renderer null-material diagnostics also remain outside this audio change.

Music integration: the expanded audio suite passed 115 checks, including MP3
loop settings, menu/combat switching, result screens, retry, and cleanup. Live
Godot MCP checks confirmed both tracks playing with looping enabled and menu
music restored after leaving combat.

Also audition one complete run in the browser: compare hit/block/break clarity,
listen across the 15-second flag and 25-second ambience loop boundaries, and
check the mix at the user's normal playback volume.
