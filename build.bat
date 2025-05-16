@echo off
pushd bmff
call build.bat
popd

pushd ebml
call build.bat
popd

pushd tests
call build.bat
popd