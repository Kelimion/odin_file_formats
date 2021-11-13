@echo off
set PATH_TO_ODIN=odin
set COMMON=-show-timings -no-bounds-check -vet -strict-style
echo ---
echo Running ISO Base Media File Format tests
echo ---
%PATH_TO_ODIN% run bmff %COMMON%