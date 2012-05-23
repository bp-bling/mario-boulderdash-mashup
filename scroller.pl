use strict;
use warnings;

=for comment

TODO:

* jump higher
* right/left momentum
* un-invert it back to not being callbacks but instead linear flow through
* rework scrolling so that blocks don't move, but the viewport does
* break blocks (of certain types)
* load map of level from an ASCII map (block objects)
* collision detection from tekroids.pl

=cut

use SDL;
use SDL::Rect;
use SDL::Events;
use Math::Trig;
use Collision::2D ':all';
use Data::Dumper;
use SDLx::App;
use SDLx::Controller::Interface;
use SDLx::Sprite::Animated;
use SDL::Joystick;

my $app = SDLx::App->new( w => 400, h => 400, dt => 0.02, title => 'Pario' );

my $joystick;
if( my $num_joysticks = SDL::Joystick::num_joysticks() ) {
    # XXX which joystick should be a parameter
    my $js_index = $num_joysticks-1;
    $joystick = SDL::Joystick->new($js_index) or die SDL::get_error;
    if($joystick) {
        printf("Opened Joystick $js_index\n");
        printf("Name: %s\n",              SDL::Joystick::name($js_index));
        printf("Number of Axes: %d\n",    SDL::Joystick::num_axes($joystick));
        printf("Number of Buttons: %d\n", SDL::Joystick::num_buttons($joystick));
        printf("Number of Balls: %d\n",   SDL::Joystick::num_balls($joystick));
    }
}

$app->update();

my @update_rects = ();

my $sprite = SDLx::Sprite::Animated->new(
    image           => 'data/m.bmp',
    rect            => SDL::Rect->new( 0, 0, 16, 28 ),
    ticks_per_frame => 6,
    alpha_key       => SDL::Color->new(139, 0, 139),
);

$sprite->set_sequences(
    left  => [ [ 0, 1 ], [ 1, 1 ], [ 2, 1 ], [ 3, 1 ], [ 4, 1 ] ],
    right => [ [ 0, 0 ], [ 1, 0 ], [ 2, 0 ], [ 3, 0 ], [ 4, 0 ] ],
    stopl => [ [ 0, 1 ] ],
    stopr => [ [ 0, 0 ] ],
    jumpr => [ [ 5, 0 ] ],
    jumpl => [ [ 5, 1 ] ],
    duckr => [ [ 6, 0 ] ],
    duckl => [ [ 6, 1 ] ],
);

$sprite->sequence('stopr');
$sprite->start();

my $obj = SDLx::Controller::Interface->new( x => 10, y => 380, v_x => 0, v_y => 0 );

do {
    # open my $fh, '<', 'level1.txt' or die;
    
};

my @blocks = (
    [ 19,  310 ],
    [ 40,  310 ],
    [ 30,  289 ],
    [ 120, 380 ],
    [ 141, 380 ],
    [ 141, 359 ]
);

foreach ( ( 0 .. 2, 10 ... 15, 17 ... 25 ) ) {
    push @blocks, [ $_ * 20 + $_ * 1, 380 ];
}

my $pressed                = {};      # some combination of left/right/up/down
my $lockjump               = 0;       # has jumped, hasn't hit the ground yet
my $vel_x                  = 100;     # X speed when walking/jumping
my $vel_y                  = -102;    # Y (initial) speed when jumping
my $quit                   = 0;
my $gravity                = 160;     # gravitational constant; was 180
my $gravity_delay          = 0;       # countdown, initialized from $gravity_delay_constant, before gravity kicks in for the current jump
my $gravity_delay_constant = 120;
my $dashboard              = '';      # debug message to display on-screen
my $w                      = 16;      # mario width
my $h                      = 28;      # mario height (but not necessarily block height, which is/was 20)
my $block_height           = 20;
my $block_width            = 20;
my $scroller               = 0;       # movement backlogged to recenter the screen

$obj->set_acceleration(
    sub {
        my $time  = shift;
        my $state = shift;
        $state->v_x(0);    # Don't move by default
        my $ay = 0;        # Y acceleration

        #
        # controls and animation selection
        #

        if ( $pressed->{right} ) {
            $state->v_x($vel_x);
            if   ( $pressed->{up} ) { $sprite->sequence('jumpr') }
            elsif ($sprite->sequence() ne 'right') { $sprite->sequence('right'); }

        }
        elsif ( $sprite->sequence() eq 'right' and ! $pressed->{left} ) {
            $sprite->sequence('stopr');
        }

        if ( $pressed->{left} ) {
            $state->v_x( -$vel_x );
            if   ( $pressed->{up} ) { $sprite->sequence('jumpl') }
            elsif ($sprite->sequence() ne 'left') { $sprite->sequence('left'); }
        }
        elsif ( $sprite->sequence() eq 'left' and ! $pressed->{right} ) {
            $sprite->sequence('stopl');
        }

        if ( $pressed->{up} && ! $lockjump ) {

            $sprite->sequence('jumpr')   if ( $sprite->sequence() =~ 'r'); # XXX
            $sprite->sequence('jumpl')   if ( $sprite->sequence() =~ 'l'); # XXX

            $state->v_y($vel_y);
            $gravity_delay = $gravity_delay_constant;
            $lockjump = 1;

        }

        #
        # collision checks
        #

        my $collision = check_collision( $state, \@blocks );
        $dashboard = 'Collision = ' . Dumper $collision;

        if ( $collision != -1 && $collision->[0] eq 'x' ) {
            my $block = $collision->[1];

            #X-axis collision_check
            if ( $state->v_x() > 0 ) {    #moving right
                $state->x( $block->[0] - $block_width - 3 );    # set to edge of block XXX what is 3 for?
            }

            if ( $state->v_x() < 0 ) {                #moving left
                $state->x( $block->[0] + 3 + $block_width );    # set to edge of block XXX what is 3 for?
            }
        }

        # y-axis collision_check

        if ( $state->v_y() < 0 ) {                    #moving up
            if ( $collision != -1 && $collision->[0] eq 'y' ) {
                my $block = $collision->[1];
                $state->y( $block->[1] + $block_height + 3 );    # stop just below block
                $state->v_y(0);                                  # momentum lost
            }
            else {
                # apply gravity; continue jumping
                if( $gravity_delay-- <= 0 ) {
                    $ay = $gravity; 
                }
            }
        }
        else {
            # moving along the ground 
            # Y velocity zero or greater than zero
            if ( $collision != -1 && $collision->[0] eq 'y' ) {
                my $block = $collision->[1];
                $state->y( $block->[1] - $h - 1 );  # hover one pixel over the block
                $state->v_y(0);                     # Causes test again in next frame
                $ay = 0;                            # no downward velocity
                $lockjump = 0 if ! $pressed->{up};  # able to jump again
                $sprite->sequence( 'stopr' ) if $sprite->sequence eq 'jumpr';
                $sprite->sequence( 'stopl' ) if $sprite->sequence eq 'jumpl';
            } 
            else { 
                # apply gravity; continue falling 
                # XXXX need a terminal velocity
                $ay = $gravity;
            }
        }

        if ( $state->y + 10 > $app->h ) {
            # fell off of the world
            $quit = 1;
        }

        #
        # re-center the screen
        #

        if ($scroller) {
            my $dir = 0;
            $scroller-- and $dir = +1 if $scroller > 0;
            $scroller++ and $dir = -1 if $scroller < 0;

            $state->x( $state->x() + $dir );

            $_->[0] += $dir foreach (@blocks); # XXXXXXXXXX move frame of reference instead

        }
        else {
            if ( $state->x() > $app->w - 100 ) {
                $scroller = -5;
            }
            if ( $state->x() < 100 ) {
                $scroller = 5;
            }

        }

        # return ( $accel_x, $accel_y, $torque );
        return ( 0, $ay, 0 );
    }
);

#
# read keyboard and joystick
#

$app->add_event_handler(
    sub {
        $_[1]->stop if $_[0]->type == SDL_QUIT || $quit;

        my $key = $_[0]->key_sym;
        my $name = SDL::Events::get_key_name($key) if $key;

        if ( $_[0]->type == SDL_KEYDOWN ) {
            $pressed->{$name} = 1;
        }
        elsif ( $_[0]->type == SDL_KEYUP ) {
            $pressed->{$name} = 0;
        }
        elsif( $_[0]->type == SDL_JOYAXISMOTION ) {
           #warn "- Joystick axis motion event structure: which axis: " . $_[0]->jaxis_axis . " value: " . $_[0]->jaxis_value;
           if( $_[0]->jaxis_axis == 3 and $_[0]->jaxis_value > 10000 ) {
               # right on the d-pad
               $pressed->{right} = 1;
           } elsif( $_[0]->jaxis_axis == 3 and $_[0]->jaxis_value < -10000 ) {
               $pressed->{left} = 1;
           } elsif( $_[0]->jaxis_axis == 3 and $_[0]->jaxis_value > -10000 and $_[0]->jaxis_value < 10000 ) {
               $pressed->{right} = 0;
               $pressed->{left} = 0;
           }
        } elsif( $_[0]->type == SDL_JOYBALLMOTION ) {
            #warn "- Joystick trackball motion event structure";
        } elsif( $_[0]->type == SDL_JOYHATMOTION ) {
            #warn " - Joystick hat position change event structure";
        } elsif( $_[0]->type == SDL_JOYBUTTONDOWN and $_[0]->jbutton_button == 2 ) {
            # button 2 is B, button 1 is A
            # warn " - Joystick button event structure: button down: button ". $_[0]->jbutton_button;
            $pressed->{up} = 1;
        } elsif( $_[0]->type == SDL_JOYBUTTONUP and $_[0]->jbutton_button == 2 ) {
            # warn " - Joystick button event structure: button up: button ". $_[0]->jbutton_button;
            $pressed->{up} = 0;
        }
    }
);

$app->add_show_handler(
    sub {
        $app->draw_rect( [ 0, 0, $app->w, $app->h ], 0x0 );
        $app->draw_rect( [ @$_, $block_width, $block_height ], 0xFF0000FF ) foreach @blocks; # XXX

        SDL::GFX::Primitives::string_color( $app, $app->w/2-100, 0, $dashboard, 0xFF0000FF); # XXX debug
        SDL::GFX::Primitives::string_color(
            $app,
            $app->w / 2 - 100,
            $app->h / 2,
            "Mario is DEAD", 0xFF0000FF
        ) if $quit;

    }
);

#
# render objects
#

$obj->attach( $app, sub {

    my $state = shift;
    my $c_rect = SDL::Rect->new( $state->x, $state->y, 16, 28 );
    $sprite->x( $state->x );
    $sprite->y( $state->y );
    $sprite->draw($app->surface);
    #$app->draw_rect( [  $state->x, $state->y, 16, 28   ], 0xFF00FFFF );

} );

$app->add_show_handler( sub { $app->update(); } );

$app->run();

sub check_collision {
    my ( $mario, $blocks ) = @_;

    my @collisions = ();

    foreach (@$blocks) {
        my $hash = {
            x  => $mario->x,
            y  => $mario->y,
            w  => $w,
            h  => $h,
            xv => $mario->v_x * 0.02,
            yv => $mario->v_y * 0.02
        };
        my $rect  = hash2rect($hash);
        my $bhash = { x => $_->[0], y => $_->[1], w => $w, h => $block_height };
        my $block = hash2rect($bhash);
        my $c = dynamic_collision( $rect, $block, interval => 1, keep_order => 1 );
        if ($c) {

            my $axis = $c->axis() || 'y';

            return [ $axis, $_ ];

        }

    }

    return -1;

}

__END__

; NonMaskableInterrupt->OperModeExecutionTree-> 
; GameMode->GameCoreRoutine->GameRoutines->PlayerCtrlRoutine->PlayerMovementSubs
;                        |-->GameEngine


PlayerCtrlRoutine:
; ...
SaveJoyp:   lda SavedJoypadBits         ;otherwise store A and B buttons in $0a
            and #%11000000
            sta A_B_Buttons
            lda SavedJoypadBits         ;store left and right buttons in $0c
            and #%00000011
            sta Left_Right_Buttons
            lda SavedJoypadBits         ;store up and down buttons in $0b
            and #%00001100
            sta Up_Down_Buttons
            and #%00000100              ;check for pressing down
            beq SizeChk                 ;if not, branch
            lda Player_State            ;check player's state
            bne SizeChk                 ;if not on the ground, branch
            ldy Left_Right_Buttons      ;check left and right
            beq SizeChk                 ;if neither pressed, branch
            lda #$00
            sta Left_Right_Buttons      ;if pressing down while on the ground,
            sta Up_Down_Buttons         ;nullify directional bits
SizeChk:    jsr PlayerMovementSubs      ;run movement subroutines
            ldy #$01                    ;is player small?
            lda PlayerSize
            bne ChkMoveDir
            ldy #$00                    ;check for if crouching
            lda CrouchingFlag
            beq ChkMoveDir              ;if not, branch ahead
            ldy #$02                    ;if big and crouching, load y with 2
ChkMoveDir: sty Player_BoundBoxCtrl     ;set contents of Y as player's bounding box size control
            lda #$01                    ;set moving direction to right by default
            ldy Player_X_Speed          ;check player's horizontal speed
            beq PlayerSubs              ;if not moving at all horizontally, skip this part
            bpl SetMoveDir              ;if moving to the right, use default moving direction
            asl                         ;otherwise change to move to the left
SetMoveDir: sta Player_MovingDir        ;set moving direction
PlayerSubs: jsr ScrollHandler           ;move the screen if necessary
            jsr GetPlayerOffscreenBits  ;get player's offscreen bits
            jsr RelativePlayerPosition  ;get coordinates relative to the screen
            ldx #$00                    ;set offset for player object
            jsr BoundingBoxCore         ;get player's bounding box coordinates
            jsr PlayerBGCollision       ;do collision detection and process
            lda Player_Y_Position
            cmp #$40                    ;check to see if player is higher than 64th pixel
            bcc PlayerHole              ;if so, branch ahead
            lda GameEngineSubroutine
            cmp #$05                    ;if running end-of-level routine, branch ahead
            beq PlayerHole
            cmp #$07                    ;if running player entrance routine, branch ahead
            beq PlayerHole
            cmp #$04                    ;if running routines $00-$03, branch ahead
            bcc PlayerHole
            lda Player_SprAttrib
            and #%11011111              ;otherwise nullify player's
            sta Player_SprAttrib        ;background priority flag
PlayerHole: lda Player_Y_HighPos        ;check player's vertical high byte
            cmp #$02                    ;for below the screen
            bmi ExitCtrl                ;branch to leave if not that far down
            ldx #$01
            stx ScrollLock              ;set scroll lock
            ldy #$04
            sty $07                     ;set value here
            ldx #$00                    ;use X as flag, and clear for cloud level
            ldy GameTimerExpiredFlag    ;check game timer expiration flag
            bne HoleDie                 ;if set, branch
            ldy CloudTypeOverride       ;check for cloud type override
            bne ChkHoleX                ;skip to last part if found
HoleDie:    inx                         ;set flag in X for player death
            ldy GameEngineSubroutine
            cpy #$0b                    ;check for some other routine running
            beq ChkHoleX                ;if so, branch ahead
            ldy DeathMusicLoaded        ;check value here
            bne HoleBottom              ;if already set, branch to next part
            iny
            sty EventMusicQueue         ;otherwise play death music
            sty DeathMusicLoaded        ;and set value here
HoleBottom: ldy #$06
            sty $07                     ;change value here
ChkHoleX:   cmp $07                     ;compare vertical high byte with value set here
            bmi ExitCtrl                ;if less, branch to leave
            dex                         ;otherwise decrement flag in X
            bmi CloudExit               ;if flag was clear, branch to set modes and other values
            ldy EventMusicBuffer        ;check to see if music is still playing
            bne ExitCtrl                ;branch to leave if so
            lda #$06                    ;otherwise set to run lose life routine
            sta GameEngineSubroutine    ;on next frame
ExitCtrl:   rts                         ;leave


PlayerMovementSubs:
           lda #$00                  ;set A to init crouch flag by default
           ldy PlayerSize            ;is player small?
           bne SetCrouch             ;if so, branch
           lda Player_State          ;check state of player
           bne ProcMove              ;if not on the ground, branch 
           lda Up_Down_Buttons       ;load controller bits for up and down
           and #%00000100            ;single out bit for down button 
SetCrouch: sta CrouchingFlag         ;store value in crouch flag
ProcMove:  jsr PlayerPhysicsSub      ;run sub related to jumping and swimming
           lda PlayerChangeSizeFlag  ;if growing/shrinking flag set, 
           bne NoMoveSub             ;branch to leave 
           lda Player_State
           cmp #$03                  ;get player state
           beq MoveSubs              ;if climbing, branch ahead, leave timer unset
           ldy #$18
           sty ClimbSideTimer        ;otherwise reset timer now
MoveSubs:  jsr JumpEngine

PlayerPhysicsSub:  
           lda Player_State          ;check player state
           cmp #$03
           bne CheckForJumping       ;if not climbing, branch
           ldy #$00
           lda Up_Down_Buttons       ;get controller bits for up/down
           and Player_CollisionBits  ;check against player's collision detection bits
           beq ProcClimb             ;if not pressing up or down, branch
           iny 
           and #%00001000            ;check for pressing up
           bne ProcClimb
           iny 
ProcClimb: ldx Climb_Y_MForceData,y  ;load value here
           stx Player_Y_MoveForce    ;store as vertical movement force
           lda #$08                  ;load default animation timing
           ldx Climb_Y_SpeedData,y   ;load some other value here
           stx Player_Y_Speed        ;store as vertical speed  
           bmi SetCAnim              ;if climbing down, use default animation timing value
           lsr                       ;otherwise divide timer setting by 2
SetCAnim:  sta PlayerAnimTimerSet    ;store animation timer setting and leave
           rts

CheckForJumping:
        lda JumpspringAnimCtrl    ;if jumpspring animating,
        bne NoJump                ;skip ahead to something else
        lda A_B_Buttons           ;check for A button press
        and #A_Button
        beq NoJump                ;if not, branch to something else
        and PreviousA_B_Buttons   ;if button not pressed in previous frame, branch
        beq ProcJumping
NoJump: jmp X_Physics             ;otherwise, jump to something else

ProcJumping:
           lda Player_State           ;check player state
           beq InitJS                 ;if on the ground, branch
           lda SwimmingFlag           ;if swimming flag not set, jump to do something else
           beq NoJump                 ;to prevent midair jumping, otherwise continue
           lda JumpSwimTimer          ;if jump/swim timer nonzero, branch
           bne InitJS
           lda Player_Y_Speed         ;check player's vertical speed
           bpl InitJS                 ;if player's vertical speed motionless or down, branch
           jmp X_Physics              ;if timer at zero and player still rising, do not swim
InitJS:    lda #$20                   ;set jump/swim timer
           sta JumpSwimTimer
           ldy #$00                   ;initialize vertical force and dummy variable
           sty Player_YMF_Dummy
           sty Player_Y_MoveForce
           lda Player_Y_HighPos       ;get vertical high and low bytes of jump origin
           sta JumpOrigin_Y_HighPos   ;and store them next to each other here
           lda Player_Y_Position
           sta JumpOrigin_Y_Position
           lda #$01                   ;set player state to jumping/swimming
           sta Player_State
           lda Player_XSpeedAbsolute  ;check value related to walking/running speed
           cmp #$09
           bcc ChkWtr                 ;branch if below certain values, increment Y
           iny                        ;for each amount equal or exceeded
           cmp #$10
           bcc ChkWtr
           iny
ChkWtr:    lda #$01                   ;set value here (apparently always set to 1)
           sta DiffToHaltJump
           lda SwimmingFlag           ;if swimming flag disabled, branch
           beq GetYPhy
           ldy #$05                   ;otherwise set Y to 5, range is 5-6
           lda Whirlpool_Flag         ;if whirlpool flag not set, branch
           beq GetYPhy
           iny                        ;otherwise increment to 6
GetYPhy:   lda JumpMForceData,y       ;store appropriate jump/swim
           sta VerticalForce          ;data here
           lda FallMForceData,y
           sta VerticalForceDown
           lda InitMForceData,y
           sta Player_Y_MoveForce
           lda PlayerYSpdData,y
           sta Player_Y_Speed
           lda SwimmingFlag           ;if swimming flag disabled, branch
           beq PJumpSnd
           lda #Sfx_EnemyStomp        ;load swim/goomba stomp sound into
           sta Square1SoundQueue      ;square 1's sfx queue
           lda Player_Y_Position
           cmp #$14                   ;check vertical low byte of player position
           bcs X_Physics              ;if below a certain point, branch
           lda #$00                   ;otherwise reset player's vertical speed
           sta Player_Y_Speed         ;and jump to something else to keep player
           jmp X_Physics              ;from swimming above water level
PJumpSnd:  lda #Sfx_BigJump           ;load big mario's jump sound by default
           ldy PlayerSize             ;is mario big?
           beq SJumpSnd
           lda #Sfx_SmallJump         ;if not, load small mario's jump sound
SJumpSnd:  sta Square1SoundQueue      ;store appropriate jump sound in square 1 sfx queue
X_Physics: ldy #$00
           sty $00                    ;init value here
           lda Player_State           ;if mario is on the ground, branch
           beq ProcPRun
           lda Player_XSpeedAbsolute  ;check something that seems to be related
           cmp #$19                   ;to mario's speed
           bcs GetXPhy                ;if =>$19 branch here
           bcc ChkRFast               ;if not branch elsewhere
ProcPRun:  iny                        ;if mario on the ground, increment Y
           lda AreaType               ;check area type
           beq ChkRFast               ;if water type, branch
           dey                        ;decrement Y by default for non-water type area
           lda Left_Right_Buttons     ;get left/right controller bits
           cmp Player_MovingDir       ;check against moving direction
           bne ChkRFast               ;if controller bits <> moving direction, skip this part
           lda A_B_Buttons            ;check for b button pressed
           and #B_Button
           bne SetRTmr                ;if pressed, skip ahead to set timer
           lda RunningTimer           ;check for running timer set
           bne GetXPhy                ;if set, branch
ChkRFast:  iny                        ;if running timer not set or level type is water,
           inc $00                    ;increment Y again and temp variable in memory
           lda RunningSpeed
           bne FastXSp                ;if running speed set here, branch
           lda Player_XSpeedAbsolute
           cmp #$21                   ;otherwise check player's walking/running speed
           bcc GetXPhy                ;if less than a certain amount, branch ahead
FastXSp:   inc $00                    ;if running speed set or speed => $21 increment $00
           jmp GetXPhy                ;and jump ahead
SetRTmr:   lda #$0a                   ;if b button pressed, set running timer
           sta RunningTimer
GetXPhy:   lda MaxLeftXSpdData,y      ;get maximum speed to the left
           sta MaximumLeftSpeed
           lda GameEngineSubroutine   ;check for specific routine running
           cmp #$07                   ;(player entrance)
           bne GetXPhy2               ;if not running, skip and use old value of Y
           ldy #$03                   ;otherwise set Y to 3
GetXPhy2:  lda MaxRightXSpdData,y     ;get maximum speed to the right
           sta MaximumRightSpeed
           ldy $00                    ;get other value in memory
           lda FrictionData,y         ;get value using value in memory as offset
           sta FrictionAdderLow
           lda #$00
           sta FrictionAdderHigh      ;init something here
           lda PlayerFacingDir
           cmp Player_MovingDir       ;check facing direction against moving direction
           beq ExitPhy                ;if the same, branch to leave
           asl FrictionAdderLow       ;otherwise shift d7 of friction adder low into carry
           rol FrictionAdderHigh      ;then rotate carry onto d0 of friction adder high
ExitPhy:   rts                        ;and then leave

GetPlayerAnimSpeed:
            ldy #$00                   ;initialize offset in Y
            lda Player_XSpeedAbsolute  ;check player's walking/running speed
            cmp #$1c                   ;against preset amount
            bcs SetRunSpd              ;if greater than a certain amount, branch ahead
            iny                        ;otherwise increment Y
            cmp #$0e                   ;compare against lower amount
            bcs ChkSkid                ;if greater than this but not greater than first, skip increment
            iny                        ;otherwise increment Y again
ChkSkid:    lda SavedJoypadBits        ;get controller bits
            and #%01111111             ;mask out A button
            beq SetAnimSpd             ;if no other buttons pressed, branch ahead of all this
            and #$03                   ;mask out all others except left and right
            cmp Player_MovingDir       ;check against moving direction
            bne ProcSkid               ;if left/right controller bits <> moving direction, branch
            lda #$00                   ;otherwise set zero value here
SetRunSpd:  sta RunningSpeed           ;store zero or running speed here
            jmp SetAnimSpd
ProcSkid:   lda Player_XSpeedAbsolute  ;check player's walking/running speed
            cmp #$0b                   ;against one last amount
            bcs SetAnimSpd             ;if greater than this amount, branch
            lda PlayerFacingDir
            sta Player_MovingDir       ;otherwise use facing direction to set moving direction
            lda #$00
            sta Player_X_Speed         ;nullify player's horizontal speed
            sta Player_X_MoveForce     ;and dummy variable for player
SetAnimSpd: lda PlayerAnimTmrData,y    ;get animation timer setting using Y as offset
            sta PlayerAnimTimerSet
            rts


ImposeFriction:
           and Player_CollisionBits  ;perform AND between left/right controller bits and collision flag
           cmp #$00                  ;then compare to zero (this instruction is redundant)
           bne JoypFrict             ;if any bits set, branch to next part
           lda Player_X_Speed
           beq SetAbsSpd             ;if player has no horizontal speed, branch ahead to last part
           bpl RghtFrict             ;if player moving to the right, branch to slow
           bmi LeftFrict             ;otherwise logic dictates player moving left, branch to slow
JoypFrict: lsr                       ;put right controller bit into carry
           bcc RghtFrict             ;if left button pressed, carry = 0, thus branch
LeftFrict: lda Player_X_MoveForce    ;load value set here
           clc
           adc FrictionAdderLow      ;add to it another value set here
           sta Player_X_MoveForce    ;store here
           lda Player_X_Speed
           adc FrictionAdderHigh     ;add value plus carry to horizontal speed
           sta Player_X_Speed        ;set as new horizontal speed
           cmp MaximumRightSpeed     ;compare against maximum value for right movement
           bmi XSpdSign              ;if horizontal speed greater negatively, branch
           lda MaximumRightSpeed     ;otherwise set preset value as horizontal speed
           sta Player_X_Speed        ;thus slowing the player's left movement down
           jmp SetAbsSpd             ;skip to the end
RghtFrict: lda Player_X_MoveForce    ;load value set here
           sec
           sbc FrictionAdderLow      ;subtract from it another value set here
           sta Player_X_MoveForce    ;store here
           lda Player_X_Speed
           sbc FrictionAdderHigh     ;subtract value plus borrow from horizontal speed
           sta Player_X_Speed        ;set as new horizontal speed
           cmp MaximumLeftSpeed      ;compare against maximum value for left movement
           bpl XSpdSign              ;if horizontal speed greater positively, branch
           lda MaximumLeftSpeed      ;otherwise set preset value as horizontal speed
           sta Player_X_Speed        ;thus slowing the player's right movement down
XSpdSign:  cmp #$00                  ;if player not moving or moving to the right,
           bpl SetAbsSpd             ;branch and leave horizontal speed value unmodified
           eor #$ff
           clc                       ;otherwise get two's compliment to get absolute
           adc #$01                  ;unsigned walking/running speed
SetAbsSpd: sta Player_XSpeedAbsolute ;store walking/running speed here and leave
           rts

JumpSwimSub:
          ldy Player_Y_Speed         ;if player's vertical speed zero
          bpl DumpFall               ;or moving downwards, branch to falling
          lda A_B_Buttons
          and #A_Button              ;check to see if A button is being pressed
          and PreviousA_B_Buttons    ;and was pressed in previous frame
          bne ProcSwim               ;if so, branch elsewhere
          lda JumpOrigin_Y_Position  ;get vertical position player jumped from
          sec
          sbc Player_Y_Position      ;subtract current from original vertical coordinate
          cmp DiffToHaltJump         ;compare to value set here to see if player is in mid-jump
          bcc ProcSwim               ;or just starting to jump, if just starting, skip ahead
DumpFall: lda VerticalForceDown      ;otherwise dump falling into main fractional
          sta VerticalForce
ProcSwim: lda SwimmingFlag           ;if swimming flag not set,
          beq LRAir                  ;branch ahead to last part
          jsr GetPlayerAnimSpeed     ;do a sub to get animation frame timing
          lda Player_Y_Position
          cmp #$14                   ;check vertical position against preset value
          bcs LRWater                ;if not yet reached a certain position, branch ahead
          lda #$18
          sta VerticalForce          ;otherwise set fractional
LRWater:  lda Left_Right_Buttons     ;check left/right controller bits (check for swimming)
          beq LRAir                  ;if not pressing any, skip
          sta PlayerFacingDir        ;otherwise set facing direction accordingly
LRAir:    lda Left_Right_Buttons     ;check left/right controller bits (check for jumping/falling)
          beq JSMove                 ;if not pressing any, skip
          jsr ImposeFriction         ;otherwise process horizontal movement
JSMove:   jsr MovePlayerHorizontally ;do a sub to move player horizontally
          sta Player_X_Scroll        ;set player's speed here, to be used for scroll later
          lda GameEngineSubroutine
          cmp #$0b                   ;check for specific routine selected
          bne ExitMov1               ;branch if not set to run
          lda #$28
          sta VerticalForce          ;otherwise set fractional
ExitMov1: jmp MovePlayerVertically   ;jump to move player vertically, then leave


JumpMForceData:
      .db $20, $20, $1e, $28, $28, $0d, $04

FallMForceData:
      .db $70, $70, $60, $90, $90, $0a, $09

PlayerYSpdData:
      .db $fc, $fc, $fc, $fb, $fb, $fe, $ff

InitMForceData:
      .db $00, $00, $00, $00, $00, $80, $00

MaxLeftXSpdData:
      .db $d8, $e8, $f0

MaxRightXSpdData:
      .db $28, $18, $10
      .db $0c ;used for pipe intros

FrictionData:
      .db $e4, $98, $d0

Climb_Y_SpeedData:
      .db $00, $ff, $01

Climb_Y_MForceData:
      .db $00, $20, $ff


MoveEnemyHorizontally:
      inx                         ;increment offset for enemy offset
      jsr MoveObjectHorizontally  ;position object horizontally according to
      ldx ObjectOffset            ;counters, return with saved value in A,
      rts                         ;put enemy offset back in X and leave

MovePlayerHorizontally:
      lda JumpspringAnimCtrl  ;if jumpspring currently animating,
      bne ExXMove             ;branch to leave
      tax                     ;otherwise set zero for offset to use player's stuff

MoveObjectHorizontally:
          lda SprObject_X_Speed,x     ;get currently saved value (horizontal
          asl                         ;speed, secondary counter, whatever)
          asl                         ;and move low nybble to high
          asl
          asl
          sta $01                     ;store result here
          lda SprObject_X_Speed,x     ;get saved value again
          lsr                         ;move high nybble to low
          lsr
          lsr
          lsr
          cmp #$08                    ;if < 8, branch, do not change
          bcc SaveXSpd
          ora #%11110000              ;otherwise alter high nybble
SaveXSpd: sta $00                     ;save result here
          ldy #$00                    ;load default Y value here
          cmp #$00                    ;if result positive, leave Y alone
          bpl UseAdder
          dey                         ;otherwise decrement Y
UseAdder: sty $02                     ;save Y here
          lda SprObject_X_MoveForce,x ;get whatever number's here
          clc
          adc $01                     ;add low nybble moved to high
          sta SprObject_X_MoveForce,x ;store result here
          lda #$00                    ;init A
          rol                         ;rotate carry into d0
          pha                         ;push onto stack
          ror                         ;rotate d0 back onto carry
          lda SprObject_X_Position,x
          adc $00                     ;add carry plus saved value (high nybble moved to low
          sta SprObject_X_Position,x  ;plus $f0 if necessary) to object's horizontal position
          lda SprObject_PageLoc,x
          adc $02                     ;add carry plus other saved value to the
          sta SprObject_PageLoc,x     ;object's page location and save
          pla
          clc                         ;pull old carry from stack and add
          adc $00                     ;to high nybble moved to low
ExXMove:  rts                         ;and leave

;-------------------------------------------------------------------------------------
;$00 - used for downward force
;$01 - used for upward force
;$02 - used for maximum vertical speed

MovePlayerVertically:
         ldx #$00                ;set X for player offset
         lda TimerControl
         bne NoJSChk             ;if master timer control set, branch ahead
         lda JumpspringAnimCtrl  ;otherwise check to see if jumpspring is animating
         bne ExXMove             ;branch to leave if so
NoJSChk: lda VerticalForce       ;dump vertical force 
         sta $00
         lda #$04                ;set maximum vertical speed here
         jmp ImposeGravitySprObj ;then jump to move player vertically

ImposeGravityBlock:
      ldy #$01       ;set offset for maximum speed
      lda #$50       ;set movement amount here
      sta $00
      lda MaxSpdBlockData,y    ;get maximum speed

ImposeGravitySprObj:
      sta $02            ;set maximum speed here
      lda #$00           ;set value to move downwards
      jmp ImposeGravity  ;jump to the code that actually moves it


;$00 - used for downward force
;$01 - used for upward force
;$07 - used as adder for vertical position

ImposeGravity:
         pha                          ;push value to stack
         lda SprObject_YMF_Dummy,x
         clc                          ;add value in movement force to contents of dummy variable
         adc SprObject_Y_MoveForce,x
         sta SprObject_YMF_Dummy,x
         ldy #$00                     ;set Y to zero by default
         lda SprObject_Y_Speed,x      ;get current vertical speed
         bpl AlterYP                  ;if currently moving downwards, do not decrement Y
         dey                          ;otherwise decrement Y
AlterYP: sty $07                      ;store Y here
         adc SprObject_Y_Position,x   ;add vertical position to vertical speed plus carry
         sta SprObject_Y_Position,x   ;store as new vertical position
         lda SprObject_Y_HighPos,x
         adc $07                      ;add carry plus contents of $07 to vertical high byte
         sta SprObject_Y_HighPos,x    ;store as new vertical high byte
         lda SprObject_Y_MoveForce,x
         clc
         adc $00                      ;add downward movement amount to contents of $0433
         sta SprObject_Y_MoveForce,x
         lda SprObject_Y_Speed,x      ;add carry to vertical speed and store
         adc #$00
         sta SprObject_Y_Speed,x
         cmp $02                      ;compare to maximum speed
         bmi ChkUpM                   ;if less than preset value, skip this part
         lda SprObject_Y_MoveForce,x
         cmp #$80                     ;if less positively than preset maximum, skip this part
         bcc ChkUpM
         lda $02
         sta SprObject_Y_Speed,x      ;keep vertical speed within maximum value
         lda #$00
         sta SprObject_Y_MoveForce,x  ;clear fractional
ChkUpM:  pla                          ;get value from stack
         beq ExVMove                  ;if set to zero, branch to leave
         lda $02
         eor #%11111111               ;otherwise get two's compliment of maximum speed
         tay
         iny
         sty $07                      ;store two's compliment here
         lda SprObject_Y_MoveForce,x
         sec                          ;subtract upward movement amount from contents
         sbc $01                      ;of movement force, note that $01 is twice as large as $00,
         sta SprObject_Y_MoveForce,x  ;thus it effectively undoes add we did earlier
         lda SprObject_Y_Speed,x
         sbc #$00                     ;subtract borrow from vertical speed and store
         sta SprObject_Y_Speed,x
         cmp $07                      ;compare vertical speed to two's compliment
         bpl ExVMove                  ;if less negatively than preset maximum, skip this part
         lda SprObject_Y_MoveForce,x
         cmp #$80                     ;check if fractional part is above certain amount,
         bcs ExVMove                  ;and if so, branch to leave
         lda $07
         sta SprObject_Y_Speed,x      ;keep vertical speed within maximum value
         lda #$ff
         sta SprObject_Y_MoveForce,x  ;clear fractional
ExVMove: rts                          ;leave!

