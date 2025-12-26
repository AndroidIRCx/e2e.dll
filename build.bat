@echo off
"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\amd64\MSBuild.exe" e2e.vcxproj /p:Configuration=Release /p:Platform=Win32 /v:minimal
pause