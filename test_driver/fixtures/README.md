# AAC priming regression

`aac_priming.m4a` is a synthetic 3-second 660 Hz tone, generated with FFmpeg:

```
ffmpeg -f lavfi -i sine=frequency=660:sample_rate=44100:duration=3 -c:a aac -b:a 96k aac_priming.m4a
```

Its first encoded packet has PTS -0.023220 seconds with 1024 skip samples.
The analyzer must read it rather than confuse a negative timestamp with EOS.

Push it to the installed app's external files directory as
`/sdcard/Android/data/com.ringtone.ringtone_maker/files/aac_priming_regression.m4a`.
Build the release device harness using a quoted Gradle property
`"-Ptarget=<absolute path to test_driver/aac_priming_device.dart>"` and
`-Ptarget-platform=android-arm64`.
Install and launch, then inspect logcat for `AAC_REGRESSION PASS ALL`.
Repush the fixture before rerunning to invalidate its modification-based cache.
Restore the normal release APK using the absolute path to `lib/main.dart` after the run.

Checks: a nonzero waveform for negative-PTS AAC, complete analysis, cache round trip,
exports beginning at zero and later in the source, genuine silent PCM, and rejection
of an empty audio stream. Preview exports and generated WAV files are cleaned up.
