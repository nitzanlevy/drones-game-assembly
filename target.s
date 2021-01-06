section .text
    global target_x_coordinate
    global target_y_coordinate
    global create_target

;first arg is the lower bound, second is range
%macro randon_number_in_range 3
    finit
    call generate_number    ;the function generate number [0,65535]
    fild dword[seed]    ;insert the current seed into the ST
    mov dword[random_helper], 65535  
    fidiv dword[random_helper]  ;divide ST(0)\65535 = seed\65535
    mov dword[random_helper], %2
    fimul dword[random_helper]  ;mul ST(0)*range
    mov dword[random_helper], %1 
    fadd dword[random_helper]   ;add ST(0)+lower_bound
    ; now we have in ST(0) random number in [lowerbound,range-lowerbound]
    fstp dword[%3]
    ffree
%endmacro

%macro print_float 1
    fld dword[%1]
    sub esp, 8
    fstp qword[esp]
    push float_format_new_line
    call printf
    add esp,12
%endmacro

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

%macro print_reg 1
	pushad
    push %1
	push print_r
	call printf
	add esp, 8 ; size of dword
	popad
%endmacro

section .bss
    target_x_coordinate: resb 4     ;4 bytes for floating point
    target_y_coordinate: resb 4     ;4 bytes for floating point
    random_helper:resb 4

section .rodata
    float_format_new_line: db '%.2f', 10, 0
    say_hello:  db 'I am target', 10, 0
    print_r: db 'reg value is: %d', 10, 0


section .text
    global FuncTarget
    global target_x_coordinate
    global target_y_coordinate
    extern printf
    extern resume
    extern generate_number
    extern seed
    extern COScheduler
    extern current_drone_id
    extern drones_co_routines_array
    extern printf

FuncTarget:
    call create_target              ;createing a new target since the last one was destroied
    mov edx, [current_drone_id]
    mov ebx, dword[drones_co_routines_array]
    lea ebx,[ebx+edx*8]  
    call resume 

    jmp FuncTarget

create_target:
    reserve_regs

    ;;x_coordinate
    randon_number_in_range 0, 100, target_x_coordinate    
    ;;y_coordinate
    randon_number_in_range 0, 100, target_y_coordinate

    restore_regs
    ret