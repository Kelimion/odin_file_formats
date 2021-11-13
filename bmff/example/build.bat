@echo off
odin build . -out:example.exe -vet -define:BMFF_DEBUG=true
: -opt:1 -debug
if %errorlevel% neq 0 goto end_of_build
example
example "../../tests/assets/bmff/test_metadata.mp4"
:end_of_build