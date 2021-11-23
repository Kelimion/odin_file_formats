@echo off
odin build . -out:example.exe -vet -define:EBML_DEBUG=true
: -opt:1 -debug
if %errorlevel% neq 0 goto end_of_build
example


:end_of_build