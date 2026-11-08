#!/bin/bash
# Makes a 60 s synthetic melody (our own, not a copyrighted song) for trying the import flow.
#   make-dummy-song.sh [output dir]      default: $TMPDIR/finpro-ui-verify
# Prints the file path. Pass it to ui-verify.sh as importFile (the simulator reads host paths).
set -euo pipefail
OUT="${1:-${TMPDIR:-/tmp}/finpro-ui-verify}"
mkdir -p "$OUT"
python3 -I - "$OUT/dummy.wav" <<'PY'
import sys, wave, struct, math
sr, dur = 44100, 60
mel = [261.63, 293.66, 329.63, 392.0, 440.0, 392.0, 329.63, 293.66]
chords = [(130.81, 164.81, 196.0), (110.0, 130.81, 164.81), (87.31, 110.0, 130.81), (98.0, 123.47, 146.83)]
note = 60 / 100 / 2
frames = bytearray()
for i in range(sr * dur):
    t = i / sr
    n = int(t / note); nt = t - n * note
    f = mel[n % len(mel)]
    env = min(1, nt * 40) * math.exp(-nt * 3)
    v = 0.35 * env * (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t))
    v += 0.12 * sum(math.sin(2 * math.pi * c * t) for c in chords[int(t / (note * 8)) % 4])
    fade = min(1, t / 0.5, (dur - t) / 1.0)
    frames += struct.pack('<h', int(max(-1, min(1, v * fade)) * 32000))
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(bytes(frames)); w.close()
PY
afconvert -f m4af -d aac -b 128000 "$OUT/dummy.wav" "$OUT/Dummy Song.m4a"
rm "$OUT/dummy.wav"
echo "$OUT/Dummy Song.m4a"
