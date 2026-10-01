# CoralOS v0.01

**CoralOS** is an independent 16-bit operating system for programmers, written from scratch in pure x86 Assembly. The system features its own custom kernel, text editor, calculator, and the **FSM** (Files System Manager) file system.

## Key Feature: Aqe Programming Language
The OS comes with a built-in `aqec` compiler and its own `.pbi` (Program Binary) executable format. The Aqe language introduces a unique low-level syntax that replaces cryptic assembly opcodes with intuitive mathematical symbols for branching and loops (such as `=-` for "not equal", `<`, and `>`).

### Aqe Code Example:
```text
b eax 0
proverka:
add eax
c eax 1
=- proverka
```

## How to Build and Run
1. Compile the project using the built-in `build.bat` script (requires the NASM compiler installed).
2. Run the resulting `coral.img` disk image in the QEMU emulator.

## License
This project is distributed under the official MIT License. See the LICENSE file for details.

