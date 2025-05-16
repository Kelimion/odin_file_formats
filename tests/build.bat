@echo off
set PATH_TO_ODIN=odin
set COMMON=-show-timings -vet -vet-tabs -strict-style -vet-style -warnings-as-errors -disallow-do
echo ---
echo Running ISO Base Media File Format tests
echo ---
%PATH_TO_ODIN% test bmff %COMMON%
echo ---
echo Running EBML (Matroska) Format tests
echo ---
%PATH_TO_ODIN% test ebml %COMMON%