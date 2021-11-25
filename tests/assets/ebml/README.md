# Matroska Test Files

These test files are a subsset of the [official Matroska test files](https://github.com/ietf-wg-cellar/matroska-test-files).

# Multiple audio/subtitles

This has a main audio track in english and a secondary audio track in
english. It also has subtitles in English, French, German, Hungarian,
Spanish, Italian and Japanese. The player should provide the possibility
to switch between these streams.

The sample contains H264 (1024x576 pixels), and stereo AAC and
commentary in AAC+ (using SBR). The source material is taken from the
[Elephant Dreams](http://orange.blender.org/download) video project

# Junk elements & damaged

This file contains junk elements (elements not defined in the specs)
either at the beggining or the end of Clusters. These elements should be
skipped. There is also an invalid element at 451417 that should be
skipped until the next valid Cluster is found.

The sample contains H264 (1024x576 pixels), and stereo AAC. The source
material is taken from the [Elephant
Dreams](http://orange.blender.org/download) video project