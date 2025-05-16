@echo off
if "%1" == "bmff" (
	pushd bmff
	call build.bat
	popd
	goto end
)

if "%1" == "ebml" (
	pushd ebml
	call build.bat
	popd
	goto end
)

if "%1" == "test" (
	pushd tests
	call build.bat
	popd
	goto end
)

echo Run:
echo     `build.bat test` for bmff + ebml tests.
echo     `build.bat bmff` for bmff (mp4/m4a) example.
echo     `build.bat ebml` for ebml (mkv)     example.
:end