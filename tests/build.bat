@echo off
echo ---
echo Running ISO Base Media File Format tests
echo ---
pushd bmff
call build.bat
popd
echo ---
echo Running EBML (Matroska) Format tests
echo ---
pushd ebml
call build.bat
popd