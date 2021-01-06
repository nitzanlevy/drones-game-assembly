%macro reserve_regs 0
    push ebp
    mov ebp,esp
    pushad
%endmacro

%macro restore_regs 0
    popad
    mov esp,ebp
    pop ebp
%endmacro
%macro print_hello 0
	pushad
	push say_hello
	call printf
	add esp, 4 ; size of dword
	popad
%endmacro

section .rodata
    size_of_drone: equ 21 ;size of each drone is 21 bytes-(active-1 byte ,x_coordinate-4 bytes, y_coordinate-4 bytes, speed-4 bytes, heading- 4 bytes, score- 4 bytes)
    drone_x_coordinate: equ 1
    drone_y_coordinate: equ 5
    drone_speed: equ 9
    drone_heading: equ 13
    drone_score: equ 17

    say_hello:  db 'I am printer', 10, 0
   	target_format_printer: db 10,"%.2f,%.2f",10,0
    ;;;;;;                   id   x_1   y_1   a_1  speed_1  score_1 
    drone_format_printer: db "%d, %.2f, %.2f, %.2f, %.2f , %d", 10, 0	; format string for popPrint

section .text
    global FuncPrinter
    extern printf
    extern COScheduler
    extern resume
    extern target_x_coordinate
    extern target_y_coordinate
    extern N
    extern drones_array

FuncPrinter:
    ;print terget cooradinate x,y
    fld dword [target_y_coordinate]
    fld dword [target_x_coordinate]
    sub esp,16
    fstp qword [esp]
    fstp qword [esp+8]
    push target_format_printer
    call printf
    add esp,20

    ;loop for print all drones
    mov ebx,[drones_array]
    mov esi,1
    print_loop:
        cmp esi, [N]
        jg end_print_loop

        ;load all the fields into the x87 stack
        fld dword [ebx+drone_speed]
        fld dword [ebx+drone_heading]
        fld dword [ebx+drone_y_coordinate]
        fld dword [ebx+drone_x_coordinate]
        mov eax, [ebx+drone_score]
        push eax    ;score

        ;pop the fiels from the x87 stack
        sub esp, 32
        fstp qword [esp]    ;speed
        fstp qword [esp+8]  ;heading
        fstp qword [esp+16] ;y
        fstp qword [esp+24] ;x
        push esi    ;id
        push drone_format_printer
        call printf
        add esp, 36

        add ebx, size_of_drone
        inc esi
        jmp print_loop

    end_print_loop:
    mov ebx, COScheduler
    call resume

    jmp FuncPrinter