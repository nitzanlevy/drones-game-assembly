section .text 
    global current_drone_id
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

%macro print_float 1
    pushad
    fld dword[%1]
    sub esp, 8
    fstp qword[esp]
    push float_format_new_line
    call printf
    add esp,12
    popad
%endmacro


%macro print_float2 1
    pushad
    fld dword[%1]
    sub esp, 8
    fstp qword[esp]
    push float_format_new_line2
    call printf
    add esp,12
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
    fiadd dword[random_helper]   ;add ST(0)+lower_bound
    ; now we have in ST(0) random number in [lowerbound,range-lowerbound]
    fstp dword[%3]
    ffree
    popad
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

section .rodata
    say_hello:  db 'I am drone', 10, 0
    print_r: db 'register value is: %d', 10, 0 
    drone_x_coordinate: equ 1
    drone_y_coordinate: equ 5
    drone_speed: equ 9
    drone_heading: equ 13
    drone_score: equ 17
    size_of_drone: equ 21
    float_format_new_line: db '%.2f', 10, 0
    float_format_new_line2: db 'value is: %.2f', 10, 0


section .data 
    one_eighty:	dd 	180.0
    ninety:	dd	90.0
    one_hundred: dd 100.0
    three_hundred_sixty: dd 360.0
    zero: dd 0
    
section .bss
    current_drone_id: resb 4
    random_helper:resb 4
    heading_helper: resb 4
    speed_helper: resb 4

    delta_x_sqr: resb 4
    delta_y_sqr: resb 4
    result_destroy: resb 4

section .text
    global FuncDrone
    extern generate_number
    extern target_x_coordinate
    extern target_y_coordinate
    extern drones_array
    extern seed
    extern resume
    extern COScheduler
    extern COTarget
    extern D

    extern printf

; (*) Generate random heading change angle  ∆α       ; generate a random number in range [-60,60] degrees, with 16 bit resolution
; (*) Generate random speed change ∆a         ; generate random number in range [-10,10], with 16 bit resolution        
; (*) Compute a new drone position as follows:
;     (*) first move speed units at the direction defined by the current angle, wrapping around the torus if needed.
;         For example, if speed=60 then move 60 units in the current direction.
;     (*) then change the current angle to be α + ∆α, keeping the angle between [0, 360] by wraparound if needed
;     (*) then change the current speed to be speed + ∆a, keeping the speed between [0, 100] by cutoff if needed
; (*) Do forever
;     (*) if mayDestroy(…) (check if a drone may destroy the target)
;         (*) destroy the target	
;         (*) resume target co-routine
;     (*) Generate random angle ∆α       ; generate a random number in range [-60,60] degrees, with 16 bit resolution
;     (*) Generate random speed change ∆a    ; generate random number in range [-10,10], with 16 bit resolution        
;     (*) Compute a new drone position as follows:
;         (*) first, move speed units at the direction defined by the current angle, wrapping around the torus if needed. 
;         (*) then change the new current angle to be α + ∆α, keeping the angle between [0, 360] by wraparound if needed
;         (*) then change the new current speed to be speed + ∆a, keeping the speed between [0, 100] by cutoff if needed
;     (*) resume scheduler co-routine by calling resume(scheduler)	
; (*) end do

FuncDrone:
    
    reserve_regs
    mov edx,[current_drone_id]
    mov ebx,dword[drones_array]
    imul edx,size_of_drone
    add ebx, edx
    ;now ebx is pointer to the start of the drone data

    ;(*) Generate random heading change angle  ∆α       ;generate a random number in range [-60,60] degrees, with 16 bit resolution
    randon_number_in_range -60, 120 , heading_helper

    ;(*) Generate random speed change ∆a       ; generate random number in range [-10,10], with 16 bit resolution
    randon_number_in_range -10, 20, speed_helper

    ;(*)move speed units at the direction defined by the current angle, wrapping around the torus if needed.
    finit
    fld dword[ebx + drone_heading]

    fldpi       ; Convert heading into radians
	fmulp       ; multiply by pi
	fld	dword [one_eighty]
	fdivp	      ; and divide by 180.0
    fsincos  ; Compute vectors in y and x 
    fld	dword [ebx+drone_speed]
	fmulp        ; Multiply by distance to get dy 	
    fld	dword [ebx + drone_y_coordinate]
	faddp
	fstp dword [ebx + drone_y_coordinate]
	fld	dword [ebx + drone_speed]
	fmulp;        ; Multiply by distance to get ∆x
	fld	dword [ebx+drone_x_coordinate]
	faddp			    
    fstp dword [ebx + drone_x_coordinate]
    ;finish to change x,y
    

    fld	dword [heading_helper]; get the ∆α  
    fadd dword[ebx + drone_heading]
    fstp dword[ebx + drone_heading]


    fld dword[speed_helper]
    fadd dword[ebx + drone_speed]
    fstp dword[ebx + drone_speed]
    

    ; ;check if the drone x coordinate is over 100 and reduce 100 of it if it does
    fld dword[one_hundred]
    fld dword[ebx + drone_x_coordinate]
    fcomi
    ffreep
    jb dont_reduce_one_hundred_of_x_coo
    
    fld dword[ebx + drone_x_coordinate]
    fsub dword[one_hundred]
    fstp dword[ebx + drone_x_coordinate]

    dont_reduce_one_hundred_of_x_coo:

    ; ;check if the drone x coordinate is less 0 and add 100 of it if it does
    fld dword[zero]
    fld dword[ebx + drone_x_coordinate]
    fcomi
    ffreep
    ja dont_add_one_hundred_of_x_coo

    fld dword[ebx + drone_x_coordinate]
    fadd dword[one_hundred]
    fstp dword[ebx + drone_x_coordinate]

    dont_add_one_hundred_of_x_coo:

     ; ;check if the drone y coordinate is over 100 and reduce 100 of it if it does
    fld dword[one_hundred]
    fld dword[ebx + drone_y_coordinate]
    fcomi
    ffreep
    jb dont_reduce_one_hundred_of_y_coo

    fld dword[ebx + drone_y_coordinate]
    fsub dword[one_hundred]
    fstp dword[ebx + drone_y_coordinate]

    dont_reduce_one_hundred_of_y_coo:
    
    ;check if the drone y coordinate is less 0 and add 100 of it if it does
    
    fld dword[zero]
    fld dword[ebx + drone_y_coordinate]
    fcomip
    ffreep
    ja dont_add_one_hundred_of_y_coo

    fld dword[ebx + drone_y_coordinate]
    fadd dword[one_hundred]
    fstp dword[ebx + drone_y_coordinate]

    dont_add_one_hundred_of_y_coo:


    ;; speed fix
    fld dword[one_hundred]
    fld dword[ebx+ drone_speed]
    fcomip
    ffreep
    jb dont_put_100_instead_of_speed

    fld dword[one_hundred]
    fstp dword[ebx+drone_speed] 

    dont_put_100_instead_of_speed:

    fld dword[zero]
    fld dword[ebx+ drone_speed]
    fcomip
    ffreep
    ja dont_put_0_instead_of_speed

    fld dword[zero]
    fstp dword[ebx+drone_speed] 

    dont_put_0_instead_of_speed:


    ;check if the drone heading is over 360 and reduce 360 of it if it does
    fld dword[three_hundred_sixty]
    fld dword[ebx + drone_heading]
    fcomi
    ffreep
    jb dont_reduce_three_hundred_sixty_of_heading
    
    fld dword[ebx + drone_heading]
    fsub dword[three_hundred_sixty]
    fstp dword[ebx + drone_heading]

    dont_reduce_three_hundred_sixty_of_heading:

    ;check if the drone heading is less 0 and add 360 of it if it does
    fld dword[zero]
    fld dword[ebx + drone_heading]
    fcomi
    ffreep
    ja dont_add_three_hundred_sixty_of_heading

    fld dword[ebx + drone_heading]
    fadd dword[three_hundred_sixty]
    fstp dword[ebx + drone_heading]

    dont_add_three_hundred_sixty_of_heading:

    call may_destroy                    ;checks if the drone can destroy the targer
    
    mov eax, dword[result_destroy]      ;put the result from the function may destroy in eax reg
    cmp eax, 1                         
    jne dont_destroy                    ;if the target can't be destroy by this drone resume the schedualer

    inc dword[ebx + drone_score]        ;if the target can be destroy increment this drone score, generate a new target and
    restore_regs
    mov ebx, COTarget
    call resume

    jmp FuncDrone

    dont_destroy:
    
    restore_regs
    mov ebx, COScheduler
    call resume   

    jmp FuncDrone

    ;∆x = target xcoordinate - drone x coordinate
    ;∆y = target y coordinate - drone y coordinate
    ;if ( ∆x^2 + ∆y^2  < D^2 )  return 1
    ;else return 0
    may_destroy:
        reserve_regs
        mov dword[delta_x_sqr], 0           ;reset the helper dwords
        mov dword[delta_y_sqr], 0
        finit                               ;reset the stack
        fld dword[target_x_coordinate]             
        fsub dword[ebx + drone_x_coordinate];now on the top of the stack leys ∆x = target xcoordinate - drone x coordinate
        fabs
        fst dword[delta_x_sqr]
        fmul dword[delta_x_sqr]     ;now there is ∆x^2 on the top of the stack
        fstp dword[delta_x_sqr]

        fld dword[target_y_coordinate]             
        fsub dword[ebx + drone_y_coordinate];now on the top of the stack leys ∆y = target ycoordinate - drone y coordinate
        fabs
        fst dword[delta_y_sqr]
        fmul dword[delta_y_sqr]     ;now there is ∆y^2 on the top of the stack
        fstp dword[delta_y_sqr]

        fld dword[delta_x_sqr]
        fld dword[delta_y_sqr]

        faddp             ;now on top of the stakc there is ∆x^2 + ∆y^2 and we need to compare it with D^2
        fsqrt   ;(∆x^2 + ∆y^2 )^1/2

        fld dword[D]
        mov eax, 0
        fcomi                        ;now we compare D with (∆x^2 + ∆y^2)^1/2 and return 1 if less
        ffree
        jb false
        inc eax
        false:
        mov dword[result_destroy], eax
        restore_regs
        ret
