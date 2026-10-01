; CoralOS Bootloader - Licensed under the MIT License (see LICENSE file)

bits 16                     ; BIOS запускает нас в старом 16-битном режиме
org 0x7C00                  ; и кладёт по этому адресу

KSEG    equ 0x0800          ; ядро ляжет сюда (это адрес 0x8000)
KSECT   equ 16              ; сколько секторов читаем

start:
    xor ax, ax              ; обнуляем сегменты: адреса считаются прямо
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; стек растёт вниз от нас же
    mov [drive], dl         ; BIOS сказал, с какого диска мы пришли

    mov si, msg
    call print

    mov ax, KSEG            ; куда класть прочитанное
    mov es, ax
    xor bx, bx
    mov ah, 0x02            ; 0x02 - "прочитай сектора"
    mov al, KSECT
    mov ch, 0               ; дорожка
    mov cl, 2               ; со второго: первый - мы сами
    mov dh, 0               ; головка
    mov dl, [drive]
    int 0x13
    jc error                ; перенос поднят - не прочлось

    jmp KSEG:0x0000         ; отдаём управление ядру

error:
    mov si, errmsg
    call print
.hang:
    hlt
    jmp .hang

print:                      ; si - строка, до нуля в конце
    mov ah, 0x0E            ; 0x0E - "напечатай букву"
.next:
    lodsb                   ; забрать байт из [si], si сдвинуть
    test al, al
    jz .done
    int 0x10
    jmp .next
.done:
    ret

drive  db 0
msg    db "Coral: loading", 13, 10, 0
errmsg db "Disk error", 13, 10, 0

times 510 - ($ - $$) db 0   ; добить до 510 байт
dw 0xAA55                   ; метка загрузочного сектора