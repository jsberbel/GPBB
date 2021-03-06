; Draws all pixels in the list of horizontal lines passed in, in
; mode X, the VGA's undocumented 320x240 256-color mode. Clips to
; the rectangle specified by (ClipMinX,ClipMinY),(ClipMaxX,ClipMaxY).
; Draws to the page specified by CurrentPageBase.
; C near-callable as:
;     void DrawHorizontalLineList(struct HLineList * HLineListPtr,
;          int Color);
;
; All assembly code tested with TASM 4.0.

SCREEN_WIDTH    equ     320
SCREEN_SEGMENT  equ     0a000h
SC_INDEX equ    03c4h   ;Sequence Controller Index
MAP_MASK equ    2       ;Map Mask register index in SC

HLine   struc
XStart  dw      ?       ;X coordinate of leftmost pixel in line
XEnd    dw      ?       ;X coordinate of rightmost pixel in line
HLine   ends

HLineList struc
Lngth   dw      ?       ;# of horizontal lines
YStart  dw      ?       ;Y coordinate of topmost line
HLinePtr dw     ?       ;pointer to list of horz lines
HLineList ends

Parms   struc
                dw      2 dup(?) ;return address & pushed BP
HLineListPtr    dw      ?       ;pointer to HLineList structure
Color           dw      ?       ;color with which to fill
Parms   ends
        .model small
        .data
        extrn   _CurrentPageBase:word,_ClipMinX:word
        extrn   _ClipMinY:word,_ClipMaxX:word,_ClipMaxY:word
; Plane masks for clipping left and right edges of rectangle.
LeftClipPlaneMask       db      00fh,00eh,00ch,008h
RightClipPlaneMask      db      001h,003h,007h,00fh
        .code
        align   2
ToFillDone:
        jmp     FillDone
        public _DrawHorizontalLineList
        align   2
_DrawHorizontalLineList proc
        push    bp              ;preserve caller's stack frame
        mov     bp,sp           ;point to our stack frame
        push    si              ;preserve caller's register variables
        push    di
        cld                     ;make string instructions inc pointers
        mov     dx,SC_INDEX
        mov     al,MAP_MASK
        out     dx,al           ;point SC Index to the Map Mask
        mov     ax,SCREEN_SEGMENT
        mov     es,ax   ;point ES to display memory for REP STOS
        mov     si,[bp+HLineListPtr] ;point to the line list
        mov     bx,[si+HLinePtr] ;point to the XStart/XEnd descriptor
                                ; for the first (top) horizontal line
        mov     cx,[si+YStart]  ;first scan line to draw
        mov     si,[si+Lngth]   ;# of scan lines to draw
        cmp     si,0            ;are there any lines to draw?
        jle     ToFillDone      ;no, so we're done
        cmp     cx,[_ClipMinY]  ;clipped at top?
        jge     MinYNotClipped  ;no
        neg     cx              ;yes, discard however many lines are
        add     cx,[_ClipMinY]  ; clipped
        sub     si,cx           ;that many fewer lines to draw
        jle     ToFillDone      ;no lines left to draw
        shl     cx,1            ;lines to skip*2
        shl     cx,1            ;lines to skip*4
        add     bx,cx           ;advance through the line list
        mov     cx,[_ClipMinY]  ;start at the top clip line
MinYNotClipped:
        mov     dx,si
        add     dx,cx           ;bottom row to draw + 1
        cmp     dx,[_ClipMaxY]  ;clipped at bottom?
        jle     MaxYNotClipped  ;no
        sub     dx,[_ClipMaxY]  ;# of lines to clip off the bottom
        sub     si,dx           ;# of lines left to draw
        jle     ToFillDone      ;all lines are clipped
MaxYNotClipped:
        mov     ax,SCREEN_WIDTH/4 ;point to the start of the first
        mul     cx              ; scan line on which to draw
        add     ax,[_CurrentPageBase] ;offset of first line
        mov     dx,ax           ;ES:DX points to first scan line to
                                ; draw
        mov     ah,byte ptr [bp+Color] ;color with which to fill
FillLoop:
        push    bx              ;remember line list location
        push    dx              ;remember offset of start of line
        push    si              ;remember # of lines to draw
        mov     di,[bx+XStart]  ;left edge of fill on this line
        cmp     di,[_ClipMinX]  ;clipped to left edge?
        jge     MinXNotClipped  ;no
        mov     di,[_ClipMinX]  ;yes, clip to the left edge
MinXNotClipped:
        mov     si,di
        mov     cx,[bx+XEnd]    ;right edge of fill
        cmp     cx,[_ClipMaxX]  ;clipped to right edge?
        jl      MaxXNotClipped  ;no
        mov     cx,[_ClipMaxX]  ;yes, clip to the right edge
        dec     cx
MaxXNotClipped:
        cmp     cx,di
        jl      LineFillDone    ;skip if negative width
        shr     di,1    ;X/4 = offset of first rect pixel in scan
        shr     di,1    ; line
        add     di,dx   ;offset of first rect pixel in display mem
        mov     dx,si   ;XStart
        and     si,0003h                ;look up left edge plane mask
        mov     bh,LeftClipPlaneMask[si] ; to clip & put in BH
        mov     si,cx
        and     si,0003h                  ;look up right edge plane
        mov     bl,RightClipPlaneMask[si] ; mask to clip & put in BL
        and     dx,not 011b     ;calculate # of addresses across rect
        sub     cx,dx
        shr     cx,1
        shr     cx,1    ;# of addresses across rectangle to fill - 1
        jnz     MasksSet ;there's more than one byte to draw
        and     bh,bl   ;there's only one byte, so combine the left
                        ; and right edge clip masks
MasksSet:
        mov     dx,SC_INDEX+1 ;already points to the Map Mask reg
FillRowsLoop:
        mov     al,bh   ;put left-edge clip mask in AL
        out     dx,al   ;set the left-edge plane (clip) mask
        mov     al,ah   ;put color in AL
        stosb           ;draw the left edge
        dec     cx      ;count off left edge byte
        js      FillLoopBottom ;that's the only byte
        jz      DoRightEdge ;there are only two bytes
        mov     al,00fh ;middle addresses are drawn 4 pixels at a pop
        out     dx,al   ;set the middle pixel mask to no clip
        mov     al,ah   ;put color in AL
        shr     cx,1    ;fill count in words
        rep     stosw   ;draw the middle addresses eight pixels apiece
        adc     cx,cx   ;odd address count
        rep     stosb   ;draw odd address, if any (four pixels with 1 write)
DoRightEdge:
        mov     al,bl   ;put right-edge clip mask in AL
        out     dx,al   ;set the right-edge plane (clip) mask
        mov     al,ah   ;put color in AL
        stosb           ;draw the right edge
FillLoopBottom:
LineFillDone:
        pop     si              ;retrieve # of lines to draw
        pop     dx              ;retrieve offset of start of line
        pop     bx              ;retrieve line list location
        add     dx,SCREEN_WIDTH/4 ;point to start of next line
        add     bx,size HLine   ;point to the next line descriptor
        dec     si              ;count down lines
        jnz     FillLoop
FillDone:
        pop     di              ;restore caller's register variables
        pop     si
        pop     bp              ;restore caller's stack frame
        ret
_DrawHorizontalLineList endp
        end
