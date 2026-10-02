; =============================================================================
;  CGA DEMO - a graphical demo for the IBM PC 5150 with a Color Graphics Adapter
;
;  Target : 8088 @ 4.77 MHz, CGA, MS-DOS 2.0+
;  Build  : fasm demo.asm demo.com
;  Run    : demo            (any key = next part, ESC = quit)
;
;  Parts:
;    1. Logo + raster (copper) bars     320x200, 4 colors + per-line background
;    2. Parallax starfield + scroller   320x200, 4 colors
;    3. XOR line kaleidoscope           640x200, 2 colors
;    4. Plasma                          40x25 text, 16 bg colors (blink off)
;    5. Credits                         80x25 text
;
;  Only 8086/8088 instructions are used.
;
;  Written by Erdem Ersoy (eersoy93) with Claude Code.
; =============================================================================

format binary as 'com'
use16
org 100h

VIDSEG     = 0B800h
CGA_MODE   = 3D8h                   ; mode control register
CGA_COLOR  = 3D9h                   ; color select register
CGA_STAT   = 3DAh                   ; status register
ROMFONT    = 0FA6Eh                 ; 8x8 font (chars 0-127) at F000:FA6E

TICKS_SEC  = 18                     ; BIOS timer ticks per second (~18.2)

NSTARS     = 60
STAR_YMIN  = 12
STAR_YRNG  = 150                    ; stars live in y = 12..161
SCR_Y      = 172                    ; scroller top line (24 lines tall)

QN         = 16                     ; qix history length (power of two)

; ---------------------------------------------------------------------------
; The 8088 only has short (+-127 byte) conditional jumps. FASM would silently
; emit the 386 near form (0F 8x) for longer ones, which crashes on an 8088
; (0Fh = POP CS). Force the short form so FASM reports an error instead.
; ---------------------------------------------------------------------------
irp cc, jo,jno,jb,jc,jnae,jae,jnb,jnc,je,jz,jne,jnz,jbe,jna,ja,jnbe, \
        js,jns,jp,jpe,jnp,jpo,jl,jnge,jge,jnl,jle,jng,jg,jnle
{
    macro cc target \{ cc short target \}
}

; ---------------------------------------------------------------------------
; Text helpers: row, column (centered), color, text, 0
; ---------------------------------------------------------------------------
macro ctext40 row, color, [txt]
{
common
    local s, e
    db row, (40 - (e - s)) / 2, color
s:  db txt
e:  db 0
}

macro ctext80 row, color, [txt]
{
common
    local s, e
    db row, (80 - (e - s)) / 2, color
s:  db txt
e:  db 0
}

; =============================================================================
;  Main
; =============================================================================
start:
    cld
    call get_ticks
    mov [seed], ax
    call init_rowoff
    call init_plasma_pal

    mov si, scene_list
.next:
    lodsw
    or ax, ax
    jz exit
    push si
    call ax
    pop si
    cmp byte [quit], 0
    je .next

exit:
    mov ax, 0003h
    int 10h
    mov dx, msg_bye
    mov ah, 09h
    int 21h
    mov ax, 4C00h
    int 21h

scene_list:
    dw scene_logo
    dw scene_stars
    dw scene_qix
    dw scene_plasma
    dw scene_credits
    dw 0

; =============================================================================
;  Common routines
; =============================================================================

; CF=1 if a key was pressed (ESC also sets [quit])
check_key:
    mov ah, 1
    int 16h
    jz .none
    xor ah, ah
    int 16h
    cmp al, 27
    jne .key
    mov byte [quit], 1
.key:
    stc
    ret
.none:
    clc
    ret

; AX = low word of the BIOS tick counter
get_ticks:
    push ds
    xor ax, ax
    mov ds, ax
    mov ax, [046Ch]
    pop ds
    ret

timer_start:
    call get_ticks
    mov [t0], ax
    mov word [frame], 0
    ret

; in: BX = scene length in ticks. CF=1 -> scene should end (key or timeout)
scene_done:
    call check_key
    jc .r
    call get_ticks
    sub ax, [t0]
    cmp ax, bx
    cmc
.r: ret

; wait for the start of vertical retrace
wait_vsync:
    mov dx, CGA_STAT
.a: in al, dx
    test al, 8
    jnz .a
.b: in al, dx
    test al, 8
    jz .b
    ret

; AX = pseudo random number (LCG), destroys DX
rand:
    mov ax, [seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [seed], ax
    ret

; rowoff[y] = offset of scanline y in CGA graphics memory (modes 4, 5, 6)
init_rowoff:
    mov di, rowoff
    xor ax, ax
    mov cx, 100
.r: mov [di], ax                    ; even line: bank 0
    add ax, 2000h
    mov [di+2], ax                  ; odd line: bank 1
    sub ax, 2000h - 80
    add di, 4
    loop .r
    ret

; Print a list of strings through the BIOS (works in graphics modes too).
; SI -> { row, col, color, text, 0 } ... 0FFh
gprint_list:
    lodsb
    cmp al, 0FFh
    je .done
    mov dh, al
    lodsb
    mov dl, al
    lodsb
    mov bl, al
    xor bh, bh
    mov ah, 02h
    push bx
    int 10h
    pop bx
.ch:
    lodsb
    or al, al
    jz gprint_list
    mov ah, 0Eh
    push si
    push bx
    int 10h
    pop bx
    pop si
    jmp .ch
.done:
    ret

; Write a list of strings straight into 80x25 text memory (ES = VIDSEG).
; SI -> { row, col, attr, text, 0 } ... 0FFh
tprint_list:
    lodsb
    cmp al, 0FFh
    je .done
    mov bl, 80
    mul bl                          ; AX = row * 80
    mov di, ax
    lodsb
    xor ah, ah
    add di, ax
    shl di, 1
    lodsb
    mov ah, al                      ; attribute
.ch:
    lodsb
    or al, al
    jz tprint_list
    stosw
    jmp .ch
.done:
    ret

hide_cursor:
    mov ah, 01h
    mov cx, 2000h
    int 10h
    ret

; =============================================================================
;  Part 1 - logo + copper bars (mode 4)
; =============================================================================
scene_logo:
    mov ax, 0004h
    int 10h
    mov ax, VIDSEG
    mov es, ax
    mov dx, CGA_COLOR
    mov al, 30h                     ; palette 1 (cyan/magenta/white), bright
    out dx, al

    mov byte [lg_shadow], 1         ; drop shadow first...
    mov word [lg_y], 43
    mov word [lg_x], 9
    call draw_logo
    mov byte [lg_shadow], 0         ; ...then the logo on top
    mov word [lg_y], 40
    mov word [lg_x], 8
    call draw_logo

    mov si, txt_logo
    call gprint_list

    call timer_start
.frame:
    call build_bars
    call copper_frame
    inc word [frame]
    mov bx, TICKS_SEC * 14
    call scene_done
    jnc .frame
    mov dx, CGA_COLOR
    mov al, 30h
    out dx, al
    ret

; Draw "CGA DEMO": every font bit becomes one byte (4 pixels) x 5 lines.
draw_logo:
    xor bp, bp                      ; logo line 0..39
.line:
    mov ax, bp
    mov cl, 5
    div cl                          ; AL = font row
    xor ah, ah
    mov si, logo_font
    add si, ax

    cmp byte [lg_shadow], 0
    je .grad
    mov al, 11h                     ; dithered cyan shadow
    test bp, 1
    jz .pat
    mov al, 44h
    jmp .pat
.grad:
    mov al, [logo_grad+bp]
.pat:
    mov [lg_pat], al

    mov bx, bp
    add bx, [lg_y]
    shl bx, 1
    mov di, [rowoff+bx]
    add di, [lg_x]

    mov ch, 8                       ; 8 characters
.char:
    mov ah, [si]
    mov dl, 8                       ; 8 bits
.bit:
    shl ah, 1
    jnc .skip
    mov al, [lg_pat]
    mov [es:di], al
.skip:
    inc di
    dec dl
    jnz .bit
    add si, 8
    dec ch
    jnz .char

    inc bp
    cmp bp, 40
    jb .line
    ret

; Fill bars[200] with the background color of every scanline.
build_bars:
    push es
    push ds
    pop es
    mov di, bars
    mov ax, 3030h
    mov cx, 100
    rep stosw
    pop es

    xor si, si                      ; bar index
.bar:
    xor bh, bh
    mov al, byte [frame]
    shl al, 1
    add al, [bar_phase+si]
    mov bl, al
    mov al, [sintab+bx]
    cbw
    sar ax, 1
    mov dx, ax
    mov al, byte [frame]
    mov ah, al
    shl al, 1
    add al, ah                      ; frame * 3
    add al, [bar_phase2+si]
    mov bl, al
    mov al, [sintab+bx]
    cbw
    sar ax, 1
    sar ax, 1
    add dx, ax
    add dx, 92                      ; DX = top line (may be < 0)

    mov bx, si
    shl bx, 1
    mov di, [bar_ptr+bx]
    mov cx, 15
.ln:
    cmp dx, 200
    jae .clip                       ; unsigned: also catches negatives
    mov bx, dx
    mov al, [di]
    or al, 30h
    mov [bars+bx], al
.clip:
    inc di
    inc dx
    loop .ln

    inc si
    cmp si, 3
    jb .bar
    ret

; Race the beam: change the background color on every scanline.
copper_frame:
    mov dx, CGA_STAT
.v1: in al, dx
    test al, 8
    jnz .v1
.v2: in al, dx
    test al, 8
    jz .v2                          ; now in vertical retrace

    mov si, bars
    lodsb
    mov dl, 0D9h
    out dx, al                      ; color of line 0
    mov dl, 0DAh
    mov cx, 199
    cli
.l: lodsb
    mov ah, al
.w1: in al, dx                      ; wait for visible part of the line
    test al, 1
    jnz .w1
.w2: in al, dx                      ; wait for horizontal blank
    test al, 1
    jz .w2
    mov al, ah
    mov dl, 0D9h
    out dx, al
    mov dl, 0DAh
    loop .l
.w3: in al, dx
    test al, 1
    jnz .w3
.w4: in al, dx
    test al, 1
    jz .w4
    mov al, 30h                     ; black bottom border
    mov dl, 0D9h
    out dx, al
    sti
    ret

; =============================================================================
;  Part 2 - parallax starfield + big scroller (mode 4)
; =============================================================================
scene_stars:
    mov ax, 0004h
    int 10h
    mov ax, VIDSEG
    mov es, ax
    mov dx, CGA_COLOR
    mov al, 30h
    out dx, al

    mov si, txt_stars
    call gprint_list

    ; init stars
    xor bx, bx
    xor si, si                      ; layer 0..2
.init:
    call rand
    mov al, ah
    mov dl, 160
    mul dl
    mov al, ah                      ; (rnd * 160) / 256 = 0..159
    xor ah, ah
    shl ax, 1                       ; 0..318
    mov [star_x+bx], ax
    call rand
    mov al, ah
    mov dl, STAR_YRNG
    mul dl
    mov al, ah
    xor ah, ah
    add ax, STAR_YMIN
    mov [star_y+bx], ax
    mov ax, si
    inc ax
    mov [star_col+bx], ax           ; color 1..3
    mov cl, al
    dec cl
    mov ax, 1
    shl ax, cl
    mov [star_spd+bx], ax           ; speed 1, 2, 4
    mov word [star_off+bx], 0
    mov word [star_mask+bx], 0
    inc si
    cmp si, 3
    jb .l3
    xor si, si
.l3:
    add bx, 2
    cmp bx, NSTARS * 2
    jb .init

    ; init scroller
    mov word [scr_ptr], scroll_msg
    mov byte [scr_bit], 0
    mov byte [scr_sub], 0
    call scroll_load_char

.frame:
    call wait_vsync
    call update_stars
    call scroll_step
    jc .done
    call check_key
    jnc .frame
.done:
    ret

update_stars:
    xor bx, bx
.s:
    mov di, [star_off+bx]           ; erase old star
    mov al, byte [star_mask+bx]
    not al
    and [es:di], al

    mov ax, [star_x+bx]
    sub ax, [star_spd+bx]
    jns .ok
    add ax, 320
    push ax
    call rand                       ; new random line
    mov al, ah
    mov dl, STAR_YRNG
    mul dl
    mov al, ah
    xor ah, ah
    add ax, STAR_YMIN
    mov [star_y+bx], ax
    pop ax
.ok:
    mov [star_x+bx], ax

    mov si, [star_y+bx]
    shl si, 1
    mov di, [rowoff+si]
    mov dx, ax
    shr dx, 1
    shr dx, 1
    add di, dx
    and al, 3
    mov cl, 3
    sub cl, al
    shl cl, 1                       ; (3 - (x & 3)) * 2
    mov al, byte [star_col+bx]
    shl al, cl
    or [es:di], al
    mov [star_off+bx], di
    mov byte [star_mask+bx], al

    add bx, 2
    cmp bx, NSTARS * 2
    jb .s
    ret

; copy the 8x8 ROM glyph of the next message char to curglyph
; CF=1 at the end of the message
scroll_load_char:
    mov si, [scr_ptr]
    lodsb
    or al, al
    jnz .ok
    stc
    ret
.ok:
    mov [scr_ptr], si
    xor ah, ah
    mov cl, 3
    shl ax, cl
    add ax, ROMFONT
    mov si, ax
    push ds
    mov ax, 0F000h
    mov ds, ax
    xor bx, bx
.g: lodsb
    mov [cs:curglyph+bx], al
    inc bx
    cmp bx, 8
    jb .g
    pop ds
    clc
    ret

; scroll 24 lines left by 4 pixels and draw the new right column
; CF=1 when the message is finished
scroll_step:
    push ds
    push es
    pop ds
    mov bx, SCR_Y * 2
    mov dx, 24
.sh:
    mov di, [cs:rowoff+bx]
    mov si, di
    inc si
    mov cx, 79
    rep movsb
    add bx, 2
    dec dx
    jnz .sh
    pop ds

    mov bx, SCR_Y * 2
    mov si, curglyph
    mov cl, [scr_bit]
    xor bp, bp
    mov dh, 8                       ; 8 font rows, 3 lines each
.row:
    lodsb
    shl al, cl                      ; current bit -> bit 7
    mov dl, 3
.ln:
    mov di, [rowoff+bx]
    add di, 79
    xor ah, ah
    test al, 80h
    jz .w
    mov ah, [scroll_grad+bp]
.w: mov [es:di], ah
    inc bp
    add bx, 2
    dec dl
    jnz .ln
    dec dh
    jnz .row

    xor byte [scr_sub], 1           ; every font bit is 2 bytes wide
    jnz .same
    inc byte [scr_bit]
    cmp byte [scr_bit], 8
    jb .same
    mov byte [scr_bit], 0
    jmp scroll_load_char            ; returns CF
.same:
    clc
    ret

; =============================================================================
;  Part 3 - XOR line kaleidoscope (mode 6)
; =============================================================================
scene_qix:
    mov ax, 0006h
    int 10h
    mov ax, VIDSEG
    mov es, ax
    mov si, txt_qix
    call gprint_list

    mov word [q_head], 0
    mov word [q_count], 0
    mov byte [q_colidx], 0
    call timer_start
.frame:
    call wait_vsync

    mov ax, [frame]                 ; cycle the foreground color
    test al, 7
    jnz .nocol
    mov bl, [q_colidx]
    xor bh, bh
    mov al, [q_colors+bx]
    mov dx, CGA_COLOR
    out dx, al
    inc bl
    cmp bl, 7
    jb .c1
    xor bl, bl
.c1: mov [q_colidx], bl
.nocol:

    cmp word [q_count], QN          ; erase the oldest line
    jb .notfull
    mov si, [q_head]
    add si, q_hist
    mov ax, [si]
    mov bx, [si+2]
    mov cx, [si+4]
    mov dx, [si+6]
    call qline
    jmp .move
.notfull:
    inc word [q_count]
.move:
    xor bx, bx                      ; move and bounce the end points
.m: mov ax, [q_pos+bx]
    add ax, [q_vel+bx]
    cmp ax, [q_min+bx]
    jge .a
    mov ax, [q_min+bx]
    neg word [q_vel+bx]
.a: cmp ax, [q_max+bx]
    jle .b
    mov ax, [q_max+bx]
    neg word [q_vel+bx]
.b: mov [q_pos+bx], ax
    add bx, 2
    cmp bx, 8
    jb .m

    mov si, [q_head]                ; remember and draw the new line
    add si, q_hist
    mov ax, [q_pos]
    mov [si], ax
    mov bx, [q_pos+2]
    mov [si+2], bx
    mov cx, [q_pos+4]
    mov [si+4], cx
    mov dx, [q_pos+6]
    mov [si+6], dx
    call qline
    mov ax, [q_head]
    add ax, 8
    and ax, QN * 8 - 1
    mov [q_head], ax

    inc word [frame]
    mov bx, TICKS_SEC * 16
    call scene_done
    jc .done
    jmp .frame                      ; too far for a short jump
.done:
    ret

; draw line (AX,BX)-(CX,DX) and its horizontal mirror image
qline:
    push ax
    push bx
    push cx
    push dx
    call line6
    pop dx
    pop cx
    pop bx
    pop ax
    neg ax
    add ax, 639
    neg cx
    add cx, 639
    ; fall through

; XOR line (AX,BX)-(CX,DX) in 640x200 mode, Bresenham
line6:
    push bp
    mov si, ax                      ; SI = x
    mov di, 1
    sub cx, ax
    jge .p1
    neg cx
    neg di
.p1: mov [l_dx], cx
    mov [l_sx], di
    mov di, 1
    sub dx, bx
    jge .p2
    neg dx
    neg di
.p2: mov [l_dy], dx
    mov [l_sy], di
    mov bp, cx
    sub bp, dx                      ; err = dx - dy
    cmp cx, dx
    jge .p3
    mov cx, dx
.p3: inc cx                         ; points = max(dx, dy) + 1
.plot:
    push bx
    shl bx, 1
    mov di, [rowoff+bx]
    mov ax, si
    shr ax, 1
    shr ax, 1
    shr ax, 1
    add di, ax
    mov bx, si
    and bx, 7
    mov al, [bitmask+bx]
    xor [es:di], al
    pop bx

    mov ax, bp
    shl ax, 1                       ; e2 = 2 * err
    mov dx, ax
    add dx, [l_dy]
    jle .noX                        ; e2 > -dy ?
    sub bp, [l_dy]
    add si, [l_sx]
.noX:
    cmp ax, [l_dx]
    jge .noY                        ; e2 < dx ?
    add bp, [l_dx]
    add bx, [l_sy]
.noY:
    loop .plot
    pop bp
    ret

; =============================================================================
;  Part 4 - plasma in 40x25 text mode with 16 background colors
; =============================================================================
scene_plasma:
    mov ax, 0001h
    int 10h
    call hide_cursor
    mov dx, CGA_MODE
    mov al, 08h                     ; 40x25 color text, video on, blink OFF
    out dx, al
    mov dx, CGA_COLOR
    xor al, al
    out dx, al
    mov ax, VIDSEG
    mov es, ax

    call timer_start
.frame:
    call wait_vsync
    call plasma_tables
    call plasma_draw
    inc word [frame]
    mov bx, TICKS_SEC * 16
    call scene_done
    jnc .frame
    ret

plasma_tables:
    xor bh, bh
    mov al, byte [frame]
    ; xtab[i] = sin(6i + 2t) + sin(3i - 3t)
    mov dl, al
    shl dl, 1
    mov dh, al
    add dh, al
    add dh, al
    neg dh
    mov di, xtab
    mov cx, 72
.x: mov bl, dl
    mov ah, [sintab+bx]
    mov bl, dh
    add ah, [sintab+bx]
    mov [di], ah
    inc di
    add dl, 6
    add dh, 3
    loop .x

    ; ytab[y] = sin(8y + 3t) + sin(5y - t)
    mov dl, al
    add dl, al
    add dl, al
    mov dh, al
    neg dh
    mov di, ytab
    mov cx, 25
.y: mov bl, dl
    mov ah, [sintab+bx]
    mov bl, dh
    add ah, [sintab+bx]
    mov [di], ah
    inc di
    add dl, 8
    add dh, 5
    loop .y

    ; yshift[y] = (sin(6y + 4t) + 128) / 8   -> 0..31
    mov dl, al
    shl dl, 1
    shl dl, 1
    mov di, yshift
    mov cx, 25
    push cx
    mov cl, 3
.s: mov bl, dl
    mov ah, [sintab+bx]
    xor ah, 80h
    shr ah, cl
    mov [di], ah
    inc di
    add dl, 6
    pop ax
    dec ax
    push ax
    jnz .s
    pop ax
    ret

plasma_draw:
    xor di, di
    xor bh, bh
    xor bp, bp                      ; row
.row:
    mov bl, [yshift+bp]
    lea si, [xtab+bx]
    mov dl, [ytab+bp]
    mov cx, 40
.cell:
    lodsb
    add al, dl
    mov bl, al
    mov al, [pchar+bx]
    mov ah, [pattr+bx]
    stosw
    loop .cell
    inc bp
    cmp bp, 25
    jb .row
    ret

; 256-entry cyclic palette: 16 colors x 4 shades (space, 25%, 50%, 75%)
init_plasma_pal:
    xor bx, bx
.p: mov al, bl
    mov cl, 2
    shr al, cl                      ; level 0..63
    mov ah, al
    and ah, 3                       ; shade 0..3
    shr al, cl                      ; color index 0..15
    push bx
    mov bl, al
    xor bh, bh
    mov dl, [pl_cols+bx]
    inc bl
    and bl, 15
    mov dh, [pl_cols+bx]
    mov bl, ah
    mov al, [shade_chars+bx]
    pop bx
    mov cl, 4
    shl dl, cl
    or dl, dh                       ; bg = color, fg = next color
    mov [pchar+bx], al
    mov [pattr+bx], dl
    inc bl
    jnz .p
    ret

; =============================================================================
;  Part 5 - credits (80x25 text)
; =============================================================================
scene_credits:
    mov ax, 0003h
    int 10h
    call hide_cursor
    mov ax, VIDSEG
    mov es, ax
    mov si, txt_credits
    call tprint_list

    call timer_start
.frame:
    call wait_vsync
    inc word [frame]
    mov al, byte [frame]                 ; slowly cycling border
    mov cl, 4
    shr al, cl
    and al, 7
    mov bl, al
    xor bh, bh
    mov al, [border_cols+bx]
    mov dx, CGA_COLOR
    out dx, al
    mov bx, TICKS_SEC * 30
    call scene_done
    jnc .frame
    ret

; =============================================================================
;  Data
; =============================================================================
quit        db 0
seed        dw 1234h

; 256-entry sine table, amplitude 127 (Bhaskara I approximation)
sintab:
repeat 256
    a = % - 1
    if a < 128
        t = a
    else
        t = a - 128
    end if
    p = t * (128 - t)
    v = (127 * 4 * 32400 * p) / (663552000 - 32400 * p)
    if a < 128
        db v
    else
        db -v
    end if
end repeat

; --- part 1 ---
; "CGA DEMO" glyphs (IBM PC 8x8 font)
logo_font:
    db 03Ch, 066h, 0C0h, 0C0h, 0C0h, 066h, 03Ch, 000h   ; C
    db 03Ch, 066h, 0C0h, 0C0h, 0CEh, 066h, 03Eh, 000h   ; G
    db 030h, 078h, 0CCh, 0CCh, 0FCh, 0CCh, 0CCh, 000h   ; A
    db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h   ;
    db 0F8h, 06Ch, 066h, 066h, 066h, 06Ch, 0F8h, 000h   ; D
    db 0FEh, 062h, 068h, 078h, 068h, 062h, 0FEh, 000h   ; E
    db 0C6h, 0EEh, 0FEh, 0FEh, 0D6h, 0C6h, 0C6h, 000h   ; M
    db 038h, 06Ch, 0C6h, 0C6h, 0C6h, 06Ch, 038h, 000h   ; O

; white -> cyan -> magenta, dithered (palette 1: 1=cyan 2=magenta 3=white)
logo_grad:
    db 0FFh, 0FFh, 0FFh, 0FFh, 0DDh, 0FFh, 077h, 0DDh, 077h, 0DDh
    db 055h, 077h, 055h, 055h, 055h, 055h, 066h, 055h, 099h, 066h
    db 066h, 099h, 0AAh, 066h, 0AAh, 0AAh, 0AAh, 0AAh, 088h, 0AAh
    db 022h, 088h, 022h, 088h, 022h, 000h, 000h, 000h, 000h, 000h

bar_phase   db 0, 85, 170
bar_phase2  db 0, 60, 140
bar_ptr     dw bar_red, bar_blue, bar_green
bar_red     db 4, 4, 12, 4, 12, 12, 14, 15, 14, 12, 12, 4, 12, 4, 4
bar_blue    db 1, 1, 9, 1, 9, 9, 11, 15, 11, 9, 9, 1, 9, 1, 1
bar_green   db 2, 2, 10, 2, 10, 10, 11, 15, 11, 10, 10, 2, 10, 2, 2

txt_logo:
    ctext40 13, 3, 'IBM PC 5150 * COLOR GRAPHICS ADAPTER'
    ctext40 15, 1, '320x200  4 COLORS  RASTER BARS'
    ctext40 21, 2, 'CODED IN 8088 ASSEMBLY WITH FASM'
    ctext40 23, 1, 'ANY KEY: NEXT PART   ESC: EXIT'
    db 0FFh

; --- part 2 ---
txt_stars:
    ctext40 0, 3, '- STARFIELD -'
    db 0FFh

scroll_grad:
    db 0FFh, 0FFh, 0DDh, 0FFh, 077h, 0DDh, 055h, 077h
    db 055h, 055h, 066h, 055h, 099h, 066h, 0AAh, 099h
    db 0AAh, 0AAh, 088h, 0AAh, 022h, 088h, 000h, 000h

scroll_msg:
    db '          HELLO FROM THE IBM PC 5150!   '
    db 'THIS IS 320x200 IN 4 GLORIOUS COLORS...   '
    db 'THREE LAYERS OF STARS, A CHUNKY SCROLLER AND NOTHING BUT 8088 CODE.   '
    db 'GREETINGS TO EVERYONE KEEPING OLD IRON ALIVE!          ', 0

; --- part 3 ---
txt_qix:
    ctext80 0, 1, '640x200 HI-RES MODE  -  XOR LINE KALEIDOSCOPE'
    db 0FFh

bitmask     db 80h, 40h, 20h, 10h, 08h, 04h, 02h, 01h
q_colors    db 9, 11, 10, 14, 12, 13, 15
q_pos       dw 100, 50, 520, 160
q_vel       dw 7, 3, -5, 4
q_min       dw 0, 10, 0, 10
q_max       dw 639, 199, 639, 199

; --- part 4 ---
pl_cols     db 0, 1, 9, 11, 15, 11, 3, 1, 0, 4, 12, 14, 15, 14, 12, 4
shade_chars db 20h, 0B0h, 0B1h, 0B2h

; --- part 5 ---
border_cols db 1, 9, 3, 11, 5, 13, 4, 12

txt_credits:
    ctext80 1, 01h, 78 dup 0DCh
    ctext80 3, 0Fh, 'C  G  A     D  E  M  O'
    ctext80 5, 0Bh, 'A graphical demo for the IBM PC 5150 Color Graphics Adapter'
    ctext80 8, 0Eh, 'Part 1   Logo and raster bars          320x200, 4 colors + per-line bg '
    ctext80 9, 0Eh, 'Part 2   Parallax starfield, scroller  320x200, 4 colors               '
    ctext80 10, 0Eh, 'Part 3   XOR line kaleidoscope         640x200, 2 colors               '
    ctext80 11, 0Eh, 'Part 4   Plasma                        40x25 text, 16 bg colors        '
    ctext80 14, 07h, 'Written in 8086 assembly with the flat assembler (FASM).'
    ctext80 15, 07h, 'Runs on a 4.77 MHz 8088 with CGA, or in DOSBox-X with machine=cga.'
    ctext80 18, 0Ah, 'Thanks for watching!'
    ctext80 21, 8Fh, 'Press any key to return to DOS'
    ctext80 23, 01h, 78 dup 0DFh
    db 0FFh

msg_bye     db 'CGA DEMO - thanks for watching!', 13, 10, '$'

; =============================================================================
;  Uninitialized data (not stored in the .COM file)
; =============================================================================
align 2
t0          rw 1
frame       rw 1
rowoff      rw 200

lg_x        rw 1
lg_y        rw 1
lg_shadow   rb 1
lg_pat      rb 1
bars        rb 200

star_x      rw NSTARS
star_y      rw NSTARS
star_spd    rw NSTARS
star_col    rw NSTARS
star_off    rw NSTARS
star_mask   rw NSTARS
scr_ptr     rw 1
scr_bit     rb 1
scr_sub     rb 1
curglyph    rb 8

align 2
q_head      rw 1
q_count     rw 1
q_colidx    rb 1
align 2
l_dx        rw 1
l_dy        rw 1
l_sx        rw 1
l_sy        rw 1
q_hist      rw QN * 4

xtab        rb 72
ytab        rb 25
yshift      rb 25
pchar       rb 256
pattr       rb 256
