.model tiny
.code
locals @@
org 100h


Start:
    jmp main

;-----------------------------------------------------------------------------------------------------
; Constants
;-----------------------------------------------------------------------------------------------------

VIDEOSEG     equ 0b800h   ; Адрес сегмента видеопамяти
BIAS_FRAME   equ 370h     ; Смещение относительно начала видеопамяти (в байтах)
FRAME_COLOR  equ 2        ; Цвет рамки
FRAME_HEIGHT equ 9        ; Высота рамки
FRAME_WIDTH  equ 0dh      ; Ширина рамки
NUMBER_OF_REGISTERS equ 4 ; Количество показываемых на рамке регистров

REGISTERS db 41h, 2, 58h, 2, 42h, 2, 58h, 2, 43h, 2, 58h, 2, 44h, 2, 58h, 2 ; ax, bx, cx, dx зелёного цвета

RAMKA db 0c9h, 0cdh, 0bbh, 0bah, 0h, 0bah, 0c8h, 0cdh, 0bch ; Двойная рамка

;-----------------------------------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------------------------------

BUFFER_DISPLAY_SYMBOLS:
    dw FRAME_WIDTH * FRAME_HEIGHT dup(0h) ; Массив для хранения затёртой рамкой части экрана

BUFFER_REGISTERS:
    dd NUMBER_OF_REGISTERS * 2 dup(0h) ; Массив для хранения значений регистров в виде символов
                                       ; в порядке ax, bx, cx, dx

;-----------------------------------------------------------------------------------------------------
; Macro
;-----------------------------------------------------------------------------------------------------

SAVE_ALL_REGISTERS macro
    pushf
    push es
    push ds
    push si
    push di
    push bp
    push sp
    push ss
    push ax
    push bx
    push cx
    push dx
endm

RET_ALL_REGISTERS macro
    pop dx
    pop cx
    pop bx
    pop ax
    pop ss
    pop sp
    pop bp
    pop di
    pop si
    pop ds
    pop es
    popf
endm

LOAD_REGISTERS_BUFFER macro
    mov word ptr cs:[BUFFER_REGISTERS +  0 * 2], ax
    mov word ptr cs:[BUFFER_REGISTERS +  1 * 2], bx
    mov word ptr cs:[BUFFER_REGISTERS +  2 * 2], cx
    mov word ptr cs:[BUFFER_REGISTERS +  3 * 2], dx
endm

;-----------------------------------------------------------------------------------------------------
; Code
;-----------------------------------------------------------------------------------------------------

;-----------------------------------------------------------------------------------------------------
; При нажатии на клавиатуре клавиши '1' на нампаде, изменяет переменную Active на 1 и сохраняет экран,
; после нажатия '0' изменяет переменную Active на 0 соответственно и восстанавливает экран
; Entry: None
; Exit : None
; Destr: None
;-----------------------------------------------------------------------------------------------------

new09   proc
    SAVE_ALL_REGISTERS
    LOAD_REGISTERS_BUFFER

    in al, 60h

    cmp al, 4fh ; Сравнивает со скан кодом '1'
    je @@On     ; Если совпадает, то включаем прогу
    cmp al, 52h ; Сравнивает со скан кодом '0'
    je @@Off    ; Если совпадает, то выключаем прогу, если не совпадает, значит пропускам нажатие
    jmp @@Skip

    @@Off:
        cmp byte ptr cs:[Active], 0
        je @@Skip           ; Если программа уже выключена пропускаем нажатие
        mov cs:[Active], 0
        call recoverDisplay ; Восстанавливаю старые данные на экране
        jmp @@Skip

    @@On:
        cmp byte ptr cs:[Active], 0
        jne @@Skip       ; Если программа уже включена пропускаем нажатие
        call saveDisplay ; Сохраняю старые данные об экране
        mov cs:[Active], 1
        jmp @@Skip

    @@Skip:
        RET_ALL_REGISTERS

        db 0eah
        Old090fs dw 0
        Old09Seg dw 0

        Active db 0
    endp

;-----------------------------------------------------------------------------------------------------
; По переменной Active, узнаёт в каком режиме находится программа (1/0 = вкл/выкл), во включённом
; состоянии обновляет отображаемые значения регистров
; Entry: None
; Exit : None
; Destr: None
;-----------------------------------------------------------------------------------------------------

new08   proc
    SAVE_ALL_REGISTERS

    cmp byte ptr cs:[Active], 0
    je @@Skip

    LOAD_REGISTERS_BUFFER
    call frameOn

    @@Skip:
        RET_ALL_REGISTERS

        db 0eah
        Old080fs dw 0
        Old08Seg dw 0
    endp

;-----------------------------------------------------------------------------------------------------
; Стирает рамку с экрана и восстанавливает старый вид.
; Entry: None
; Exit : None
; Destr: bx, cx, dx, ds, es, di, si
;-----------------------------------------------------------------------------------------------------

recoverDisplay  proc
    cld                            ; Сбросил флаг направления
    push cs
    pop ds                         ; Так как работаем в tiny, всё лежит в одном сегменте
    lea si, BUFFER_DISPLAY_SYMBOLS ; Установил в ds:si адрес массива для хранения данных

    mov bx, VIDEOSEG
    mov es, bx         ; Установил адрес сегмента видеопамяти
    mov di, BIAS_FRAME ; Установил смещение от начала экрана

    mov cx, FRAME_WIDTH
    mov dx, FRAME_HEIGHT ; Задаю счётчики по вертикали и горизонтали

    @@DrawOneLine:
        push di
        push cx
        rep movsw ; Циклом печатаю строчку из памяти
        pop cx
        pop di

        add di, 80 * 2 ; Передвигаюсь на следующую

        dec dx
        cmp dx, 0 ; Проверяю не пора ли выйти из цикла
        jne @@DrawOneLine

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; Рисует рамку фиксированного размера со значением регистров внутри
; Entry: None
; Exit : None
; Destr: bx, cx, dx, ds, es, di, si
;-----------------------------------------------------------------------------------------------------

frameOn   proc
    cld ; Сбросил флаг направления

    push cs
    pop ds ; Так как работаем в tiny, всё лежит в одном сегменте

    lea si, [RAMKA]      ; в ds:si положил адрес строки с символами рамки
    mov cx, FRAME_WIDTH  ; Установил ширину рамки
    mov dx, FRAME_HEIGHT ; Установил высоту рамки
    mov ah, FRAME_COLOR  ; Установил цвет рамки
    mov di, BIAS_FRAME   ; Установил смещение от начала экрана до первого символа рамки

    call drawFrame ; Рисую рамку

    call drawTitle ; Рисую надпись

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; Сохраняет в памяти старый вид экрана
; Entry: None
; Exit : None
; Destr: bx, cx, dx, ds, es, di, si, al
;-----------------------------------------------------------------------------------------------------

saveDisplay proc
    mov bx, VIDEOSEG
    mov ds, bx         ; Установил адрес сегмента видеопамяти
    mov si, BIAS_FRAME ; Установил смещение от начала экрана

    push cs
    pop es
    lea di, BUFFER_DISPLAY_SYMBOLS ; Установил в es:di адрес массива для хранения данных

    mov cx, FRAME_WIDTH
    mov dx, FRAME_HEIGHT ; Задаю счётчики по вертикали и горизонтали

    SaveOneLine:
        push si
        push cx
        rep movsw ; Циклом сохраняю одну строчку
        pop cx
        pop si

        add si, 80 * 2 ; Передвигаюсь на следующую

        dec dx
        cmp dx, 0 ; Проверяю не пора ли выйти из цикла
        jne SaveOneLine

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; На рамке фиксированного размера рисует состояние регистров
; Entry: None
; Exit : None
; Destr: es, ds, ax, bx, cx, di, si
;-----------------------------------------------------------------------------------------------------

drawTitle   proc
    mov ax, VIDEOSEG
    mov es, ax             ; Устанавливаю адрес сегмента видеопамяти
    mov di, BIAS_FRAME
    add di, 80 * 2 + 2 * 2 ; Устанавливаю нужное смещение относительно начала экрана и на две строки
                           ; ниже и два столбца правее края рамки
    push cs
    pop ds
    lea si, [REGISTERS] ; В ds:si положил адрес строки с именами регистров

    mov bx, 023dh ; В bx положил символ '='
    mov cx, NUMBER_OF_REGISTERS

    @@DrawOneReg:          ; В цикле рисую названия регистров на рамке
        push di
        movsw
        movsw              ; Нарисовал имя регистра
        add di, 1 * 2      ; Пропуск
        mov es:[di], bx    ; '='
        pop di
        add di, 2 * 80 * 2 ; Перепрыгнул через строку
        loop @@DrawOneReg

    mov cx, NUMBER_OF_REGISTERS
    mov di, BIAS_FRAME
    add di, 80 * 2 + 7 * 2     ; Устанавливаю нужное смещение относительно начала экрана и на две строки
                               ; ниже и семь столбцов правее края рамки
    lea si, [BUFFER_REGISTERS] ; В ds:si положил адрес строки со значениями регистров

    @@DrawOneValue:
        push di
        push cx
        call conversionOneNumber
        pop cx
        pop di
        add si, 2          ; Перешёл на следующее значение
        add di, 2 * 80 * 2 ; Перепрыгнул через строку
        loop @@DrawOneValue

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; Конвертирует значение регистра si в символы определённого цвета и записывает по адресу es:[di]
; Entry: es:[di] - адрес памяти куда записать результат
;        ds:[si] - значение, которое нужно конвертировать
; Exit : None
; Destr: di, ax, cx
;-----------------------------------------------------------------------------------------------------

conversionOneNumber proc
    xor cx, cx ; Почистил значения

    OneSymbol:
        mov ax, [si] ; Переложил в ax значение для конвертации
        shl ax, cl
        shr ax, 12   ; Двумя командами оставил только один байт для конвертации его в ASCII-код
        cmp ax, 9    ; Сравнил с 9, если меньше или равно, то 0-9, если больше, то a-f
        jbe DecimalNumber
        ja HexadecimalNumber

    HexadecimalNumber:
        add al, 'A' - 0ah   ; Превратил в ASCII-код
        mov ah, FRAME_COLOR ; Указал нужный цвет
        stosw               ; Положил в память
        jmp NextSymbol      ; Прыгаю на проверку на следующий цикл

    DecimalNumber:
        add al, '0'         ; Превратил в ASCII-код
        mov ah, FRAME_COLOR ; Указал нужный цвет
        stosw               ; Положил в память
        jmp NextSymbol      ; Прыгаю на проверку на следующий цикл

    NextSymbol:
        add cl, 4  ; Увеличиваю счётчик
        cmp cl, 16 ; Проверяю условие выхода
        jne OneSymbol

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; Рисует рамку фиксированного размера и цвета
; Entry: ds:si - адрес строки с символами рамки
;           cx - ширина рамки
;           dx - высота рамки
;           ah - цвет рамки
;           di - смещение до первого символа рамки
; Exit : None
; Destr: al, bx, si, es, di, dx
;-----------------------------------------------------------------------------------------------------

drawFrame   proc
    sub cx, 2
    sub dx, 2 ; Для корректной работы не учитываю края рамки

    call drawLine ; Рисую первую линию рамки

    DrawMiddle:
        add di, 80 * 2 ; Делаю отступ
        call drawLine  ; Рисую линию
        sub si, 3      ; Возвращаю указатель на 4 символ рамки

        dec dx
        cmp dx, 0
        jne DrawMiddle

    add di, 80 * 2 ; Отступаю до начала следующей линии
    add si, 3      ; Ставлю указатель на 7 символ рамки
    call drawLine  ; Рисую последнюю линию

    ret
    endp

;-----------------------------------------------------------------------------------------------------
; Рисует строку из символов (первый, последний и промежуточные), с заданной длинной, цветом и отступом
; Entry: ds:si - адрес в памяти строки с рамкой
;           ah - цвет рамки
;           di - смещение
;           cx - ширина внутренней части рамки
; Exit : None
; Destr: al, bx, si, es
;-----------------------------------------------------------------------------------------------------

drawLine    proc
    push cx
    push di
    mov bx, VIDEOSEG
    mov es, bx ; Установил адрес сегмента видеопамяти

    lodsb     ; Загрузил в al первый символ рамки
    stosw     ; В видеопамять положил значение из ax

    lodsb     ; Загрузил в al второй символ рамки
    rep stosw ; В видеопамять cx символов из ax

    lodsb     ; Загрузил в al последний символ рамки
    stosw     ; В видеопамять положил значение из ax

    pop di
    pop cx
    ret
    endp


EOP:

main:
    xor ax, ax
    mov es, ax
    mov bx, 09h * 4
    mov di, 08h * 4

    mov ax, es:[bx]
    mov Old090fs, ax
    mov ax, es:[bx + 2]
    mov Old09Seg, ax

    mov ax, es:[di]
    mov Old080fs, ax
    mov ax, es:[di + 2]
    mov Old08Seg, ax

    cli
    push cs
    pop ax
    mov es:[bx], offset new09
    mov es:[bx + 2], ax

    mov es:[di], offset new08
    mov es:[di + 2], ax
    sti

    mov ax, 3100h
    mov dx, offset EOP
    shr dx, 4
    inc dx

    int 21h

end Start
