#!/bin/zsh
# Runs the song-preparation pipeline on the Mac: htdemucs (CoreML) and center-channel separation
# with the fallback, CREPE guide
# extraction, transposition rendering, trim-screen lyrics (LRC parsing, LRCLIB matching), and
# PrepareSongUseCase end to end.
# Run before opening a PR that touches finpro/Data/Separation or finpro/Data/Audio.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"

xcrun coremlcompiler compile "$ROOT/finpro/Resources/CrepeTiny.mlmodel" "$WORK" > /dev/null
xcrun coremlcompiler compile "$ROOT/finpro/Resources/HTDemucs.mlpackage" "$WORK" > /dev/null

xcrun swiftc -O -D DEBUG \
  $(find "$ROOT/finpro/Domain" -name '*.swift') \
  "$ROOT/finpro/Shared/DSP/CrepePitchDetector.swift" \
  "$ROOT/finpro/Shared/DSP/CrepeEstimate.swift" \
  "$ROOT/finpro/Shared/DSP/PitchMath.swift" \
  "$ROOT/finpro/Data/Audio/CrepeAnalysisRepository.swift" \
  "$ROOT/finpro/Data/Audio/AudioTranspositionRepositoryImpl.swift" \
  "$ROOT/finpro/Data/Separation/CenterChannelStemRepository.swift" \
  "$ROOT/finpro/Data/Separation/CoreMLSeparationError.swift" \
  "$ROOT/finpro/Data/Separation/HTDemucsStemSeparationRepository.swift" \
  "$ROOT/finpro/Data/Separation/SelectingStemSeparationRepository.swift" \
  "$ROOT/finpro/Shared/DSP/ShortTimeFourierTransform.swift" \
  "$ROOT/finpro/Shared/DSP/DemucsSpectrogram.swift" \
  "$ROOT/finpro/Presentation/Import/LyricsProviding.swift" \
  $(find "$ROOT/finpro/Data/Lyrics" -name '*.swift') \
  $(find "$ROOT/scripts/prep-checks" -name '*.swift') \
  -o "$WORK/prep-check"

"$WORK/prep-check" "$WORK/CrepeTiny.mlmodelc" "$WORK/HTDemucs.mlmodelc"
