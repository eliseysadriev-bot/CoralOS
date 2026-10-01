; CoralOS Kernel - Licensed under the MIT License (see LICENSE file)

org 0x0000
bits 16

; Диск: каталог и файлы лежат сразу за ядром (секторы 2-17 занимает ядро)
FSM_DIR          equ 18         ; сектор каталога
FSM_FIRST        equ 19         ; первый сектор под файлы
FSM_LAST         equ 41         ; последний сектор диска

; Память aqec (внутри сегмента ядра)
AQ_SRC           equ 0x3000     ; текст программы
AQ_BIN           equ 0x3200     ; образ .pbi: заголовок и код, всего 512 байт
AQ_CODE          equ AQ_BIN + 4 ; сам машинный код
AQ_END           equ AQ_BIN + 512
AQ_LAB           equ 0x3600     ; метки: 16 по 16 байт (имя и адрес)
AQ_FIX           equ 0x3700     ; переходы на метки: 32 по 16 байт
AQ_NLAB          equ 16
AQ_NFIX          equ 32
AQ_INT           equ 0x60       ; прерывание для print и других вызовов
PBI_MAGIC        equ 0x01494250 ; байты P B I 1 в начале .pbi

    jmp start

; Тексты
m_ver            db "CoralOS v0.01", 13, 10, 0
m_welcome        db "Welcome to CoralOS", 13, 10, 0
m_about          db "CoralOS - 16-bit OS written in Assembly", 13, 10, 0
prompt           db "> ", 0
m_help           db "Commands:", 13, 10
                 db "  clear   - clear the screen", 13, 10
                 db "  help    - this list", 13, 10
                 db "  ver     - system version", 13, 10
                 db "  echo    - print the text after it", 13, 10
                 db "  about   - about CoralOS", 13, 10
                 db "  reboot  - restart the computer", 13, 10
                 db "  exit    - turn the computer off", 13, 10
                 db "  credits - who made it", 13, 10
                 db "  time    - current time", 13, 10
                 db "  date    - current date", 13, 10
                 db "  calc    - calculator: calc 40 / 2", 13, 10
                 db "  edit    - text editor (Ctrl+S, Esc)", 13, 10
                 db "  create  - save the editor text: create name", 13, 10
                 db "  read    - show a file: read name", 13, 10
                 db "  dir     - list the files on disk", 13, 10
                 db "  aqec    - compile: aqec name -> name.pbi", 13, 10
                 db "  run     - run a program: run name.pbi", 13, 10, 0
m_credits        db "I am the developer of CoralOS", 13, 10
                 db "and I respect everyone who", 13, 10
                 db "has downloaded the code -", 13, 10
                 db "after all, this is the", 13, 10
                 db "first truly working OS.", 13, 10, 0
m_exit_msg       db "Shutting down...", 13, 10, 0
m_fs_ok          db "File processed successfully", 13, 10, 0
m_edit_help      db "Editor Mode: [Ctrl+S] Save | [Esc] Exit", 13, 10, 0
m_built          db "Built ", 0
m_stop           db 13, 10, "Stopped", 13, 10, 0

; Ошибки: раздел x номер. 1 - команды, 2 - файлы, 3 - калькулятор, 4 - aqec
m_err_1x1        db "Error 1x1", 13, 10, 0   ; неизвестная команда или нет файла
m_err_2x1        db "Error 2x1", 13, 10, 0   ; каталог или диск полон
m_err_2x2        db "Error 2x2", 13, 10, 0   ; пустое имя файла
m_err_2x3        db "Error 2x3", 13, 10, 0   ; ошибка диска
m_err_3x1        db "Error 3x1", 13, 10, 0   ; неизвестный знак
m_err_3x2        db "Error 3x2", 13, 10, 0   ; пустой пример
m_err_3x3        db "Error 3x3", 13, 10, 0   ; деление на ноль
m_err_4x1        db "Error 4x1", 13, 10, 0   ; неизвестное слово
m_err_4x2        db "Error 4x2", 13, 10, 0   ; слишком длинно или много меток
m_err_4x3        db "Error 4x3", 13, 10, 0   ; нет такой метки
m_err_4x4        db "Error 4x4", 13, 10, 0   ; не тот регистр или число
m_err_4x5        db "Error 4x5", 13, 10, 0   ; файл не .pbi программа
m_dir_head       db "Files on disk:", 13, 10, 0

; Имена команд
c_clear          db "clear", 0
c_help           db "help", 0
c_ver            db "ver", 0
c_echo           db "echo", 0
c_about          db "about", 0
c_reboot         db "reboot", 0
c_exit           db "exit", 0
c_credits        db "credits", 0
c_time           db "time", 0
c_date           db "date", 0
c_calc           db "calc", 0
c_edit           db "edit", 0
c_read           db "read", 0
c_create         db "create", 0
c_dir            db "dir", 0
c_aqec           db "aqec", 0
c_run            db "run", 0

empty_arg        db 0
preset_name      db "notices.txt", 0
s_pbi            db ".pbi", 0

; Переменные и буферы
fsm_current_sec  db FSM_DIR
fsm_next_sector  db FSM_FIRST
fsm_bufptr       dw fsm_buffer  ; откуда писать и куда читать
fs_data          dw 0           ; что сохраняет fsm_save
boot_drive       db 0x80
cmdbuf           times 64 db 0
argptr           dw 0
note_buf         times 512 db 0
fsm_buffer       times 512 db 0

; Точка входа
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov [boot_drive], dl        ; загрузчик оставил номер диска в DL
    cld

    ; Прерывание для программ aqec
    xor ax, ax
    mov es, ax
    mov word [es:AQ_INT * 4], aq_sys
    mov [es:AQ_INT * 4 + 2], cs
    mov ax, cs
    mov es, ax

    call clearscr
    mov si, m_ver
    call print
    mov si, m_welcome
    call print
    mov si, m_about
    call print

    call fsm_init               ; читаем каталог, при первом запуске создаём notices.txt

main_loop:
    mov si, prompt
    call print

    mov di, cmdbuf
    call readline

    mov si, cmdbuf
    cmp byte [si], 0
    je main_loop

    call docmd
    jmp main_loop

; Ввод строки в [di]
readline:
    xor cx, cx
.l:
    call getkey
    cmp al, 13
    je .done
    cmp al, 8
    je .back
    cmp cx, 63
    jae .l
    stosb
    inc cx
    call putchar
    jmp .l
.back:
    test cx, cx
    jz .l
    dec cx
    dec di
    mov al, 8
    call putchar
    mov al, ' '
    call putchar
    mov al, 8
    call putchar
    jmp .l
.done:
    mov byte [di], 0
    call newline
    ret

; Разбор и запуск команды из cmdbuf
docmd:
    mov si, cmdbuf
    mov di, argptr
    mov byte [di], 0
.find_space:
    lodsb
    cmp al, 0
    je .no_arg
    cmp al, ' '
    je .found_space
    jmp .find_space
.found_space:
    mov byte [si-1], 0          ; отделяем команду от аргумента
.skip_spaces:
    lodsb
    cmp al, ' '
    je .skip_spaces
    cmp al, 0
    je .no_arg
    dec si
    mov [argptr], si
    jmp .check_cmds
.no_arg:
    mov word [argptr], empty_arg
.check_cmds:

    mov si, cmdbuf
    mov di, c_clear
    call streq
    test al, al
    jz .not_clear
    call clearscr
    ret
.not_clear:

    mov si, cmdbuf
    mov di, c_help
    call streq
    test al, al
    jz .not_help
    mov si, m_help
    call print
    ret
.not_help:

    mov si, cmdbuf
    mov di, c_ver
    call streq
    test al, al
    jz .not_ver
    mov si, m_ver
    call print
    ret
.not_ver:

    mov si, cmdbuf
    mov di, c_echo
    call streq
    test al, al
    jz .not_echo
    mov si, [argptr]
    call print
    call newline
    ret
.not_echo:

    mov si, cmdbuf
    mov di, c_about
    call streq
    test al, al
    jz .not_about
    mov si, m_about
    call print
    ret
.not_about:

    mov si, cmdbuf
    mov di, c_reboot
    call streq
    test al, al
    jz .not_reboot
    call do_reboot
    ret
.not_reboot:

    mov si, cmdbuf
    mov di, c_exit
    call streq
    test al, al
    jz .not_exit
    call do_exit
    ret
.not_exit:

    mov si, cmdbuf
    mov di, c_credits
    call streq
    test al, al
    jz .not_credits
    mov si, m_credits
    call print
    ret
.not_credits:

    mov si, cmdbuf
    mov di, c_time
    call streq
    test al, al
    jz .not_time
    call show_time
    ret
.not_time:

    mov si, cmdbuf
    mov di, c_date
    call streq
    test al, al
    jz .not_date
    call show_date
    ret
.not_date:

    mov si, cmdbuf
    mov di, c_calc
    call streq
    test al, al
    jz .not_calc
    call do_calc
    ret
.not_calc:

    mov si, cmdbuf
    mov di, c_edit
    call streq
    test al, al
    jz .not_edit
    call do_edit
    ret
.not_edit:

    mov si, cmdbuf
    mov di, c_read
    call streq
    test al, al
    jz .not_read
    call do_read
    ret
.not_read:

    mov si, cmdbuf
    mov di, c_create
    call streq
    test al, al
    jz .not_create
    call do_create
    ret
.not_create:

    mov si, cmdbuf
    mov di, c_dir
    call streq
    test al, al
    jz .not_dir
    call do_dir
    ret
.not_dir:

    mov si, cmdbuf
    mov di, c_aqec
    call streq
    test al, al
    jz .not_aqec
    call do_aqec
    ret
.not_aqec:

    mov si, cmdbuf
    mov di, c_run
    call streq
    test al, al
    jz .not_run
    call do_run
    ret
.not_run:

    mov si, m_err_1x1           ; неизвестная команда
    call print
    ret

; Выключение через APM
do_exit:
    mov si, m_exit_msg
    call print
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    mov ax, 0x530e
    xor bx, bx
    mov cx, 0x0102
    int 0x15
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
.hang_exit:
    hlt
    jmp .hang_exit

; Перезагрузка: переход на FFFF:0000
do_reboot:
    db 0xea
    dw 0x0000
    dw 0xffff

; Время из BIOS
show_time:
    mov ah, 0x02
    int 0x1a
    mov al, ch
    call print_bcd
    mov al, ':'
    call putchar
    mov al, cl
    call print_bcd
    mov al, ':'
    call putchar
    mov al, dh
    call print_bcd
    call newline
    ret

; Дата из BIOS: CH - век, CL - год, DH - месяц, DL - день
show_date:
    mov ah, 0x04
    int 0x1a
    mov al, dl
    call print_bcd
    mov al, '.'
    call putchar
    mov al, dh
    call print_bcd
    mov al, '.'
    call putchar
    mov al, ch
    call print_bcd
    mov al, cl
    call print_bcd
    call newline
    ret

; Печать BCD-байта из al
print_bcd:
    push ax
    shr al, 4
    add al, '0'
    call putchar
    pop ax
    and al, 0x0f
    add al, '0'
    call putchar
    ret

; Сравнение строк si и di. al = 1, если равны
streq:
.l:
    lodsb
    mov bl, [di]
    cmp al, bl
    jne .not_equal
    cmp al, 0
    je .equal
    inc di
    jmp .l
.not_equal:
    xor al, al
    ret
.equal:
    mov al, 1
    ret

clearscr:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    ret

; Печать строки из si до нуля
print:
    lodsb
    cmp al, 0
    je .done
    call putchar
    jmp print
.done:
    ret

putchar:
    mov ah, 0x0e
    xor bx, bx
    int 0x10
    ret

newline:
    mov al, 13
    call putchar
    mov al, 10
    call putchar
    ret

getkey:
    mov ah, 0x00
    int 0x16
    ret

; Текстовый редактор. Ctrl+S - конец текста, Esc - выход
do_edit:
    call clearscr
    mov si, m_edit_help
    call print
    mov di, note_buf            ; чистим буфер от прошлого текста
    mov cx, 512
    xor al, al
    rep stosb
    mov di, note_buf
    xor cx, cx
.edit_loop:
    call getkey
    cmp al, 27
    je .exit_editor
    cmp al, 19
    je .save_editor
    cmp al, 8
    je .edit_back

    cmp al, 13
    jne .not_enter
    cmp cx, 510                 ; Enter занимает два байта
    jae .edit_loop
    stosb
    inc cx
    call putchar
    mov al, 10
    stosb
    inc cx
    call putchar
    jmp .edit_loop

.not_enter:
    cmp cx, 511
    jae .edit_loop
    stosb
    inc cx
    call putchar
    jmp .edit_loop

.edit_back:
    test cx, cx
    jz .edit_loop
    cmp byte [di - 1], 10       ; стираем перевод строки?
    jne .normal_back
    dec cx
    dec di
    dec cx
    dec di
    mov ah, 0x03                ; позиция курсора: DH - строка, DL - колонка
    xor bh, bh
    int 0x10
    test dh, dh
    jz .edit_loop
    dec dh                      ; курсор в конец строки выше
    mov dl, 79
    mov ah, 0x02
    xor bh, bh
    int 0x10
    jmp .edit_loop

.normal_back:
    dec cx
    dec di
    mov al, 8
    call putchar
    mov al, ' '
    call putchar
    mov al, 8
    call putchar
    jmp .edit_loop

.save_editor:
    mov byte [di], 0
    jmp .edit_loop

.exit_editor:
    call clearscr
    ret

; Показать файл
do_read:
    pusha
    mov si, [argptr]
    cmp byte [si], 0
    je .err_empty

    call fsm_read_sector

    mov di, fsm_buffer
    mov cx, 32
.search_loop:
    cmp byte [di], 0
    je .next_slot
    push si
    push di
    call streq
    pop di
    pop si
    test al, al
    jnz .found_file
.next_slot:
    add di, 16
    loop .search_loop

    mov si, m_err_1x1
    call print
    popa
    ret

.found_file:
    mov al, [di + 15]           ; сектор файла - в последнем байте записи
    mov [fsm_current_sec], al
    call fsm_read_sector
    mov si, fsm_buffer
    call print
    call newline
    mov byte [fsm_current_sec], FSM_DIR
    popa
    ret

.err_empty:
    mov si, m_err_2x2
    call print
    popa
    ret

; Сохранить текст редактора в файл
do_create:
    pusha
    mov si, [argptr]
    cmp byte [si], 0
    je .err_empty
    mov ax, note_buf
    call fsm_save
    jc .done                    ; ошибку уже показали
    mov si, m_fs_ok
    call print
.done:
    popa
    ret
.err_empty:
    mov si, m_err_2x2
    call print
    popa
    ret

; Список файлов
do_dir:
    pusha
    call fsm_read_sector
    mov si, m_dir_head
    call print
    mov di, fsm_buffer
    mov cx, 32
.loop:
    cmp byte [di], 0
    je .skip_print
    push di
    mov si, di
    call print
    call newline
    pop di
.skip_print:
    add di, 16
    loop .loop
    popa
    ret

; Калькулятор: calc 40 / 2
do_calc:
    pusha
    mov di, [argptr]
    xor cx, cx
    cmp byte [di], 0
    je .empty_input
    call calc_parse
    popa
    ret
.empty_input:
    mov si, m_err_3x2
    call print
    popa
    ret

calc_parse:
    pusha
    mov si, [argptr]
    call calc_number            ; первое число
    mov bx, ax
.skip_spaces1:
    lodsb
    cmp al, ' '
    je .skip_spaces1
    mov dl, al                  ; знак
.skip_spaces2:
    lodsb
    cmp al, ' '
    je .skip_spaces2
    dec si
    call calc_number            ; второе число

    cmp dl, '+'
    jne .not_add
    add bx, ax
    jmp .print_res
.not_add:
    cmp dl, '-'
    jne .not_sub
    sub bx, ax
    jmp .print_res
.not_sub:
    cmp dl, '*'
    jne .not_mul
    imul bx, ax
    jmp .print_res
.not_mul:
    cmp dl, '/'
    jne .not_div
    test ax, ax
    jz calc_div0
    cwd
    xchg ax, bx
    idiv bx
    mov bx, ax
    jmp .print_res
.not_div:
    cmp dl, '%'
    jne .bad_sign
    test ax, ax
    jz calc_div0
    cwd
    xchg ax, bx
    idiv bx
    mov bx, dx
.print_res:
    mov ax, bx
    call print_num
    call newline
    popa
    ret
.bad_sign:
    mov si, m_err_3x1
    call print
    popa
    ret

calc_div0:
    mov si, m_err_3x3
    call print
    popa
    ret

; Число из строки si в ax, можно с минусом
calc_number:
    push bx
    push cx
    xor bx, bx
    xor cx, cx
    lodsb
    cmp al, '-'
    jne .p1
    mov cx, 1
    jmp .p2
.p1:
    dec si
.p2:
    lodsb
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    sub al, '0'
    xor ah, ah
    imul bx, 10
    add bx, ax
    jmp .p2
.done:
    dec si
    mov ax, bx
    jcxz .ok
    neg ax
.ok:
    pop cx
    pop bx
    ret

; Печать числа ax со знаком
print_num:
    pusha
    cmp ax, 0
    jge .p1
    push ax
    mov al, '-'
    call putchar
    pop ax
    neg ax
.p1:
    mov bx, 10
    xor cx, cx
.l1:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .l1
.l2:
    pop dx
    add dl, '0'
    mov al, dl
    call putchar
    loop .l2
    popa
    ret

; Диск: сектор fsm_current_sec, буфер fsm_bufptr
fsm_read_sector:
    pusha
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, [fsm_current_sec]
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, [fsm_bufptr]
    int 0x13
    jc .disk_error
    popa
    ret
.disk_error:
    mov si, m_err_2x3
    call print
    popa
    ret

fsm_write_sector:
    pusha
    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, [fsm_current_sec]
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, [fsm_bufptr]
    int 0x13
    jc .disk_error
    popa
    ret
.disk_error:
    mov si, m_err_2x3
    call print
    popa
    ret

; При запуске читаем каталог. Пустой - кладём notices.txt.
; Следующий свободный сектор - за самым дальним занятым.
fsm_init:
    pusha
    mov byte [fsm_current_sec], FSM_DIR
    call fsm_read_sector
    cmp byte [fsm_buffer], 0
    jne .scan
    mov di, fsm_buffer
    mov si, preset_name
.copy_preset:
    lodsb
    stosb
    test al, al
    jnz .copy_preset
    mov byte [fsm_buffer + 15], FSM_FIRST
    call fsm_write_sector
.scan:
    mov byte [fsm_next_sector], FSM_FIRST
    mov si, fsm_buffer
    mov cx, 32
.slot:
    cmp byte [si], 0
    je .next
    mov al, [si + 15]
    cmp al, [fsm_next_sector]
    jb .next
    inc al
    mov [fsm_next_sector], al
.next:
    add si, 16
    loop .slot
    popa
    ret

; Найти файл si в каталоге. CF = нет такого, иначе al = его сектор
fsm_find:
    push cx
    push si
    push di
    mov byte [fsm_current_sec], FSM_DIR
    mov word [fsm_bufptr], fsm_buffer
    call fsm_read_sector
    mov di, fsm_buffer
    mov cx, 32
.l:
    cmp byte [di], 0
    je .next
    push si
    push di
    call streq
    pop di
    pop si
    test al, al
    jnz .found
.next:
    add di, 16
    loop .l
    pop di
    pop si
    pop cx
    stc
    ret
.found:
    mov al, [di + 15]
    pop di
    pop si
    pop cx
    clc
    ret

; Прочитать сектор al в память по адресу di
fsm_load:
    mov [fsm_current_sec], al
    mov [fsm_bufptr], di
    call fsm_read_sector
    mov word [fsm_bufptr], fsm_buffer
    mov byte [fsm_current_sec], FSM_DIR
    ret

; Записать 512 байт из [ax] в файл с именем si.
; Файл есть - перезаписать, нет - создать. CF = ошибка (уже показана)
fsm_save:
    pusha
    mov [fs_data], ax
    mov byte [fsm_current_sec], FSM_DIR
    mov word [fsm_bufptr], fsm_buffer
    call fsm_read_sector

    mov di, fsm_buffer          ; такой файл уже есть?
    mov cx, 32
.find:
    cmp byte [di], 0
    je .next
    push si
    push di
    call streq
    pop di
    pop si
    test al, al
    jnz .write_data
.next:
    add di, 16
    loop .find

    mov di, fsm_buffer          ; ищем свободную запись
    mov cx, 32
.free:
    cmp byte [di], 0
    je .got_slot
    add di, 16
    loop .free
    jmp .full

.got_slot:
    cmp byte [fsm_next_sector], FSM_LAST
    ja .full
    mov bx, di
    mov cx, 14                  ; имя не длиннее 14 букв
.copy:
    lodsb
    test al, al
    jz .name_end
    stosb
    loop .copy
.name_end:
    mov byte [di], 0
    mov al, [fsm_next_sector]
    mov [bx + 15], al
    inc byte [fsm_next_sector]
    call fsm_write_sector       ; каталог
    mov di, bx

.write_data:
    mov al, [di + 15]
    mov [fsm_current_sec], al
    mov ax, [fs_data]
    mov [fsm_bufptr], ax
    call fsm_write_sector       ; сам файл
    mov word [fsm_bufptr], fsm_buffer
    mov byte [fsm_current_sec], FSM_DIR
    popa
    clc
    ret

.full:
    mov si, m_err_2x1
    call print
    popa
    stc
    ret

; aqec - язык и компилятор.
; aqec name читает исходник name и сохраняет машинный код в name.pbi.
; run name.pbi запускает программу. Регистры в начале равны нулю.
;
; Команды, каждая на своей строке:
;   b eax 5        mov: положить число в регистр
;   add eax        inc: прибавить 1, add eax 5 - прибавить 5
;   sub ecx        dec: отнять 1, sub ecx 2 - отнять 2
;   c ecx 0        cmp: сравнить регистр с числом
;   = метка        je: перейти, если равно
;   =- метка       jne: перейти, если не равно
;   go метка       jmp: перейти всегда
;   метка:         метка
;   p eax          вывести число из регистра
;   p "текст"      вывести текст
;   nl             перевод строки
; Регистры: eax, ebx, ecx, edx. Esc останавливает программу при выводе.

do_aqec:
    pusha
    mov si, [argptr]
    cmp byte [si], 0
    je .err_empty_name
    call fsm_find
    jc .no_file
    mov di, AQ_SRC
    call fsm_load
    mov byte [AQ_SRC + 511], 0  ; конец текста на всякий случай

    mov di, AQ_BIN              ; чистый образ и заголовок
    mov cx, 512
    xor al, al
    rep stosb
    mov dword [AQ_BIN], PBI_MAGIC

    mov word [aq_nlab], 0
    mov word [aq_nfix], 0
    mov si, AQ_SRC
    mov di, AQ_CODE
.line:
    call aq_skip_blank
    cmp byte [si], 0
    je .resolve
    cmp di, AQ_END - 8          ; кончается место под код
    jae .too_long
    call aq_token               ; слово в aq_word, длина в cx
    mov bx, cx
    cmp byte [aq_word + bx - 1], ':'
    jne .not_label
    mov byte [aq_word + bx - 1], 0
    call aq_add_label
    jc .too_long
    jmp .line
.not_label:
    mov bx, w_b
    call aq_is
    jnz .op_b
    mov bx, w_add
    call aq_is
    jnz .op_add
    mov bx, w_sub
    call aq_is
    jnz .op_sub
    mov bx, w_c
    call aq_is
    jnz .op_c
    mov bx, w_je
    call aq_is
    jnz .op_je
    mov bx, w_jne
    call aq_is
    jnz .op_jne
    mov bx, w_go
    call aq_is
    jnz .op_go
    mov bx, w_p
    call aq_is
    jnz .op_p
    mov bx, w_nl
    call aq_is
    jnz .op_nl
    mov si, m_err_4x1
    jmp .fail

.op_b:                          ; mov рег, число
    call aq_reg
    jc .bad_arg
    call aq_num
    jc .bad_arg
    mov byte [di], 0x66
    mov al, 0xB8
    add al, [aq_r]
    mov [di + 1], al
    mov eax, [aq_v]
    mov [di + 2], eax
    add di, 6
    jmp .line

.op_add:                        ; inc рег или add рег, число
    mov byte [aq_one], 0x40
    mov byte [aq_ext], 0xC0
    jmp .incdec
.op_sub:                        ; dec рег или sub рег, число
    mov byte [aq_one], 0x48
    mov byte [aq_ext], 0xE8
.incdec:
    call aq_reg
    jc .bad_arg
    call aq_skip_spaces
    call aq_has_number
    jc .with_number
    mov byte [di], 0x66
    mov al, [aq_one]
    add al, [aq_r]
    mov [di + 1], al
    add di, 2
    jmp .line
.with_number:
    call aq_num
    jc .bad_arg
    mov al, [aq_ext]
    jmp .op_imm

.op_c:                          ; cmp рег, число
    call aq_reg
    jc .bad_arg
    call aq_num
    jc .bad_arg
    mov al, 0xF8
.op_imm:                        ; 66 81 (код + рег) число: 7 байт
    add al, [aq_r]
    mov byte [di], 0x66
    mov byte [di + 1], 0x81
    mov [di + 2], al
    mov eax, [aq_v]
    mov [di + 3], eax
    add di, 7
    jmp .line

.op_je:                         ; je метка
    mov byte [aq_jcc], 0x84
    jmp .jump
.op_jne:                        ; jne метка
    mov byte [aq_jcc], 0x85
.jump:
    call aq_token
    test cx, cx
    jz .bad_arg
    mov byte [di], 0x0F
    mov al, [aq_jcc]
    mov [di + 1], al
    mov word [di + 2], 0        ; адрес впишем, когда найдём метку
    lea ax, [di + 2]
    call aq_add_fix
    jc .too_long
    add di, 4
    jmp .line

.op_go:                         ; jmp метка
    call aq_token
    test cx, cx
    jz .bad_arg
    mov byte [di], 0xE9
    mov word [di + 1], 0
    lea ax, [di + 1]
    call aq_add_fix
    jc .too_long
    add di, 3
    jmp .line

.op_nl:                         ; int AQ_INT, вызов 3
    mov byte [di], 0xCD
    mov byte [di + 1], AQ_INT
    mov byte [di + 2], 3
    add di, 3
    jmp .line

.op_p:                          ; вывод: регистр или текст
    call aq_skip_spaces
    cmp byte [si], '"'
    je .p_text
    call aq_reg
    jc .bad_arg
    mov byte [di], 0xCD         ; int AQ_INT, вызов 1, номер регистра
    mov byte [di + 1], AQ_INT
    mov byte [di + 2], 1
    mov al, [aq_r]
    mov [di + 3], al
    add di, 4
    jmp .line
.p_text:                        ; int AQ_INT, вызов 2, текст и ноль
    inc si
    mov byte [di], 0xCD
    mov byte [di + 1], AQ_INT
    mov byte [di + 2], 2
    add di, 3
.p_char:
    mov al, [si]
    test al, al
    jz .p_end
    cmp al, 13
    je .p_end
    cmp al, 10
    je .p_end
    inc si
    cmp al, '"'
    je .p_end
    cmp di, AQ_END - 2
    jae .too_long
    mov [di], al
    inc di
    jmp .p_char
.p_end:
    mov byte [di], 0
    inc di
    jmp .line

.resolve:
    mov byte [di], 0xC3         ; ret - конец кода
    mov cx, [aq_nfix]           ; вписываем адреса в переходы
    mov bx, AQ_FIX
.fix:
    jcxz .save
    push cx
    mov si, bx
    call aq_find_label          ; ax = адрес метки
    pop cx
    jc .bad_label
    mov di, [bx + 14]           ; место под адрес в коде
    sub ax, di
    sub ax, 2                   ; считаем от конца команды
    mov [di], ax
    add bx, 16
    dec cx
    jmp .fix

.save:
    mov si, [argptr]            ; имя результата: часть до точки и .pbi
    mov di, aq_outname
    mov cx, 10
.base:
    lodsb
    test al, al
    jz .ext
    cmp al, '.'
    je .ext
    stosb
    loop .base
.ext:
    mov si, s_pbi
.ext_l:
    lodsb
    stosb
    test al, al
    jnz .ext_l

    mov si, aq_outname
    mov ax, AQ_BIN
    call fsm_save
    jc .done                    ; ошибку уже показали
    mov si, m_built
    call print
    mov si, aq_outname
    call print
    call newline
.done:
    popa
    ret

.err_empty_name:
    mov si, m_err_2x2
    jmp .fail
.no_file:
    mov si, m_err_1x1
    jmp .fail
.too_long:
    mov si, m_err_4x2
    jmp .fail
.bad_arg:
    mov si, m_err_4x4
    jmp .fail
.bad_label:
    mov si, m_err_4x3
.fail:
    call print
    popa
    ret

; run name.pbi - загрузить программу и выполнить
do_run:
    pusha
    mov si, [argptr]
    cmp byte [si], 0
    je .err_empty
    call fsm_find
    jc .no_file
    mov di, AQ_BIN
    call fsm_load
    cmp dword [AQ_BIN], PBI_MAGIC
    jne .not_prog
    pushad
    xor eax, eax                ; в начале все регистры - ноль
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    mov [aq_sp], sp             ; сюда вернёмся, если нажмут Esc
    mov si, AQ_CODE
    call si
.after:
    popad
    popa
    ret
.err_empty:
    mov si, m_err_2x2
    jmp .fail
.no_file:
    mov si, m_err_1x1
    jmp .fail
.not_prog:
    mov si, m_err_4x5
.fail:
    call print
    popa
    ret

; Вызовы для программ: int AQ_INT, байт номера, затем данные.
; 1 - число из регистра, 2 - текст до нуля, 3 - перевод строки.
; Адрес возврата сдвигается за данные.
aq_sys:
    pushad
    mov bp, sp                  ; [bp + 32] - адрес возврата
    mov ah, 1                   ; нажата ли клавиша
    int 0x16
    jz .work
    xor ah, ah
    int 0x16
    cmp al, 27                  ; Esc останавливает программу
    je .abort
.work:
    mov si, [bp + 32]
    lodsb
    cmp al, 1
    je .reg
    cmp al, 2
    je .text
    cmp al, 3
    je .nl
    jmp .out
.reg:
    lodsb                       ; номер регистра
    movzx di, al
    shl di, 2
    neg di
    mov eax, [bp + di + 28]     ; eax лежит на 28, ecx на 24 и так далее
    call print_num32
    jmp .out
.text:
    lodsb
    test al, al
    jz .out
    call putchar
    jmp .text
.nl:
    call newline
.out:
    mov [bp + 32], si
    popad
    iret
.abort:
    mov si, m_stop
    call print
    sti
    mov sp, [aq_sp]
    jmp do_run.after

; Слово до пробела или конца строки в aq_word (до 15 букв), длина в cx
aq_token:
    call aq_skip_spaces
    push bx
    mov bx, aq_word
    xor cx, cx
.l:
    mov al, [si]
    cmp al, ' '
    je .end
    cmp al, 13
    je .end
    cmp al, 10
    je .end
    test al, al
    jz .end
    cmp cx, 15
    jae .skip
    mov [bx], al
    inc bx
    inc cx
.skip:
    inc si
    jmp .l
.end:
    mov byte [bx], 0
    pop bx
    ret

; aq_word равно слову bx? ZF = 0, если да
aq_is:
    push si
    push di
    mov si, aq_word
    mov di, bx
    call streq
    pop di
    pop si
    test al, al
    ret

; Регистр в номер aq_r. CF = неизвестный регистр
aq_reg:
    push cx
    push bx
    call aq_token
    xor cx, cx
.l:
    mov bx, cx
    shl bx, 1
    mov bx, [aq_regs + bx]
    call aq_is
    jnz .ok
    inc cx
    cmp cx, 4
    jb .l
    pop bx
    pop cx
    stc
    ret
.ok:
    mov [aq_r], cl
    pop bx
    pop cx
    clc
    ret

; Число (можно с минусом) в aq_v. CF = числа нет
aq_num:
    push cx
    call aq_skip_spaces
    call aq_has_number
    jnc .none
    xor cx, cx
    cmp byte [si], '-'
    jne .digits
    inc cx
    inc si
.digits:
    xor ebx, ebx
.l:
    movzx eax, byte [si]
    sub al, '0'
    cmp al, 9
    ja .end
    imul ebx, ebx, 10
    add ebx, eax
    inc si
    jmp .l
.end:
    jcxz .pos
    neg ebx
.pos:
    mov [aq_v], ebx
    pop cx
    clc
    ret
.none:
    pop cx
    stc
    ret

; Запомнить метку aq_word по месту в коде di. CF = много меток
aq_add_label:
    push ax
    push bx
    push si
    push di
    mov ax, [aq_nlab]
    cmp ax, AQ_NLAB
    jae .full
    inc word [aq_nlab]
    shl ax, 4
    add ax, AQ_LAB
    mov bx, ax
    mov [bx + 14], di
    mov si, aq_word
    mov di, bx
    mov cx, 13
.copy:
    lodsb
    stosb
    test al, al
    jz .done
    loop .copy
    mov byte [di], 0
.done:
    pop di
    pop si
    pop bx
    pop ax
    clc
    ret
.full:
    pop di
    pop si
    pop bx
    pop ax
    stc
    ret

; Запомнить переход на метку aq_word, место под адрес в ax. CF = много
aq_add_fix:
    push bx
    push si
    push di
    push cx
    mov bx, [aq_nfix]
    cmp bx, AQ_NFIX
    jae .full
    inc word [aq_nfix]
    shl bx, 4
    add bx, AQ_FIX
    mov [bx + 14], ax
    mov si, aq_word
    mov di, bx
    mov cx, 13
.copy:
    lodsb
    stosb
    test al, al
    jz .done
    loop .copy
    mov byte [di], 0
.done:
    pop cx
    pop di
    pop si
    pop bx
    clc
    ret
.full:
    pop cx
    pop di
    pop si
    pop bx
    stc
    ret

; Найти метку с именем si. ax = адрес в коде, CF = нет такой
aq_find_label:
    push bx
    push cx
    push di
    mov cx, [aq_nlab]
    mov di, AQ_LAB
.l:
    jcxz .none
    push si
    push di
    call streq
    pop di
    pop si
    test al, al
    jnz .found
    add di, 16
    dec cx
    jmp .l
.found:
    mov ax, [di + 14]
    pop di
    pop cx
    pop bx
    clc
    ret
.none:
    pop di
    pop cx
    pop bx
    stc
    ret

; Пропустить пробелы и переводы строк
aq_skip_blank:
    cmp byte [si], ' '
    je .skip
    cmp byte [si], 13
    je .skip
    cmp byte [si], 10
    je .skip
    ret
.skip:
    inc si
    jmp aq_skip_blank

; Пропустить только пробелы
aq_skip_spaces:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp aq_skip_spaces
.done:
    ret

; Здесь число (цифра или минус)? CF = да
aq_has_number:
    cmp byte [si], '-'
    je .yes
    cmp byte [si], '0'
    jb .no
    cmp byte [si], '9'
    ja .no
.yes:
    stc
    ret
.no:
    clc
    ret

; Печать числа eax со знаком
print_num32:
    pushad
    test eax, eax
    jns .pos
    push eax
    mov al, '-'
    call putchar
    pop eax
    neg eax
.pos:
    mov ebx, 10
    xor cx, cx
.split:
    xor edx, edx
    div ebx
    push dx
    inc cx
    test eax, eax
    jnz .split
.out:
    pop ax
    add al, '0'
    call putchar
    loop .out
    popad
    ret

aq_word    times 16 db 0
aq_outname times 16 db 0
aq_nlab    dw 0
aq_nfix    dw 0
aq_sp      dw 0
aq_r       db 0
aq_v       dd 0
aq_one     db 0
aq_ext     db 0
aq_jcc     db 0
aq_regs    dw w_eax, w_ecx, w_edx, w_ebx   ; порядок как в машинном коде
w_eax      db "eax", 0
w_ecx      db "ecx", 0
w_edx      db "edx", 0
w_ebx      db "ebx", 0
w_b        db "b", 0
w_add      db "add", 0
w_sub      db "sub", 0
w_c        db "c", 0
w_je       db "=", 0
w_jne      db "=-", 0
w_go       db "go", 0
w_p        db "p", 0
w_nl       db "nl", 0

; Ядро занимает 16 секторов (KSECT в boot.asm)
times 16 * 512 - ($ - $$) db 0

; Место под файлы: секторы 18-41. Загрузчик их не читает,
; но образ диска должен быть такого размера.
times 40 * 512 - ($ - $$) db 0