"""Registry of Atari Gamma Force's generated music slots and the mood
each one should evoke (copied from MegaGammaForce's gtools/musicgen, whose
own tracks are its game's; the in-game songs here are MegaGammaForce's,
converted by tools/vgm2pokey.py). These are the story's: the cutscenes'
tunes, short (each cutscene bank holds its own copy).

`resource` is the output filename stem: assets/music/fur/<resource>.fur,
assets/music/<resource>.vgm.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class MoodPreset:
    """Musical parameters for a track's mood. Semitone 0 = C.

    `intensity` (0.0-1.0) places the track on the game's arc and drives
    compose.py's choice of chord progressions (title/early levels stay
    simple and diatonic; boss fights and late levels pull from a pool of
    more harmonically restless progressions) and whether the contrasting
    B-theme/bridge modulates to a different key.
    """

    key_root: int
    scale: str
    bpm: float
    intensity: float
    target_seconds: float = 170.0
    lead_octave: int = 5
    arp_octave: int = 4
    bass_octave: int = 2
    use_drums: bool = True
    meter: str = "4/4"  # "4/4", "6/8" or "3/4"; styles 9 and up read it
    # "song" (intro, themes, bridge, outro; loops) or "jingle": two phrases,
    # the second a cadence home, played once (styles 9 and up)
    form: str = "song"


@dataclass
class TrackSpec:
    resource: str  # e.g. "Level_01" -- ROM asset name and output filename stem
    description: str
    aliases: list
    mood: MoodPreset


TRACKS: list = [
    TrackSpec(
        resource="Prologue",
        description="Cutscene: Scramble Order, Code Gamma (the launch, before stage 1)",
        aliases=["prologue"],
        # Urgent and heroic: the catapult counting down.
        mood=MoodPreset(key_root=2, scale="minor", bpm=140, intensity=0.6, target_seconds=40.0, lead_octave=5),
    ),
    TrackSpec(
        resource="Briefing",
        description="Briefings: Dr. Thorne's sector alerts (before stages 2, 3, 4, 5, 7)",
        aliases=["briefing"],
        # Tense and steady, under the radio chatter.
        mood=MoodPreset(key_root=9, scale="minor", bpm=110, intensity=0.4, target_seconds=30.0, lead_octave=5),
    ),
    TrackSpec(
        resource="ActBreak",
        description="Cutscenes: the act breaks (before stages 6, 8, 9)",
        aliases=["actbreak", "act"],
        # Grand: leaving the Earth, the Moon, then the dive into the Sun.
        mood=MoodPreset(key_root=7, scale="minor", bpm=120, intensity=0.7, target_seconds=45.0, lead_octave=5),
    ),
    TrackSpec(
        resource="Epilogue",
        description="Cutscene: The Sun Burns Clean (after GAMMA PRIME)",
        aliases=["epilogue", "ending"],
        # Warm and major: going home.
        mood=MoodPreset(key_root=2, scale="major", bpm=96, intensity=0.35, target_seconds=60.0, lead_octave=5),
    ),
]

_ALIAS_INDEX = {}
for _t in TRACKS:
    _ALIAS_INDEX[_t.resource] = _t
    for _a in _t.aliases:
        _ALIAS_INDEX[_a] = _t


def resolve(name: str) -> TrackSpec:
    key = name.strip().lower()
    for candidate_key, spec in _ALIAS_INDEX.items():
        if candidate_key.lower() == key:
            return spec
    raise KeyError(f"unknown track '{name}'. Known: {sorted(set(_ALIAS_INDEX.keys()))}")
