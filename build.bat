@echo off
setlocal
rem Coral OS: Build and launch script

rem --- Find NASM compiler ---
set "N="
where nasm >nul 2>&1 && set "N=nasm"
if not defined N if exist "%LOCALAPPDATA%\bin\NASM\nasm.exe" set "N=%LOCALAPPDATA%\bin\NASM\nasm.exe"
if not defined N if exist "%LOCALAPPDATA%\NASM\nasm.exe" set "N=%LOCALAPPDATA%\NASM\nasm.exe"
if not defined N if exist "%ProgramFiles%\NASM\nasm.exe" set "N=%ProgramFiles%\NASM\nasm.exe"
if not defined N if exist "%ProgramFiles(x86)%\NASM\nasm.exe" set "N=%ProgramFiles(x86)%\NASM\nasm.exe"
if not defined N if exist "C:\nasm\nasm.exe" set "N=C:\nasm\nasm.exe"
if not defined N goto nonasm

rem --- Find QEMU emulator ---
set "Q="
where qemu-system-i386 >nul 2>&1 && set "Q=qemu-system-i386"
if not defined Q if exist "%ProgramFiles%\qemu\qemu-system-i386.exe" set "Q=%ProgramFiles%\qemu\qemu-system-i386.exe"
if not defined Q if exist "%ProgramFiles(x86)%\qemu\qemu-system-i386.exe" set "Q=%ProgramFiles(x86)%\qemu\qemu-system-i386.exe"
if not defined Q if exist "C:\qemu\qemu-system-i386.exe" set "Q=C:\qemu\qemu-system-i386.exe"
if not defined Q goto noqemu

echo [1/3] Compiling bootloader...
"%N%" -f bin boot.asm -o boot.bin
if errorlevel 1 goto err

echo [2/3] Compiling kernel...
"%N%" -f bin kernel.asm -o kernel.bin
if errorlevel 1 goto err

echo [3/3] Creating disk image...
copy /b boot.bin + kernel.bin coral.img >nul
if errorlevel 1 goto err

echo Starting emulator...
"%Q%" -drive file=coral.img,format=raw
echo.
echo Done.
pause
exit /b

:nonasm
echo.
echo Error: NASM was not found. Please check your path installation.
echo.
pause
exit /b

:noqemu
echo.
echo Error: QEMU was not found. Please check your path installation.
echo.
pause
exit /b

:err
echo.
echo Error: Build failed. Check the compiler messages above.
echo.
pause
