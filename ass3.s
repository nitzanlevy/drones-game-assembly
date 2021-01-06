section .text
    global N
    global R
    global K
    global D
    global seed
    global generate_number
    global drones_array
    global resume
    global COScheduler
    global COPrinter
    global drones_co_routines_array
    global COTarget

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
    push number_format_new_line
    call printf
    add esp, 8
    popad
%endmacro

%macro print_float 1
    fld dword[%1]
    sub esp, 8
    fstp qword[esp]
    push float_format_new_line
    call printf
    add esp,12
%endmacro

%macro convert_string 3
    pushad
    push %1
    push %2
    push %3
    call sscanf
    add esp, 12
    popad
%endmacro

;first arg is the lower bound, second is range, third is mem place
%macro randon_number_in_range 3
    pushad
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
    popad
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

section .rodata
    STKSIZE: equ 16*1024    ;16KB
    CODEP: equ 0    ; offset of pointer to co-routine function in co-routine struct
    SPP: equ 4      ; offset of pointer to co-routine stack in co-routine struct 
    size_of_drone: equ 21 ;size of each drone is 21 bytes-(active-1 byte ,x_coordinate-4 bytes, y_coordinate-4 bytes, speed-4 bytes, heading- 4 bytes, score- 4 bytes)
    drone_active: equ 0
    drone_x_coordinate: equ 1
    drone_y_coordinate: equ 5
    drone_speed: equ 9
    drone_heading: equ 13
    drone_score: equ 17

    number_format: db '%d', 0
    float_format: db '%f', 0
    number_format_new_line: db '%d', 10, 0
    float_format_new_line: db '%.2f', 10, 0
    say_hello:  db 'hello world', 10, 0


section .bss
    N: resb 4                       ;number of drones
    R: resb 4                       ;number of full scheduler cycles between each elimination
    K: resb 4                       ;how many drone steps between game board printings
    D: resb 4                       ;maximum distance that allows to destroy a target
    seed: resb 4                    ;seed for initialization of LFSR shift register
    
    random_helper:resb 4
    drones_array: resb 4
    drones_co_routines_array: resb 4    
    CURR: resd 1
    SPT: resd 1                     ;temprary stack pointer
    SPMAIN: resd 1                  ;stack pointer of main
    STKPrinter: resb STKSIZE
    STKTarget: resb STKSIZE
    STKScheduler: resb STKSIZE

section .data
    COPrinter:  dd FuncPrinter
                dd STKPrinter + STKSIZE
    COTarget:   dd FuncTarget
                dd STKTarget + STKSIZE
    COScheduler:    dd FuncScheduler
                    dd STKScheduler + STKSIZE
    CORS:   dd COPrinter
            dd COTarget
            dd COScheduler

section .text
    global main

    extern FuncTarget
    extern FuncScheduler
    extern FuncPrinter
    extern FuncDrone
    extern malloc
    extern free
    extern printf
    extern sscanf
    extern create_target
    extern current_drone_id

main:
    mov ebp, esp
    mov ebx, dword [ebp+4]      ;got the number of argmuments (argc)
    mov ecx, dword [ebp+8]      ;pointer to argv

    ;getting all the command line args and put them in the global vars N,R,K,D,seed
    convert_string N, number_format, dword[ecx + 4]
    convert_string R, number_format, dword[ecx + 8]   
    convert_string K, number_format, dword[ecx + 12]
    convert_string D, float_format, dword[ecx + 16]
    convert_string seed, number_format, dword[ecx + 20]

    mov dword[current_drone_id],0
    call init_3cors
    call init_drones_co_routines
    call create_target
    call init_drones
    call startCo
    ret

init_3cors:
    reserve_regs
    mov ecx,0 
    init_cors_loop:
        cmp ecx, 3
        je end_init_cors_loop
        mov ebx, [4*ecx + CORS]     ;get pointer to COi struct
        mov eax, [ebx + CODEP]      ;get initial EIP value – pointer to COi function
        mov [SPT],esp               ;save ESP value                  
        mov esp,[ebx + SPP]         ;get initial ESP value – pointer to COi stack
        push eax                    ; push initial “return” address
        pushfd                      ; push flags
        pushad                      ; push all other registers
        mov [ebx+SPP],esp           ; save new SPi value (after all the pushes)
        mov esp,[SPT]               ; restore ESP value
        inc ecx
        jmp init_cors_loop
    end_init_cors_loop:
    restore_regs
    ret

init_drones:
    reserve_regs

    mov eax, [N] ;put in eax the number of drones
    imul eax, size_of_drone ;evaluate the space we need to save for all the drones
    push eax 
    call malloc     ; call malloc for save number_of_drones*size_of_drone(24)
    add esp,4
    mov [drones_array],eax  ;save the pointer to the array
    
    mov edi, [drones_array] ;edi is the pointer to the array
    mov ecx, 0
    init_drones_loop:
        cmp ecx, dword[N]
        je end_init_drones_loop
        
        ;calculate the offset of the specific drone in the array
        mov ebx, ecx
        imul ebx,size_of_drone
        
        ;active
        ;calculate the offset of the specific field
        mov eax,ebx
        add eax, drone_active 
        mov byte[edi + eax], 1 ;set drone_active to 1

        ;;x_coordinate
        ;calculate the offset of the specific field
        mov eax,ebx
        add eax, drone_x_coordinate 
        add eax, edi
        randon_number_in_range 0, 100, eax ;generate number between [0,100]
        
        ;;y_coordinate
        ;calculate the offset of the specific field
        mov eax, ebx
        add eax, drone_y_coordinate 
        add eax, edi
        randon_number_in_range 0, 100, eax  ;generate number between [0,100]


        ;;speed
        ;calculate the offset of the specific field
        mov eax, ebx
        add eax, drone_speed
        add eax, edi
        randon_number_in_range 0, 100 ,eax  ;generate number between [0,100]
         
        ;;heading
        ;calculate the offset of the specific field
        mov eax, ebx
        add eax, drone_heading 
        add eax, edi
        randon_number_in_range 0, 360, eax  ;generate number between [0,100]
        
        ;;score
        mov eax, ebx
        add eax, drone_score 
        mov dword[edi + eax], 0

        inc ecx
        jmp init_drones_loop
    end_init_drones_loop:
    restore_regs
    ret

init_drones_co_routines:
    reserve_regs
    mov eax, [N]
    imul eax, 8 ;eax = number_of_drones*(8bytes for co-routines struct) 
    push eax
    call malloc
    add esp, 4
    mov dword[drones_co_routines_array], eax
    mov esi,0
    init_drones_co_routines_loop:
        cmp esi, dword[N]
        je end_init_drones_co_routines_loop
        mov ebx, dword[drones_co_routines_array]
        lea ebx,[8*esi+ebx]
      
        mov dword[ebx + CODEP], FuncDrone    ;initiate pointer to COi function
        mov eax, STKSIZE
        push eax 
        call malloc
        add esp, 4
        add eax, STKSIZE    ;go to the end of the stk
        mov [ebx + SPP], eax        ;initiate pointer to COi stack
        
        mov eax, [ebx + CODEP]      ;get initial EIP value – pointer to COi function
        mov [SPT],esp               ;save ESP value                  
        mov esp,[ebx + SPP]         ;get initial ESP value – pointer to COi stack
        push eax                    ; push initial “return” address
        pushfd                      ; push flags
        pushad                      ; push all other registers
        mov [ebx+SPP],esp           ; save new SPi value (after all the pushes)
        mov esp,[SPT]               ; restore ESP value
        inc esi
        jmp init_drones_co_routines_loop

    end_init_drones_co_routines_loop:
    restore_regs
    ret


startCo:
    pushad ; save registers of main ()
    mov [SPMAIN], esp ; save ESP of main ()
    mov ebx, [CORS + 8] ; gets a pointer to a scheduler struct
    jmp do_resume ; resume a scheduler co-routine

resume: ; save state of current co-routine
    pushfd
    pushad
    mov edx, [CURR]
    mov [edx+SPP], esp ; save current ESP

do_resume: ; load ESP for resumed co-routine
    mov esp, dword[ebx+SPP]
    mov [CURR], ebx
    popad ; restore resumed co-routine state
    popfd
    ret ; "return" to resumed co-routine

generate_number:
    reserve_regs
    mov esi, 0
    generate_loop:
        cmp esi, 16
        je end_generate_loop
        mov ebx,0
        mov ecx,0
        mov eax,[seed]      ;move the seed input into 16 bits the bx reg which will be the output
        mov bx, ax
        and bx , 0x1        ;put in bx the LSB 16'th bit 
        
        mov cx , ax
        and cx , 0x4        ;put in cx the 14'th bit
        shr cx , 2
        xor bx , cx         ;perform xor between the 14'th and 16'th bits let the result be x
        
        mov cx , ax
        and cx , 0x8        ;put in cx the 13'th bit
        shr cx , 3
        xor bx , cx         ;perform xor between the 13'th and x bits let the result be y

        mov cx , ax
        and cx , 0x32       ;put in cx the 11'th bit
        shr cx , 5
        xor bx , cx         ;perform xor between the 11'th and y bits

        shr ax,1
        shl bx ,15
        or bx , ax 
        mov [seed] , bx
        inc esi
        jmp generate_loop
    
    end_generate_loop:
    restore_regs
    ret   