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

%macro print_reg 1
    pushad
    push %1
    push print_r
    call printf
    add esp, 8
    popad
%endmacro
%macro print_hello 0
	pushad
	push say_hello
	call printf
	add esp, 4 ; size of dword
	popad
%endmacro
section .rodata
    MAX_INT: equ 2147483647 ;2^31-1
    STKSIZE: equ 16*1024    ;16KB
    size_of_drone: equ 21 ;size of each drone is 21 bytes-(active-1 byte ,x_coordinate-4 bytes, y_coordinate-4 bytes, speed-4 bytes, heading- 4 bytes, score- 4 bytes)
    active: equ 0
    say_hello:  db 'hello world', 10, 0
    number_format_new_line: db '%d', 10, 0
    winner_format: db 'The Winner is drone: %d', 10,0
    drone_score: equ 17
    print_r: db 'reg value is: %d', 10, 0

section .data
    iglobali: dd 0

section .text
    global FuncScheduler
    extern N
    extern K
    extern R
    extern print_func
    extern drones_array
    extern resume
    extern COScheduler
    extern COPrinter
    extern drones_co_routines_array
    extern printf
    extern exit
    extern current_drone_id
    extern free

FuncScheduler:
    mov esi,dword[iglobali]
    mov edx,0
    mov eax,esi 
    mov ebx,dword[N]
    idiv ebx    ;get the reminder in edx, for checking i%N
    
    ;edx is the drone's id
    push edx    ;backup edx
    mov eax,edx
    mov ebx,dword[drones_array]
    imul eax,size_of_drone
    add ebx, eax
    movzx ebx,byte[ebx] ; get the active flag of the current drone
    pop edx     ;restored edx
    cmp ebx, 0
    je drone_not_active
    
    ;if the drone is active
    mov [current_drone_id], edx
    mov ebx, dword[drones_co_routines_array]
    lea ebx,[ebx+edx*8]  
    call resume 

    inc dword[current_drone_id]
    
    drone_not_active:

    mov edx, 0
    mov eax, esi
    mov ebx, dword[K]
    IDIV ebx    ;get the reminder in edx, for checking i%K
    cmp edx, 0  ;if (i%K==0)
    jne skip1        
    
    ;time to print the game board
    mov ebx, COPrinter
    call resume
    
    skip1:
    
    mov edx, 0
    mov eax, esi 
    mov ebx, dword[N]
    IDIV ebx    ;get the quoient in eax- i/N

    mov edx, 0
    mov ebx, dword[R]
    IDIV ebx    ;get the reminder in edx
    cmp edx, 0
    jne skip2   ;if((i/N)%R == 0)
    
    mov edx, 0
    mov eax, esi 
    mov ebx, dword[N]
    IDIV ebx    ;get the quoient in eax- i/N
    cmp edx,0
    jne skip2   ;(if((i/N)%R == 0 && i%N == 0 ))
    call worst_drone_out
    
    skip2:

    call check_for_winner   ;if only one active drone is left
    inc dword[iglobali]
    jmp FuncScheduler
    
worst_drone_out:
    reserve_regs        
    mov esi,0   ;esi is the id of the drone we wiil destroy
    mov edi, MAX_INT    ;the min score
    
    cmp dword[N],1
    je check_for_winner
    mov ecx, 0
    ;find M - the lowest number of targets destroyed, between all of the active drones
    find_min_loop:
        cmp ecx,[N]
        je end_find_min_loop

        mov eax, ecx
        mov ebx,dword[drones_array]
        imul eax, size_of_drone
        add ebx, eax
        movzx eax,byte[ebx] ; get the active flag of the current drone
        cmp eax, 1  ;check if the drone is active
        
        je drone_is_active
        inc ecx
        jmp find_min_loop
        
        drone_is_active:

        mov ebx, dword[ebx+drone_score]   ;get the score of the current drone
        cmp ebx, edi    
        jge not_min_score
        
        mov esi, ecx    ;save the min drone id
        mov edi, ebx    ;save the miv drone score

        not_min_score:
        inc ecx
        jmp find_min_loop
    end_find_min_loop:

    ; "turn off" one of the drones that destroyed only M targets.
    mov eax,esi ;esi is the id of the min score drone
    mov ebx,dword[drones_array]
    imul eax,size_of_drone
    add ebx, eax
    mov byte[ebx], 0 ; get the active flag of the current drone

    ;now we finished and we should turn return
    restore_regs
    ret


check_for_winner:
    reserve_regs
    
    mov esi, 0 ;esi is the number of active drones
    mov edi, 0 ;if there is only 1 dorne active edi will be the id of this drone
    
    mov ecx,0
    count_active_loop:
        cmp ecx,[N]
        je end_count_active_loop
        
        mov eax, ecx
        mov ebx,dword[drones_array]
        imul eax,size_of_drone
        add ebx, eax
        movzx ebx,byte[ebx] ; get the active flag of the current drone
        cmp ebx, 0  ;check if the drone is active
        
        je drone_isnt_active
        
        inc esi
        mov edi, ecx

        drone_isnt_active:
        inc ecx
        jmp count_active_loop

    end_count_active_loop:

    cmp esi,1
    jne no_winner_yet
    inc edi ;for fix the id started from 0
    
    push edi
    push winner_format
    call printf
    add esp, 8

    ;free all the mallocs

    mov esi,0
    free_loop:
        cmp esi,[N]
        je end_free_loop
        
        mov ebx,[drones_co_routines_array]
        mov eax,esi
        imul eax, 8
        add ebx,eax
        ;now ebx pointer to the current struct

        add ebx, 4
        mov ebx,dword[ebx]
        ;now ebx pointer to the stki
        push dword[ebx]
        call free 
        add esp,4

        inc esi
        jmp free_loop
    end_free_loop:
    push 1 
    call exit

    no_winner_yet:
    restore_regs
    ret

    
