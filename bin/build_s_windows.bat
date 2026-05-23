@echo off
set PATH=C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%
set SRC=C:\Users\shuwen\s\src\cmd\compile\seed
set OUT=C:\Users\shuwen\s\bin\s.exe
C:\msys64\mingw64\bin\gcc.exe -std=c11 -o "%OUT%" ^
  "%SRC%\s_seed.c" ^
  "%SRC%\bootstrap\bootstrap.c" ^
  "%SRC%\code\generator.c" ^
  "%SRC%\code\native_backend.c" ^
  "%SRC%\debug\debug.c" ^
  "%SRC%\error\error.c" ^
  "%SRC%\intermediate\ir.c" ^
  "%SRC%\lexical\lexer.c" ^
  "%SRC%\runtime\runtime.c" ^
  "%SRC%\semantic\analyzer.c" ^
  "%SRC%\syntax\parser.c" ^
  "%SRC%\testing\tests.c"
echo Exit: %ERRORLEVEL%
