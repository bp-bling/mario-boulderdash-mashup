use strict;
use warnings;

=for comment

TODO:

o. portals!
o. win condition
o. pushing single boulders
o. should be able to jump up to under rocks
o. FSA enemies!  turtles?  ugh, the whole shell bounce thing.  goombas?
o. mario/enemy collision logic
o. mario stomping on stuff?
o. Player_Draw
o. Player_CommonGroundAnims
o. Player_DoSpecialTiles
o. Player_DoGameplay -- stole a few tidbits from it but should copy the whole routine
o. barrels and ladders from the original Mario Brothers?  resurrect vine logic?
o. could make good use of water tiles if we pulled in the needed code; puzzles could involve filling chimneys with water
o. use SMB3 mario draw routines so that he's doing the right frames and animations

TILES:

../background.gif
../javascript-boulderdash/images/sprites.png

LEVELS:

o. dirt maze that's one big elaborate shape
o. sand pushing mario up a chimney
o. trying to navigate dirt and boulders
o. dropping boulders on enemies

=cut

use SDL;
use SDL::Rect;
use SDL::Events;
use SDL::Image;
use Math::Trig;
use Data::Dumper;
use SDLx::App;
use SDLx::Controller::Interface;
use SDLx::Sprite::Animated;
use SDL::Joystick;
use PeekPoke 'peek', 'poke';
use B;
use B::Generate;

my $app = SDLx::App->new( w => 640, h => 480, dt => 0.02, title => 'Pario' );

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
    image           => 'mario.ppm',
    rect            => SDL::Rect->new( 0, 0, 16, 18 ),
    ticks_per_frame => 6,
    alpha_key       => SDL::Color->new(0, 255, 255),
);

$sprite->set_sequences(
    left  => [ [ 12, 1, ], [ 11, 1, ] ],
    right => [ [ 3, 0 ], [ 2, 0 ] ],
    stopl => [ [ 11, 1 ] ],
    stopr => [ [ 2, 0 ] ],
    jumpr => [ [ 5, 0 ] ],
    jumpl => [ [ 9, 1 ] ],
    duckr => [ [ 3, 0 ] ],
    duckl => [ [ 1, 1 ] ],
);

$sprite->sequence('stopr');
$sprite->start();

#

my $fireflysprite = SDLx::Sprite::Animated->new(
    image           => 'boulderdashsprites.png',
    rect            => SDL::Rect->new( 0, 0, 16, 16 ),
    ticks_per_frame => 6,
    # alpha_key       => SDL::Color->new(0, 255, 255), # XXX transparent in the png working?
);
$fireflysprite->set_sequences(
    firefly => [ [ 0, 9 ], [ 1, 9 ], [ 2, 9 ], [ 3, 9 ], [ 4, 9 ], [ 5, 9 ], [ 6, 9 ], [ 7, 9 ] ],
);
$fireflysprite->sequence('firefly');
$fireflysprite->start();

my $explodetospace = SDLx::Sprite::Animated->new(
    image           => 'boulderdashsprites.png',
    rect            => SDL::Rect->new( 0, 0, 16, 16 ),
    ticks_per_frame => 6,
);
$explodetospace->set_sequences(
    explodetospace => [ [ 4, 7 ], [ 5, 7 ], [ 4, 7 ], [ 3, 7 ] ],
);
$explodetospace->sequence('explodetospace');
$explodetospace->start();


#    explodetodiamond => [ [ 3, 7 ], [ 4, 7 ], [ 5, 7 ], [ 4, 7 ], [ 3, 7 ] ], # XXX

use constant { UP => 0, UPRIGHT => 1, RIGHT => 2, DOWNRIGHT => 3, DOWN => 4, DOWNLEFT => 5, LEFT => 6, UPLEFT => 7, };
my $DIRX = [     0,          1,        1,            1,            0,          -1,          -1,        -1 ];
my $DIRY = [    -1,         -1,        0,            1,            1,           1,           0,        -1 ];

my $FIREFLIES = [];
$FIREFLIES->[LEFT]  = 'F1'; # OBJECT.FIREFLY1
$FIREFLIES->[UP]    = 'F2'; # OBJECT.FIREFLY2;
$FIREFLIES->[RIGHT] = 'F3'; # OBJECT.FIREFLY3;
$FIREFLIES->[DOWN]  = 'F4'; # OBJECT.FIREFLY4;
 
# hacked up:

my $deadmario = SDL::Image::load( 'deadmario.gif' ) or die;

my $brick = SDL::Image::load( 'brick.gif' ) or die; # XXX combine with tile constants somehow
my $questionbox = SDL::Image::load( 'questionbox.gif' ) or die; # XXX combine with tile constants somehow
my $emptybox = SDL::Image::load( 'emptybox.gif' ) or die; # XXX combine with tile constants somehow
my $sand = SDL::Image::load( 'sand.gif' ) or die; # XXX combine with tile constants somehow
my $rock = SDL::Image::load( 'rock.gif' ) or die; # XXX combine with tile constants somehow
my $dirt = SDL::Image::load( 'dirt.gif' ) or die; # XXX combine with tile constants somehow
my $woodblock = SDL::Image::load( 'woodblock.gif' ) or die; # XXX combine with tile constants somehow

my $icon_lookup = {
   X => $brick,
   '?' => $questionbox,
   '.' => $emptybox,
   '#' => $sand,
   '=' => $sand,
   '*' => $rock,
   '@' => $rock,
   'D' => $dirt,
   'd' => $dirt,
   'W' => $woodblock,
   'w' => $woodblock,
   'M' => $emptybox, # XXX debug -- mario; shouldn't be left here unless we're trying to debug
};

my %tile_properties = (
    # solid bottom and solid sides are the same thing
    # XXX reconsile this with the TILE constants
    ' ' => { solid_top => 0, solid_bottom => 0, rounded => 1, explodable => 0, consumable => 1, diggable => 0, },
    'X' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 1, diggable => 0, }, # brick
    '?' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # questionbox
    '.' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # emptybox
    '#' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 1, diggable => 0, }, # sand
    '=' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 1, diggable => 0, }, # falling sand
    '*' => { solid_top => 1, solid_bottom => 1, rounded => 1, explodable => 0, consumable => 1, diggable => 0, }, # rock/boulder 
    '@' => { solid_top => 1, solid_bottom => 1, rounded => 0, explodable => 0, consumable => 1, diggable => 0, }, # rock/falling boulder
    'D' => { solid_top => 1, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 1, diggable => 1, }, # dirt
    'd' => { solid_top => 1, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 1, diggable => 1, }, # falling dirt
    'W' => { solid_top => 1, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 1, diggable => 1, }, # woodblock
    'w' => { solid_top => 1, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 1, diggable => 1, }, # falling woodblock
    'M' => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 1, diggable => 0, }, # XXX debug -- mario
    F1  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 1, consumable => 1, diggable => 0, }, # firefly
    F2  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 1, consumable => 1, diggable => 0, }, # firefly
    F3  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 1, consumable => 1, diggable => 0, }, # firefly
    F4  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 1, consumable => 1, diggable => 0, }, # firefly
    E1  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # explosion
    E2  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # explosion
    E3  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # explosion
    E4  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # explosion
    E5  => { solid_top => 0, solid_bottom => 0, rounded => 0, explodable => 0, consumable => 0, diggable => 0, }, # explosion
    # EXPLODETODIAMOND0: { code: 0x20, rounded: false, explodable: false, consumable: false, sprite: { x: 3, y: 7                 } },
    # EXPLODETODIAMOND1: { code: 0x21, rounded: false, explodable: false, consumable: false, sprite: { x: 4, y: 7                 } },
    # EXPLODETODIAMOND2: { code: 0x22, rounded: false, explodable: false, consumable: false, sprite: { x: 5, y: 7                 } },
    # EXPLODETODIAMOND3: { code: 0x23, rounded: false, explodable: false, consumable: false, sprite: { x: 4, y: 7                 } },
    # EXPLODETODIAMOND4: { code: 0x24, rounded: false, explodable: false, consumable: false, sprite: { x: 3, y: 7                 } },

);


my $obj = SDLx::Controller::Interface->new( x => 10, y => 380, v_x => 0, v_y => 0 );

#
#
#

my @enemes;

#
#
#

my $map;  # ->[$x]->[$y]
my $map_max_x = 0;
my $map_max_y = 0;

do {
    my $fn = 'level1.txt';
    $fn = shift @ARGV if @ARGV;
    $fn .= '.txt' unless $fn =~ m/\.txt$/;
    open my $fh, '<', $fn or die "$fn: $!";
    my $y = 0;
    while( my $line = readline $fh ) {
        chomp $line;
        my @line = split m//, $line;
        for my $x ( 0 .. $#line ) {
            $map->[$x]->[$y] = $line[$x];
            $map->[$x]->[$y] .= '1' if ! exists $tile_properties{ $map->[$x]->[$y] }; # deal with things like A1, A2, A3, A4 all being keyed off 'A' in the map .txt
            $map_max_x = $x if $x > $map_max_x;
        }
        $y++; 
    }
    $map_max_y = $y;
};

sub map_x_y {
    my $x = shift;
    my $y = shift;
    return $map->[$x]->[$y] || ' ';
}

my $a = 0;
my $x = 0;
my $y = 0;
my $carry = 0;
my @stack;

my $PLAYER_TOPRUNSPEED    = 0x28;         # Highest X velocity when Player runs
my $PLAYER_TOPPOWERSPEED  = 0x38;         # Highest X velocity hit when Player is at full "power"
my $PLAYER_JUMP           = - 0x38;       # Player's root Y velocity for jumping (further adjusted a bit by Player_SpeedJumpInc)
my $PLAYER_MAXSPEED       = 0x40;         # Player's maximum speed

# Player_Suit -- Player's active powerup (see also: Player_QueueSuit)
my $PLAYERSUIT_SMALL    = 0; 
my $PLAYERSUIT_BIG      = 1;
my $PLAYERSUIT_FIRE     = 2;
my $PLAYERSUIT_RACCOON  = 3; 
my $PLAYERSUIT_FROG     = 4;
my $PLAYERSUIT_TANOOKI  = 5;
my $PLAYERSUIT_HAMMER   = 6;
my $PLAYERSUIT_SUPERSUITBEGIN = $PLAYERSUIT_FROG ;  # Marker for when "Super Suits" begin
my $PLAYERSUIT_LAST     = $PLAYERSUIT_HAMMER ; 
my $PLAYER_FLY_YVEL       = - 0x18;  # The Y velocity the Player flies at
my $PLAYER_TAILWAG_YVEL    = 0x10;  # The Y velocity that the tail wag attempts to lock you at

my $PF_JUMPFALLSMALL   = 0x40;   # Standard jump/fall frame when small
my $PF_FASTJUMPFALLSMALL       = 0x4E;  # "Fast" jump/fall frame when small

my $PAD_A       = 0x80;  # bit 7; BIT puts this bit into N 
my $PAD_B       = 0x40;  # bit 6; BIT puts this bit into V
my $PAD_SELECT  = 0x20;                  
my $PAD_START   = 0x10;
my $PAD_UP      = 0x08;
my $PAD_DOWN    = 0x04;
my $PAD_LEFT    = 0x02;
my $PAD_RIGHT   = 0x01;

my $FALLRATE_MAX          = 0x40;         # Maximum Y velocity falling rate

my $Player_XAccelMain = [
    # This is the main value of X acceleration applied
    # F = "Friction" (stopping rate), "N = "Normal" accel, S = "Skid" accel, X = unused
    # Without B button  With B button  
    #      F   N   S   X     F   N   S   X
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Small
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Big
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Fire
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Leaf
          -1,  2,  2,  0,   -1,  2,  2,  0,  # Frog
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Tanooki
          -1,  0,  2,  0,   -1,  0,  2,  0,  # Hammer
];

# Table of values that have to do with Player_UphillSpeedIdx override
my $Player_UphillSpeedVals = [
    0x00, 0x16, 0x15, 0x14, 0x13, 0x12, 0x11, 0x10, 0x0F, 0x0E, 0x0D,
];

my $Player_XAccelPseudoFrac =  [
    # F = "Friction" (stopping rate), "N = "Normal" accel, S = "Skid" accel, X = unused
    # Without B button      With B button
    #         F     N     S     X       F     N     S     X
           0x60, 0xE0, 0x00, 0x00,   0x60, 0xE0, 0x00, 0x00,  # Small
           0x20, 0xE0, 0x00, 0x00,   0x20, 0xE0, 0x00, 0x00,  # Big
           0x20, 0xE0, 0x00, 0x00,   0x20, 0xE0, 0x00, 0x00,  # Fire
           0x20, 0xE0, 0x00, 0x00,   0x20, 0xE0, 0x00, 0x00,  # Leaf
           0x00, 0x00, 0x00, 0x00,   0x00, 0x00, 0x00, 0x00,  # Frog
           0x60, 0xE0, 0x00, 0x00,   0x60, 0xE0, 0x00, 0x00,  # Tanooki
           0x60, 0xE0, 0x00, 0x00,   0x60, 0xE0, 0x00, 0x00,  # Hammer
];

# This table grants a couple (dis)abilities to certain^M
# power-ups; specifically:^M
# Bit 0 (1) = Able to fly and flutter (Raccoon tail wagging)^M
# Bit 1 (2) = NOT able to slide on slopes^M
my $PowerUp_Ability = [
    #   Small,    Big, Fire,   Leaf,  Frog, Tanooki,    Hammer
         0x00,   0x00,  0x00,  0x01,  0x02,    0x01,     0x02,
];

# Based on how fast Player is running, the jump is
# increased just a little (this is subtracted, thus
# for the negative Y velocity, it's "more negative")
my $Player_SpeedJumpInc = [    0x00, 0x02, 0x04, 0x08 ];

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#; Player_JumpFlyFlutter
#;
#; Controls the acts of jumping, flying, and fluttering (tail wagging)
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
my $PRG008_AC22 = [ # XXX give this a better name
     0xD0, 0xCE, 0xCC, 0xCA, 0xCA, 0xCA
];

my $Level_Tile_Head        = 0;    # Tile at Player's head
my $Level_Tile_GndL        = 0;    # Tile at Player's feet left
my $Level_Tile_GndR        = 0;    # Tile at Player's feet right
my $Level_Tile_InFL        = 0;    # Tile "in front" of Player ("lower", at feet)
my $Level_Tile_InFU        = 0;    # Tile "in front" of Player ("upper", at face)
# Level_Tile_Array, except for $Level_Tile_Head, has things the positions in the same order as $TileAttrAndQuad_OffsFlat.  A loop loops over those and this at the same time, calling Player_GetTileAndSlope() with those offsets to populate these variables
my $Level_Tile_Array = [ \$Level_Tile_Head, \$Level_Tile_GndL, \$Level_Tile_GndR, \$Level_Tile_InFL, \$Level_Tile_InFU, ]; # sdw: using this instead for calls like this:  LDA Level_Tile_Head,X
# my $Level_Tile_Quad = [ 0, 0, 0, 0 ];  # $0608-$060B Quadrant of tile for each of the positions above XXX; not sure I'm using quadrants to do tile attributes; okay, not using quadrants to do tile attributes
my $Level_Tile_Positions = [];           # hacked up; X, Y coordinates of where observed blocks are

#    ; Offsets used for tile detection in non-sloped levels
#    ; +16 if moving downward
#    ; +8 if on the right half of the tile
my $TileAttrAndQuad_OffsFlat = [
    #     Yoff Xoff

    # Not small or ducking moving downward - Left half
    0x20, 0x04,    # Ground left
    0x20, 0x0B,    # Ground right
    0x1B, 0x0E,    # In-front lower
    0x0E, 0x0E,    # In-front upper

    # Not small or ducking moving downward - Right half
    0x20, 0x04,    # Ground left
    0x20, 0x0B,    # Ground right
    0x1B, 0x01,    # In-front lower
    0x0E, 0x01,    # In-front upper

    # Not small or ducking moving upward - Left half
    0x06, 0x08,    # Ground left
    0x06, 0x08,    # Ground right
    0x1B, 0x0E,    # In-front lower
    0x0E, 0x0E,    # In-front upper

    # Not small or ducking moving upward - Right half
    0x06, 0x08,    # Ground left
    0x06, 0x08,    # Ground right
    0x1B, 0x01,    # In-front lower
    0x0E, 0x01,    # In-front upper

    # my 0xTileAttrAndQuad_OffsFlat_Sm =...

    # Small or ducking moving downward - Left half
    0x20, 0x04,    # Ground left
    0x20, 0x0B,    # Ground right
    0x1B, 0x0D,    # In-front lower
    0x14, 0x0D,    # In-front upper

    # Small or ducking moving downward - Right half
    0x20, 0x04,    # Ground left
    0x20, 0x0B,    # Ground right
    0x1B, 0x02,    # In-front lower
    0x14, 0x02,    # In-front upper

    # Small or ducking moving upward - Left half
    0x10, 0x08,    # Ground left
    0x10, 0x08,    # Ground right
    0x1B, 0x0D,    # In-front lower
    0x14, 0x0D,    # In-front upper

    # Small or ducking moving upward - Right half
    0x10, 0x08,    # Ground left
    0x10, 0x08,    # Ground right
    0x1B, 0x02,    # In-front lower
    0x14, 0x02,    # In-front upper
];

my $PRG008_B3AC = [ # XXX give this a better name
    0x02, 0x0E,  # Left/Right half, not small 
    0x03, 0x0D,  # Left/Right half, small
];

my $Read_Joypads_UnkTable = [ 0x00, 0x01, 0x02, 0x00, 0x04, 0x05, 0x06, 0x04, 0x08, 0x09, 0x0A, 0x08, 0x00, 0x01, 0x02, 0x00 ];

my $pressed                = {};      # some combination of left/right/up/down
#my $lockjump               = 0;       # has jumped, hasn't hit the ground yet
my $quit                   = 0;
my $dashboard              = '';      # debug message to display on-screen
my $w                      = 16;      # mario width
my $h                      = 28;      # mario height (but not necessarily block height, which is/was 20)
my $block_height           = 20;
#my $block_width            = 20;
#my $scroller               = 0;       # movement backlogged to recenter the screen

my $Counter_1              = 0;       # This value simply increments every frame, used for timing various things
my $Counter_Wiggly         = 0;      # "Wiggly" counter, provides rippled movement (like the airship rising durin g its intro)

my $Player_InAir           = 0;      # When set, Player is in the air
my $Player_InAir_OLD       = 0;
my $Player_Slide           = 0;      # Positive values sliding forward, negative values sliding backward; directly sets Player_XVel
my $Player_Kuribo          = 0;      # Set for Kuribo's Shoe active
my $Player_KuriboDir       = 0;      # While Kuribo's shoe is moving: 0 - Not requesting move, 1 - move right, 2 - move left
my $Player_RunFlag         = 0;      # Set while Player is actually considered "running" (holding down B and at enough speed; doesn't persist)
my $Player_Power           = 0;      # >>>>>>[P] charge level ($7F max)
my $Player_Slippery        = 0;      # 0 = Ground is not slippery, 1 = Ground is a little slippery, 2 = Ground is REALLY slippery
my $Player_MoveLR          = 0;      # 0 - Not moving left/right, 1 - Moving left, 2 - Moving right (reversed from the pad input)
my $Player_FlipBits        = 0;      # Set to $00 for Player to face left, Set to $40 for Player to face right;
my $Player_FlipBits_OLD    = 0;
my $Player_EndLevel        = 0;
my $Player_VibeDisable     = 0;      # While greater than zero, Player is unable to move (from impact of heavy fellow)
my $Player_Suit            = 0;      # Player's active powerup (see also: Player_QueueSuit)
my $Player_InWater         = 0;      # Set for when in water (1 = Regular water specifically, other non-zero values indicate waterfall)
my $Player_IsDucking       = 0;      # Set when Player is ducking down
my $Player_SlideRate:      = 0;      # While Player is sliding, this is added to X Velocity (does not persist, however)
my $Player_SwimCnt         = 0;      # Swim counter FIXME Describe better 0-3
my $Player_AllowAirJump:   = 0;      # Counts down to zero, but while set, you can jump in the air
my $Player_FlyTime         = 0;      # When > 0, Player can fly (for power ups that do so); decrements (unless $FF) to 0
my $Player_Frame           = 0;      # Player display frame
my $Player_StarInv         = 0;      # Starman Invincibility counter; full/fatal invincibility, counts down to zero
my $Player_RootJumpVel     = $PLAYER_JUMP;
my $Player_mGoomba         = 0;      # Player is caught by a micro Goomba (jump short)
my $Player_WagCount        = 0;      # after wagging raccoon tail, until this hits zero, holding 'A' keeps your fall rate low
my $Player_UphillFlag      = 0;      # When set, Player is walking uphill, and uses speed index value at Player_UphillSpeedIdx
my $Player_UphillSpeedIdx  = 0;      # Override when Player_UphillFlag is set (shared with Player_Microgoomba)
my $Player_XVelAdj         = 0;      # Applies additional value to the X Velocity
my $Player_XVel            = 0;      # Player's X Velocity (negative values to the left) (max value is $38)
my $Player_YVel            = 0;      # Player's Y Velocity (negative values upward)
my $Player_X               = 50<<4;      # XXX initialize to something else    XXX contains the fractional 4 bits too
my $Player_Y               = 100<<4;      # XXX contains the fractional 4 bits too
# $Player_XVelFrac -- don't use
# $Player_XHi -- don't use
my $Player_IsHolding       = 0;      # Set when Player is holding something (animation effect only)
my $Player_IsClimbing      = 0;      # Set when Player is climing vine
my $Player_WalkAnimTicks   = 0;      # Ticks between animation frames of walking; max value varies by Player's X velocity
my $Player_HitCeiling      = 0;      # Flag set when Player has just hit head off ceiling
my $Player_LowClearance    = 0;      # Set when Player is in a "low clearance" situation (big Mario in a single block high tunnel)
my $Player_Current         = 0;      # Which Player is currently up (0 = Mario, 1 = Luigi)

my $Kill_Tally             = 0;      # Counter that increases with each successful hit of an object without touching the ground

# Player_Behind_En:
# Specifies whether the "Behind the scenes" effect is actually active
# If the Player has stepped out from behind the background, it can be
# still active, but he won't get the effect of it!
my $Player_Behind_En       = 0;
my $Player_Behind          = 0;      # When non-zero, Player is "behind the scenes" (as by white block)
my  $Level_PipeMove = 0; # see asm; long desc of how targets are encoded

my $Level_SlopeEn          = 0;      # If set, enables slope tiles (otherwise they're considered flat top-only solids)

my $Pad_Holding            = 0;      # Active player's inputs (i.e. 1P or 2P, whoever's playing) buttons being held in (continuous)
my $Pad_Input              = 0;      # Active player's inputs (i.e. 1P or 2P, whoever's playing) buttons newly pressed only (one shot)

my $Controller1Press       = 0;      # Player 1's controller "pressed this frame only" (see Controller1 for values)
my $Controller1            = 0;      # Player 1's controller inputs -- R01 L02 D04 U08 S10 E20 B40 A80

my $Temp_Var1              = 0;
my $Temp_Var2              = 0;
my $Temp_Var3              = 0;      # Player's current X Velocity; set at PRG008_A928, inside Player_Control
my $Temp_Var10             = 0;
my $Temp_Var11             = 0;
my $Temp_Var12             = 0;
my $Temp_Var14             = 0;      # Top run speed depending on Power
my $Temp_Var15             = 0;
my $Temp_Var16             = 0;
my $Temp_VarNP0            = 0;      # A temporary not on page 0; sdw: also: If did not use "high" Y last call to Player_GetTileAndAttr

#
#
#

# Commons (not really comprehensive)
my $TILEA_NOTEINVIS        = 0x03;    # Invisible (until hit) note block

my $TILEA_NOTE        = 0x2E;    # Standard note block
my $TILEA_NOTEFLOWER    = 0x2F;    # Note block with fire flower
my $TILEA_NOTELEAF        = 0x30;    # Note block with leaf
my $TILEA_NOTESTAR        = 0x31;    # Note block with star
my $TILEA_ICEBRICK        = 0x32;    # Ice block
my $TILEA_ICEBLOCK        = 0x32;

my $TILEA_COIN        = 0x40;    # Coin
my $TILEA_COINREMOVED    = 0x41;    # Tile used after coin has been collected
my $TILEA_DOOR1        = 0x42;    # Doorway 1, typically black in appearance (apparently wired to only work in fortresses)
my $TILEA_DOOR2        = 0x43;    # Doorway 2, typically red in appearance
my $TILEA_INVISCOIN        = 0x44;    # Invisible coin block
my $TILEA_INVIS1UP        = 0x45;    # Invisible 1-up
my $TILEA_NOTECOINHEAVEN    = 0x46;    # Placeholder for invisible note block that takes you to coin heaven

my $TILEA_BLOCKEMPTY    = 0x5F;    # Used up ? block type empty block

my $TILEA_QBLOCKFLOWER    = 0x60;    # ? block with fire flower
my $TILEA_QBLOCKLEAF    = 0x61;    # ? block with leaf
my $TILEA_QBLOCKSTAR    = 0x62;    # ? block with star
my $TILEA_QBLOCKCOIN    = 0x63;    # ? block with coin
my $TILEA_QBLOCKCOINSTAR    = 0x64;    # ? block with coin OR star
my $TILEA_QBLOCKCOIN2    = 0x65;    # ? block with coin (again??)
my $TILEA_MUNCHER        = 0x66;    # Muncher plant!
my $TILEA_BRICK        = 0x67;    # Standard brick
my $TILEA_BRICKFLOWER    = 0x68;    # Brick containing fire flower
my $TILEA_BRICKLEAF        = 0x69;    # Brick containing leaf
my $TILEA_BRICKSTAR        = 0x6A;    # Brick containing star
my $TILEA_BRICKCOIN        = 0x6B;    # Brick containing single coin
my $TILEA_BRICKCOINSTAR    = 0x6C;    # Brick containing single coin OR star
my $TILEA_BRICK10COIN    = 0x6D;    # Brick with 10 coins
my $TILEA_BRICK1UP        = 0x6E;    # Brick with 1-up
my $TILEA_BRICKVINE        = 0x6F;    # Brick with vine
my $TILEA_BRICKPSWITCH    = 0x70;    # Brick with P Switch
my $TILEA_HNOTE        = 0x71;    # Coin Heaven launcher note block
my $TILEA_WOODBLOCKBOUNCE    = 0x72;    # Wood block which bounces (no contents)
my $TILEA_WOODBLOCKFLOWER    = 0x73;    # Wood block which bounces and contains fire flower
my $TILEA_WOODBLOCKLEAF    = 0x74;    # Wood block which bounces and contains leaf
my $TILEA_WOODBLOCKSTAR    = 0x75;    # Wood block which bounces and contains star

my $TILEA_WOODBLOCK        = 0x79;    # Standard solid wood block

my $TILEA_GNOTE        = 0xBC;    # Green note block (functions like standard white, just colored wrong)

my $TILEA_PSWITCH_BLANK    = 0xC1;    # Blank tile used to hide a P-Switch after it has been used on level reload

my $TILEA_PATH_HORZ        = 0xC8;    # Horizontal path (typical)
my $TILEA_PATH_VERT        = 0xC9;    # Vertical path (typical)
my $TILEA_PATH_45T2B    = 0xCA;    # 45 degree path top-to-bottom (typical)
my $TILEA_PATH_45B2T    = 0xCB;    # 45 degree path bottom-to-top (typical)
my $TILEA_PATH_625T2B_U    = 0xCC;    # 62.5 degree path top-to-bottom, upper half (typical)
my $TILEA_PATH_625T2B_L    = 0xCD;    # 62.5 degree path top-to-bottom, lower half (typical)
my $TILEA_PATH_625B2T_U    = 0xCE;    # 62.5 degree path bottom-to-top, upper half (typical)
my $TILEA_PATH_625B2T_L    = 0xCF;    # 62.5 degree path bottom-to-top, lower half (typical)

my $TILEA_PSWITCH_PRESSED    = 0xD7;    # Referenced pressed P-Switch
my $TILEA_PSWITCH        = 0xF2;        # P-Switch
my $TILEA_BLOCKBUMP_CLEAR    = 0xF3;    # Tile used when a "bump" block (e.g. ? blocks, note block, etc.) is hit

#

# Tileset 1 (Plains style)
my $TILE1_GOALBLACK        = 0x00;    # Black background of goal area
my $TILE1_GOALEDGE        = 0x01;    # > shape goal edge
my $TILE1_SKYALT        = 0x02;    # ?? Referenced, appears as sky?

my $TILE1_LITTLEFENCE    = 0x04;    # Little fence (runs atop the 'oo' type cheep-cheep bridge)
my $TILE1_ABOVEFENCE    = 0x05;    # Above little fence ?? (it appears empty)
my $TILE1_LILBGCLOUD    = 0x06;    # Little background cloud
my $TILE1_WBLOCKLV        = 0x07;    # White big block left vertical runner
my $TILE1_WBLOCKRV        = 0x08;    # White big block right vertical runner
my $TILE1_WBLOCKM        = 0x09;    # White big block center
my $TILE1_WBLOCKBH        = 0x0A;    # White big block bottom horizontal runner
my $TILE1_WBLOCK_SHUR    = 0x0B;    # White big block shadowed on by another
my $TILE1_WBLOCKSM        = 0x0C;    # White big block shadow middle
my $TILE1_WBLOCKLL        = 0x0D;    # White big block lower-left
my $TILE1_WBLOCKLR        = 0x0E;    # White big block lower-right
my $TILE1_WBLOCKSB        = 0x0F;    # White big block shadow bottom

my $TILE1_PUPCLOUD_M    = 0x10;    # "Power Up Cloud" Mushroom
my $TILE1_PUPCLOUD_F    = 0x11;    # "Power Up Cloud" Flower
my $TILE1_PUPCLOUD_S    = 0x12;    # "Power Up Cloud" Star

my $TILE1_CLOUD_UL        = 0x1F;    # Cloud upper left
my $TILE1_CLOUD_UM        = 0x20;    # Cloud upper middle
my $TILE1_CLOUD_UR        = 0x21;    # Cloud upper right
my $TILE1_CLOUD_LL        = 0x22;    # Cloud lower left
my $TILE1_CLOUD_LM        = 0x23;    # Cloud lower middle
my $TILE1_CLOUD_LR        = 0x24;    # Cloud lower right

my $TILE1_WBLOCKUL        = 0x26;    # White big block upper-left
my $TILE1_WBLOCKTH        = 0x25;    # White big block top horizontal runner
my $TILE1_WBLOCKUR        = 0x27;    # White big block upper-right

my $TILE1_JCLOUD        = 0x2C;    # Judgem's style cloud, solid on top only
my $TILE1_JCLOUDSOLID    = 0x2D;    # Judgem's style cloud, solid all around

my $TILE1_OBLOCKLV        = 0x47;    # Orange big block left vertical runner
my $TILE1_OBLOCKRV        = 0x48;    # Orange big block right vertical runner
my $TILE1_OBLOCKM        = 0x49;    # Orange big block center
my $TILE1_OBLOCKBH        = 0x4A;    # Orange big block bottom horizontal runner
my $TILE1_OBLOCK_SHUR    = 0x4B;    # Orange big block shadowed on by another
my $TILE1_OBLOCKSM        = 0x4C;    # Orange big block shadow middle
my $TILE1_OBLOCKLL        = 0x4D;    # Orange big block lower-left
my $TILE1_OBLOCKLR        = 0x4E;    # Orange big block lower-right
my $TILE1_OBLOCKSB        = 0x4F;    # Orange big block shadow bottom
my $TILE1_OBLOCKUL        = 0x51;    # Orange big block upper-left
my $TILE1_OBLOCKTH        = 0x50;    # Orange big block top horizontal runner
my $TILE1_OBLOCKUR        = 0x52;    # Orange big block upper-right

my $TILE1_GROUNDTM        = 0x53;    # Ground top middle
my $TILE1_GROUNDMM        = 0x54;    # Ground middle-middle
my $TILE1_GROUNDTL        = 0x55;    # Ground top left
my $TILE1_GROUNDML        = 0x56;    # Ground middle-left
my $TILE1_GROUNDTR        = 0x57;    # Ground top right
my $TILE1_GROUNDMR        = 0x58;    # Ground middle-right

my $TILE1_CANNONTOP1    = 0x76;    # Upper top of cannon
my $TILE1_CANNONTOP2    = 0x77;    # Lower top of cannon
my $TILE1_CANNONMID        = 0x78;    # Mid part to ground

my $TILE1_SANDTOP        = 0x7A;    # Solid sand ground, top
my $TILE1_SANDMID        = 0x7B;    # Solid sand ground, middle

my $TILE1_SKY        = 0x80;    # Official sky tile

my $TILE1_VINE        = 0x85;    # Vine
my $TILE1_LITTLE_BUSH    = 0x86;    # The little green bush

my $TILE1_GBLOCKLV        = 0x87;    # Green big block left vertical runner
my $TILE1_GBLOCKRV        = 0x88;    # Green big block right vertical runner

my $TILE1_GBLOCKM        = 0x89;    # Green big block center
my $TILE1_GBLOCKBH        = 0x8A;    # Green big block bottom horizontal runner
my $TILE1_GBLOCK_SHUR    = 0x8B;    # Green big block shadowed on by another
my $TILE1_GBLOCKSM        = 0x8C;    # Green big block shadow middle
my $TILE1_GBLOCKLL        = 0x8D;    # Green big block lower-left
my $TILE1_GBLOCKLR        = 0x8E;    # Green big block lower-right
my $TILE1_GBLOCKSB        = 0x8F;    # Green big block shadow bottom

my $TILE1_BUSH_UL        = 0x90;    # Bush upper left
my $TILE1_BUSH_UR        = 0x91;    # Bush upper right
my $TILE1_BUSH_FUL        = 0x92;    # Bush front (of another bush) upper left
my $TILE1_BUSH_FUR        = 0x93;    # Bush front (of another bush) upper right
my $TILE1_BUSH_BL        = 0x94;    # Bush bottom/middle left
my $TILE1_BUSH_BR        = 0x95;    # Bush bottom/middle right
my $TILE1_BUSH_FBL        = 0x96;    # Bush front (of another bush) bottom left
my $TILE1_BUSH_FBR        = 0x97;    # Bush front (of another bush) bottom right
my $TILE1_BUSH_MID        = 0x98;    # Bush middle
my $TILE1_BUSH_SUL        = 0x99;    # Bush shadowed upper left
my $TILE1_BUSH_SUR        = 0x9A;    # Bush shadowed upper right
my $TILE1_BUSH_SFUL        = 0x9B;    # Bush shadowed front (of another bush) upper left
my $TILE1_BUSH_SFUR        = 0x9C;    # Bush shadowed front (of another bush) upper right
my $TILE1_BUSH_SHUR        = 0x9D;    # Bush with shadow of big block
my $TILE1_BUSH_SBL        = 0x9E;    # Bush shadowed bottom/middle left
my $TILE1_BUSH_SBR        = 0x9F;    # Bush shadowed bottom/middle right

my $TILE1_GBLOCKTH        = 0xA0;    # Green big block top horizontal runner
my $TILE1_GBLOCKUL        = 0xA1;    # Green big block upper-left
my $TILE1_GBLOCKUR        = 0xA2;    # Green big block upper-right

my $TILE1_PIPETB1_L        = 0xAD;    # Pipe top/bottom 1 left (alt level)
my $TILE1_PIPETB1_R        = 0xAE;    # Pipe top/bottom 1 right
my $TILE1_PIPETB2_L        = 0xAF;    # Pipe top/bottom 2 left (Big [?] area)
my $TILE1_PIPETB2_R        = 0xB0;    # Pipe top/bottom 2 right
my $TILE1_PIPETB3_L        = 0xB1;    # Pipe top/bottom 3 left (not enterable)
my $TILE1_PIPETB3_R        = 0xB2;    # Pipe top/bottom 3 right
my $TILE1_PIPETB4_L        = 0xB3;    # Pipe top/bottom 4 left (within level transit)
my $TILE1_PIPETB4_R        = 0xB4;    # Pipe top/bottom 4 right
my $TILE1_PIPEH1_B        = 0xB5;    # Pipe horizontal 1 bottom (alt level)
my $TILE1_PIPEH2_B        = 0xB6;    # Pipe horizontal 2 bottom (not enterable)
my $TILE1_PIPEH_T        = 0xB7;    # Pipe horizontal top (common)
my $TILE1_PIPEHT        = 0xB8;    # Pipe horizontal middle top
my $TILE1_PIPEHB        = 0xB9;    # Pipe horizontal middle bottom
my $TILE1_PIPEVL        = 0xBA;    # Pipe middle vertical left
my $TILE1_PIPEVR        = 0xBB;    # Pipe middle vertical right

my $TILE1_BLOCK_SHUR    = 0xC0;    # Big block shadow upper-right
my $TILE1_BLOCK_SHUL    = 0xC1;    # Big block shadow upper-left (actually none, also used as a cleared P-Switch on level reload, AKA TILEA_PSWITCH_BLANK)
my $TILE1_BLOCK_SHLL    = 0xC2;    # Big block shadow lower-left
my $TILE1_BLOCK_SHLR    = 0xC3;    # Big block shadow lower-right
my $TILE1_BLOCK_SHADOW    = 0xC4;    # Big block general side-shadow
my $TILE1_BLOCK_SHADOWB    = 0xC5;    # Big block general bottom shadow
my $TILE1_BBLOCKLV        = 0xC7;    # Blue big block left vertical runner
my $TILE1_BBLOCKRV        = 0xC8;    # Blue big block right vertical runner
my $TILE1_BBLOCKM        = 0xC9;    # Blue big block center
my $TILE1_BBLOCKBH        = 0xCA;    # Blue big block bottom horizontal runner
my $TILE1_BBLOCK_SHUR    = 0xCB;    # Blue big block shadowed on by another
my $TILE1_BBLOCKSM        = 0xCC;    # Blue big block shadow middle
my $TILE1_BBLOCKLL        = 0xCD;    # Blue big block lower-left
my $TILE1_BBLOCKLR        = 0xCE;    # Blue big block lower-right
my $TILE1_BBLOCKSB        = 0xCF;    # Blue big block shadow bottom

my $TILE1_WATERBUMPS1    = 0xD8;    # Water ... not sure how to describe it
my $TILE1_WATERBUMPS2    = 0xD9;    # Water ... not sure how to describe it
my $TILE1_WATERBUMPSSH    = 0xD9;    # Water ... not sure how to describe it, shaded
my $TILE1_WATERWAVEL    = 0xDB;    # Water waving to the left
my $TILE1_WATERWAVE        = 0xDC;    # Water waving but with no apparent current
my $TILE1_WATERWAVER    = 0xDD;    # Water waving to the right

my $TILE1_WATER        = 0xDE;    # Water

my $TILE1_WFALLTOP        = 0xE0;    # Top of waterfall
my $TILE1_WFALLMID        = 0xE1;    # Middle of water, extending downward

my $TILE1_BBLOCKUL        = 0xE3;    # Blue big block upper-left
my $TILE1_BBLOCKTH        = 0xE2;    # Blue big block top horizontal runner
my $TILE1_BBLOCKUR        = 0xE4;    # Blue big block upper-right

my $TILE1_DIAMOND        = 0xF0;    # Diamond block
my $TILE1_CCBRIDGE        = 0xF1;    # Cheep-cheep 'oo' bridge
my $TILE1_WGROUNDTM        = 0xF4;    # Underwater ground top middle
my $TILE1_WGROUNDMM        = 0xF5;    # Underwater ground middle-middle
my $TILE1_WGROUNDTL        = 0xF6;    # Underwater ground top left
my $TILE1_WGROUNDML        = 0xF7;    # Underwater ground middle-left
my $TILE1_WGROUNDTR        = 0xF8;    # Underwater ground top right
my $TILE1_WGROUNDMR        = 0xF9;    # Underwater ground middle-right

#
#
#

my @src = do {
    open my $fh, '<', __FILE__ or die;
    readline $fh;
};

sub xgoto (*) {
    my $label = shift;
    warn "goto ``$label'' called at " . (caller)[2] . ': ' . $src[ (caller)[2]-1 ];
    goto $label;
}

$obj->set_acceleration(sub { return ( 0, 0, 0); } ); # bitches if it doesn't have this

#
# read keyboard and joystick
#

$app->add_event_handler(
    sub {
        # $_[1]->stop if $_[0]->type == SDL_QUIT || $quit;
        $_[1]->stop if $_[0]->type == SDL_QUIT; # XXX

        if( $quit ) {
            $Player_XVel = 0;
            $Player_YVel = 0;
            $pressed = { };
            return; 
        }

        my $key = $_[0]->key_sym;
        my $name = SDL::Events::get_key_name($key) if $key;
        $name = 'A' if $name and $name eq 'a';
        $name = 'B' if $name and $name eq 'b';

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
           if( $_[0]->jaxis_axis == 4 and $_[0]->jaxis_value > 10000 ) {
               $pressed->{down} = 1;
           } elsif( $_[0]->jaxis_axis == 4 and $_[0]->jaxis_value < -10000 ) {
               $pressed->{up} = 1;
           } elsif( $_[0]->jaxis_axis == 4 and $_[0]->jaxis_value > -10000 and $_[0]->jaxis_value < 10000 ) {
               $pressed->{down} = 0;
               $pressed->{up} = 0;
           }
        } elsif( $_[0]->type == SDL_JOYBALLMOTION ) {
            #warn "- Joystick trackball motion event structure";
        } elsif( $_[0]->type == SDL_JOYHATMOTION ) {
            #warn " - Joystick hat position change event structure";
        } elsif( $_[0]->type == SDL_JOYBUTTONDOWN and $_[0]->jbutton_button == 2 ) {
            # button 2 is B, button 1 is A
            # warn " - Joystick button event structure: button down: button ". $_[0]->jbutton_button;
            $pressed->{B} = 1;
        } elsif( $_[0]->type == SDL_JOYBUTTONUP and $_[0]->jbutton_button == 2 ) {
            # warn " - Joystick button event structure: button up: button ". $_[0]->jbutton_button;
            $pressed->{B} = 0;
        } elsif( $_[0]->type == SDL_JOYBUTTONDOWN and $_[0]->jbutton_button == 1 ) {
            # button 2 is B, button 1 is A
            # warn " - Joystick button event structure: button down: button ". $_[0]->jbutton_button;
            $pressed->{A} = 1;
        } elsif( $_[0]->type == SDL_JOYBUTTONUP and $_[0]->jbutton_button == 1 ) {
            # warn " - Joystick button event structure: button up: button ". $_[0]->jbutton_button;
            $pressed->{A} = 0;
        }

    }
);

sub decode_pad {
    my $bits = shift;
    my $out = '';
    $out .= 'A' if $bits & $PAD_A;
    $out .= 'B' if $bits & $PAD_B;
    $out .= '[select]' if $bits & $PAD_SELECT;
    $out .= '[start]' if $bits & $PAD_START;
    $out .= 'U' if $bits & $PAD_UP;
    $out .= 'D' if $bits & $PAD_DOWN;
    $out .= 'L' if $bits & $PAD_LEFT;
    $out .= 'R' if $bits & $PAD_RIGHT;
    return $out;
}

$app->add_show_handler(
    sub {

        #
        # controls and animation selection
        #

        Boulderdash();

        # Makes for "wobbly" raising of the airship at least..
        # from Player_DoGameplay:

        $Counter_Wiggly = ( $Counter_Wiggly & 0xf0 ) - 0x90;  $Counter_Wiggly += 256 if $Counter_Wiggly < 0;  # hacked up
        $Counter_1++; $Counter_1 = 0 if $Counter_1 == 256; # happens in PRG031_F567; hacked up

        #
        # Player_Update() and Player_Control() are both called by Player_DoGameplay(); Player_Update() calls Player_DetectSolids()
        #

        # Level_MainLoop (PRG/prg030.asm)
        # +- Player_DoGameplay (PRG/prg008.asm)
        #    +- Player_Control (PRG/prg008.asm)
        #    |  +- GndMov_Small (PRG/prg008.asm)
        #    |    +- Player_GroundHControl (PRG/prg008.asm)
        #    +- Player_Update (PRG/prg008.asm)
        #       +- Player_DetectSolids (PRG/prg008.asm)

        #
        #
        #

        Read_Joypads();

        Player_Control();  

        Player_DetectSolids();

warn "Player_InAir $Player_InAir Player_MoveLR $Player_MoveLR Player_XVel $Player_XVel Player_YVel $Player_YVel " .
     " Player_HitCeiling $Player_HitCeiling Player_LowClearance $Player_LowClearance\n";
warn "Pad_Input << $Pad_Input @{[ decode_pad($Pad_Input) ]} >> Pad_Holding << $Pad_Holding @{[ decode_pad($Pad_Holding) ]} >>\n";

        # from Player_DoGameplay:
        $Player_LowClearance = 0;

        #
        #
        #

#use Enbugger;
#use Devel::Trace;
$Devel::Trace::TRACE = 1;

        if ( $pressed->{right} ) {
            if   ( $pressed->{up} ) { $sprite->sequence('jumpr') }
            elsif ($sprite->sequence() ne 'right') { $sprite->sequence('right'); }

        }
        elsif ( $sprite->sequence() eq 'right' and ! $pressed->{left} ) {
            $sprite->sequence('stopr');
        }

        if ( $pressed->{left} ) {
            if   ( $pressed->{up} ) { $sprite->sequence('jumpl') }
            elsif ($sprite->sequence() ne 'left') { $sprite->sequence('left'); }
        }
        elsif ( $sprite->sequence() eq 'left' and ! $pressed->{right} ) {
            $sprite->sequence('stopl');
        }

        # if ( $pressed->{up} && ! $lockjump ) 
        if ( $pressed->{up} ) {

            $sprite->sequence('jumpr')   if ( $sprite->sequence() =~ 'r'); # XXX
            $sprite->sequence('jumpl')   if ( $sprite->sequence() =~ 'l'); # XXX

        }

        #
        # collision checks
        #

#        my $collision = check_collision( $state, \@blocks );
#        $dashboard = 'Collision = ' . Dumper $collision;
#
#        if ( $collision != -1 && $collision->[0] eq 'x' ) {
#            my $block = $collision->[1];
#
#            #X-axis collision_check
#            if ( $state->v_x() > 0 ) {    #moving right
#                $state->x( $block->[0] - $block_width - 3 );    # set to edge of block XXX what is 3 for?
#            }
#
#            if ( $state->v_x() < 0 ) {                #moving left
#                $state->x( $block->[0] + 3 + $block_width );    # set to edge of block XXX what is 3 for?
#            }
#        }

        # y-axis collision_check

#        if ( $state->v_y() < 0 ) {                    #moving up
#            if ( $collision != -1 && $collision->[0] eq 'y' ) {
#                my $block = $collision->[1];
#                $state->y( $block->[1] + $block_height + 3 );    # stop just below block
#                $state->v_y(0);                                  # momentum lost
#            }
#            else {
#                # apply gravity; continue jumping
#                if( $gravity_delay-- <= 0 or ! $pressed->{up} ) {
#                    $ay = $gravity; 
#                }
#            }
#        }
#        else {
#            # moving along the ground 
#            # Y velocity zero or greater than zero
#            if ( $collision != -1 && $collision->[0] eq 'y' ) {
#                my $block = $collision->[1];
#                $state->y( $block->[1] - $h - 1 );  # hover one pixel over the block
#                $state->v_y(0);                     # Causes test again in next frame
#                $ay = 0;                            # no downward velocity
#                $lockjump = 0 if ! $pressed->{up};  # able to jump again
#                $sprite->sequence( 'stopr' ) if $sprite->sequence eq 'jumpr';
#                $sprite->sequence( 'stopl' ) if $sprite->sequence eq 'jumpl';
#            } 
#            else { 
#                # apply gravity; continue falling 
#                # XXXX need a terminal velocity
#                $ay = $gravity;
#            }
#        }

        if ( $Player_Y > 0 and ($Player_Y>>4) + 10 > $app->h ) {
            # fell off of the world
            warn "player fell off of the world";
            $quit = 1;
        }

        #
        # re-center the screen
        #

        #
        # draw
        #

        $app->draw_rect( [ 0, 0, $app->w, $app->h ], 0x0 );  # clear the screen

        # warn "Player_X shifted: @{[ $Player_X >> 4 ]} Player_Y shifted: @{[ $Player_Y >> 4 ]}";
        my $player_x = $Player_X >> 4;
        my $player_y = ( $Player_Y >> 4 ) + 16;
        $sprite->x( $player_x );
        $sprite->y( $player_y );

        if( ! $quit ) {
            $sprite->draw($app->surface);
        } else {
            SDL::Video::blit_surface(
                $deadmario, SDL::Rect->new(0, 0, 16, 16,),
                $app,       SDL::Rect->new($player_x, $player_y, 16, 16),
            );
        }

        for my $x ( 0 .. $map_max_x ) {
            next if $x * $w > $app->w;
            for my $y ( 0 .. $map_max_y ) {
                next if $y * $w > $app->h;
                # $app->draw_rect( [ $x * $w, $y * $w, $w, $w ], 0xFF0000FF ) if map_x_y($x, $y) eq 'X';
                my $tile = map_x_y($x, $y);
                if( $tile ne ' ' ) {
                    my $icon = $icon_lookup->{$tile};
                    if( $icon ) {
                        SDL::Video::blit_surface(
                            $icon,     SDL::Rect->new(0, 0, 16, 16,),
                            $app,      SDL::Rect->new($x<<4, $y<<4, 16, 16),
                        );
                    } else {
                        # alright, it's one of the sprites, then
                        my $sprite;
                        $sprite = $fireflysprite if grep $tile eq $_, 'F1', 'F2', 'F3', 'F4';
                        $sprite = $explodetospace if grep $tile eq $_, 'E1', 'E2', 'E3', 'E4', 'E5';
                        if( $sprite ) {
                            $sprite->x( $x << 4 );
                            $sprite->y( $y << 4 );
                            $sprite->draw($app->surface);
                        } else {
                            # else I don't know what
                            warn "unknown tile: ``$tile''";
                        }
                    }
                }
            }
        }

        SDL::GFX::Primitives::string_color( $app, $app->w/2-100, 0, $dashboard, 0xFF0000FF); # debug

        SDL::GFX::Primitives::string_color(
            $app,
            $app->w / 2 - 100,
            $app->h / 2,
            "Mario is DEAD", 0xFF0000FF
        ) if $quit;

        $app->update();
    }
);

#
# render objects
#

#sub check_collision {
#    my ( $mario, $blocks ) = @_;
#
#    my @collisions = ();
#
#    foreach (@$blocks) {
#        my $hash = {
#            x  => $mario->x,
#            y  => $mario->y,
#            w  => $w,
#            h  => $h,
#            xv => $mario->v_x * 0.02,
#            yv => $mario->v_y * 0.02
#        };
#        my $rect  = hash2rect($hash);
#        my $bhash = { x => $_->[0], y => $_->[1], w => $w, h => $block_height };
#        my $block = hash2rect($bhash);
#        my $c = dynamic_collision( $rect, $block, interval => 1, keep_order => 1 );
#        if ($c) {
#
#            my $axis = $c->axis() || 'y';
#
#            return [ $axis, $_ ];
#
#        }
#
#    }
#
#    return -1;
#
#}

sub Boulderdash {

    #
    # XXXXXXXXXXXXX
    #

    return unless 0 == ( $Counter_1 % 4 );

    my $player_x = ( $Player_X >> 4 ) + 8;      $player_x >>= 4;  # first drop the fractal part, then convert from pixels to blocks
    my $player_y = ( $Player_Y >> 4 ) + 16;     $player_y >>= 4;
    # my $player_y = ( $Player_Y >> 4 ) + 8;     $player_y >>= 4;

    # my $get = sub { my ($p, $dir) = @_;       return $map->[ p.x + (DIRX[dir] || 0)]->[p.y + (DIRY[dir] || 0)].object; },
    # my $set = sub { ($p, $o, $dir) = @_;  var cell = this.cells[p.x + (DIRX[dir] || 0)][p.y + (DIRY[dir] || 0)]; cell.object = o; cell.frame = this.frame; },
    # my $clear = sub { my ($p, $dir) = @_;    this.set(p,OBJECT.SPACE,dir); },
    # my $move = sub { my ($p, $dir, $o) = @_;  this.clear(p); this.set(p,o,dir); },

    # local
    my $xydir = sub { return ( $_[0] + $DIRX->[$_[2]], $_[1] + $DIRY->[$_[2]] ) };
    my $xydirmap = sub :lvalue { my ($x, $y) = $xydir->(@_); $map->[$x]->[$y]; };

    # my $isempty = sub { $xydirmap->(@_) eq ' ' and ( $_[0] != $player_x and $_[1] != $player_y); }; # this mucks things up
    my $isempty = sub { $xydirmap->(@_) eq ' ' };
    my $isdirt = sub { $xydirmap->(@_) eq '~'; };
    my $isboulder = sub { $xydirmap->(@_) eq '*'; };
    # my $isrockford = sub { $xydirmap->(@_) eq 'M'; }, # XXX
    my $isrockford = sub { $xydirmap->(@_) eq 'M'; }, # XXXXXX
    my $isdiamond = sub { $xydirmap->(@_) eq 'v'; };

    my $isexplodable = sub { $tile_properties{ $xydirmap->(@_) }->{explodable}; };
    my $isconsumable = sub { $tile_properties{ $xydirmap->(@_) }->{consumable}; };  # consumable by an explosion
    my $isrounded = sub { $tile_properties{ $xydirmap->(@_) }->{rounded}; };  # consumable by an explosion

    my $rotateLeft = sub { my $dir = shift; return( ($dir-2) + ($dir < 2 ? 8 : 0) ); };
    my $rotateRight = sub { my $dir = shift; return( ($dir+2) - ($dir > 5 ? 8 : 0) ); };
    my $horizontal = sub { my $dir = shift; return( ($dir == LEFT) || ($dir == RIGHT) ); };
    my $vertical = sub { my $dir = shift; return( ($dir == UP)   || ($dir == DOWN) ); };

    my $explode; $explode = sub {
        my( $x, $y, $basedir ) = @_;
        ($x, $y) = $xydir->($x, $y, $basedir);
        # var explosion = (this.isbutterfly(p2) ? OBJECT.EXPLODETODIAMOND0 : OBJECT.EXPLODETOSPACE0); # XXX
        my $explosion = 'E1';
        $map->[$x]->[$y] = $explosion;
        for(my $dir = 0 ; $dir < 8 ; ++$dir) { # for each of the 8 directions
          if ( $tile_properties{ $xydirmap->( $x, $y, $dir ) }->{explodable} ) {
            $explode->($x, $y, $dir);
          } elsif ( $tile_properties{ $xydirmap->( $x, $y, $dir ) }->{consumable} ) {
            $quit = 1 if $isrockford->( $x, $y, $dir );
            $xydirmap->( $x, $y, $dir ) = $explosion;
          }
        }
    };

    my $make_rigid_unit = sub {
        my( $uc, $lc ) = @_;
        my @rigid;
        my $block_count;  # if we find too many blocks, abort checking
        my $disable;
        my %did;
        sub {
            my( $x, $y ) = @_;
warn "disable" if $disable;
            return if $disable;
            return if exists $did{$x, $y};  #  use the cache; enable this one or the one below
            # return if grep { $_->[0] == $x and $_->[1] == $y } @rigid;  # use the cache; enable this one or the one above; if this block is part of a larger structure we looked at this same frame, don't do it again
            @rigid = ();
            my $recurse;  $recurse = sub {
                my( $x, $y ) = @_;
                return if $disable;
                return unless $map->[$x]->[$y] eq $uc; # or $map->[$x]->[$y] eq $lc;
                # return if grep { $_->[0] == $x and $_->[1] == $y } @rigid; # don't recurse into stuff we did; this one of the next one; not necessary as we make the tile lowercase
                # return if exists $did{$x, $y};  $did{$x, $y}++; # don't recurse into stuff we already did; enable this one or the one above; not needed as we make the tile lowercase
                $did{$x, $y}++; # keep track of which tiles we looked at this frame so we don't compute the same structure twice the same frame; return not needed as we make the tile lowercase
                push @rigid, [ $x, $y ];
                $map->[$x]->[$y] = $lc; # we later change it back if we aren't falling; just don't recurse back into ourself
                # $map->[$x]->[$y] = '.'; # we later change it back if we aren't falling; just don't recurse back into ourself; debug
                $block_count++;  $disable = 1 if $block_count > 95; # XXXX
                $recurse->( $xydir->($x, $y, DOWN) )  if $xydirmap->($x, $y, DOWN) eq $uc;
                $recurse->( $xydir->($x, $y, UP) )    if $xydirmap->($x, $y, UP) eq $uc; 
                $recurse->( $xydir->($x, $y, LEFT) )  if $xydirmap->($x, $y, LEFT) eq $uc;
                $recurse->( $xydir->($x, $y, RIGHT) ) if  $xydirmap->($x, $y, RIGHT) eq $uc;
            };
            $recurse->( $x, $y );
            $block_count = 0;
            my $supported = 0;  # until shown otherwise
            # faster but only checks the bottommost tile in the chunk
            # for my $i ( 0 .. $map_max_x-1 ) {
            #     my @rigid_this_column = grep $_->[0] == $x, @rigid;
            #     (my $bottom_bit_of_rigid) = sort { $main::b->[0] <=> $main::a->[0] } @rigid_this_column;  # sort by X 
            #     $supported = 1 if ! $isempty->($bottom_bit_of_rigid->[0], $bottom_bit_of_rigid->[1], DOWN);
            # }
            for my $tile ( @rigid ) {
                my $icon = $xydirmap->($tile->[0], $tile->[1], DOWN) ;
                if( $icon ne 'D' and $icon ne 'd' and $icon ne ' ' ) {
                    # if( our $counter++ > 300 ) { $xydirmap->($tile->[0], $tile->[1], DOWN) = '.'; }; # XXX debug
# warn "supported at one down from $tile->[0], $tile->[1]";
                    $supported = 1;  last;
                }
            }
            if( $supported ) {
                for my $xy ( @rigid ) { 
                    $map->[ $xy->[0] ]->[ $xy->[1] ] = $uc;  
                }
            } else {
# warn "NOT supported";

                # for my $xy ( @rigid ) { $map->[ $xy->[0] ]->[ $xy->[1] ] = '.';  } # XXX debug
                # XXXXXX debug
                # for my $i ( 0 .. $map_max_x-1 ) {
                #     my @rigid_this_column = grep $_->[0] == $x, @rigid;
                #     (my $bottom_bit_of_rigid) = sort { $main::b->[0] <=> $main::a->[0] } @rigid_this_column;
                #     $xydirmap->( $bottom_bit_of_rigid->[0], $bottom_bit_of_rigid->[1] ) = '.';
                # }

            }
            @rigid = ();
        };
    };
    my $dirt_rigid_unit = $make_rigid_unit->('D', 'd');
    my $wood_rigid_unit = $make_rigid_unit->('W', 'w');

    $map->[$player_x]->[$player_y] = 'M' if $map->[$player_x]->[$player_y] eq ' '; # so that isempty will come back false XXXXXXXXXXXXXXX highly experimental... okay, mucks up digging; probably fixable
    # my $player_tile_save = $map->[$player_x]->[$player_y]; $map->[$player_x]->[$player_y] = 'M';

    # for(my $y = 0 ; $y < $map_max_y ; ++$y) {  # XXX
    for my $y ( reverse 0 .. $map_max_y-1 ) {
        for(my $x = 0 ; $x < $map_max_x ; ++$x) {

            my $tile = $map->[$x]->[$y];  defined $tile or die "$x $y";

            # boulders

            if( $tile eq '*' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $map->[$x]->[$y] = '@';
                } elsif ( $isrounded->($x, $y, DOWN) and $isempty->($x, $y, LEFT) && $isempty->($x, $y, DOWNLEFT)) {
                    # this.move(p, DIR.LEFT, OBJECT.BOULDERFALLING);
                    $map->[$x]->[$y] = ' ';
                    $xydirmap->( $x, $y, LEFT ) = '@';
                } elsif ( $isrounded->($x, $y, DOWN) and $isempty->($x, $y, RIGHT) && $isempty->($x, $y, DOWNRIGHT)) {
                    # this.move(p, DIR.RIGHT, OBJECT.BOULDERFALLING);
                    $map->[$x]->[$y] = ' ';
                    $xydirmap->( $x, $y, RIGHT ) = '@';
                }
            }

            if( $tile eq '@' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $xydirmap->($x, $y, DOWN) = '@';
                    $map->[$x]->[$y] = ' ';
                } elsif ($xydirmap->($x, $y, DOWN) eq 'X') {
                    $xydirmap->($x, $y, DOWN) = '*';
                    $map->[$x]->[$y] = ' ';
                } elsif ($xydirmap->($x, $y, DOWN) eq 'M') {
                    $xydirmap->($x, $y, DOWN) = '@';
                    $map->[$x]->[$y] = ' ';
                    $quit = 1;  # XXXXXX smooshed mario
                # } elsif ($isexplodable->($x, $y, DOWN)) { # XXXXXXXXXX todo
                #   $explode->($x, $y, DOWN);
                # } elsif ($ismagic->($x, $y, DOWN))   { 
                #   $domagic->($x, $y, OBJECT.DIAMOND);   
                } elsif ($isrounded->($x, $y, DOWN) && $isempty->($x, $y, LEFT) && $isempty->($x, $y, DOWNLEFT)) {
                    $xydirmap->($x, $y, LEFT) = '@';
                    $map->[$x]->[$y] = ' ';
                } elsif ($isrounded->($x, $y, DOWN) && $isempty->($x, $y, RIGHT) && $isempty->($x, $y, DOWNRIGHT)) {
                    $xydirmap->($x, $y, RIGHT) = '@';
                    $map->[$x]->[$y] = ' ';
                } else {
                    # $set->($x, $y, OBJECT.BOULDER);
                    $map->[$x]->[$y] = '*';
                }
            }

            # sand

            if( $tile eq '#' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $map->[$x]->[$y] = '=';
                } elsif ($xydirmap->($x, $y, DOWN) eq 'M') {
                    $xydirmap->($x, $y, DOWN) = '=';
                    $map->[$x]->[$y] = 'M';
                    $player_x = $x;  $player_y = $y;
                    $Player_Y = ($player_y << 4 ) << 4; # $Player_Y -= (1<<4)<<4;  # don't smooshed mario
                } elsif ( $isempty->($x, $y, LEFT) && $isempty->($x, $y, DOWNLEFT)) {
                    $map->[$x]->[$y] = ' ';
                    $xydirmap->( $x, $y, DOWNLEFT ) = '=';
                } elsif ( $isempty->($x, $y, RIGHT) && $isempty->($x, $y, DOWNRIGHT)) {
                    $map->[$x]->[$y] = ' ';
                    $xydirmap->( $x, $y, DOWNRIGHT ) = '=';
                } elsif ( 
                    $isempty->($x, $y, LEFT) && 
                    $isempty->( $xydir->($x, $y, LEFT), LEFT) && 
                    $isempty->( $xydir->($x, $y, LEFT), DOWNLEFT)
                ) {
                    $xydirmap->($x, $y, LEFT) = '=';
                    $map->[$x]->[$y] = ' ';
                } elsif ( 
                    $isempty->($x, $y, RIGHT) && 
                    $isempty->( $xydir->($x, $y, RIGHT), RIGHT) && 
                    $isempty->( $xydir->($x, $y, RIGHT), DOWNRIGHT)
                ) {
                    $xydirmap->($x, $y, RIGHT) = '=';
                    $map->[$x]->[$y] = ' ';
                } elsif ( $isempty->($x, $y, LEFT) && $xydirmap->($x, $y, UP) eq '#' ) {
                    $xydirmap->($x, $y, LEFT) = '=';
                    $map->[$x]->[$y] = ' ';
                } elsif ( $isempty->($x, $y, RIGHT) && $xydirmap->($x, $y, UP) eq '#' ) {
                    $xydirmap->($x, $y, RIGHT) = '=';
                    $map->[$x]->[$y] = ' ';
                }
            }

            if( $tile eq '=' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $xydirmap->($x, $y, DOWN) = '=';
                    $map->[$x]->[$y] = ' ';
                } elsif ( $isempty->($x, $y, LEFT) && $isempty->($x, $y, DOWNLEFT)) {
                    $xydirmap->($x, $y, DOWNLEFT) = '=';
                    $map->[$x]->[$y] = ' ';
                } elsif ( $isempty->($x, $y, RIGHT) && $isempty->($x, $y, DOWNRIGHT)) {
                    $xydirmap->($x, $y, DOWNRIGHT) = '=';
                    $map->[$x]->[$y] = ' ';
                } else {
                    $map->[$x]->[$y] = '#';
                }
            }

            # dirt 

            if( $tile eq 'D' ) {
                $dirt_rigid_unit->($x, $y);
            }

            if( $tile eq 'd' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $xydirmap->($x, $y, DOWN) = 'd';
                    $map->[$x]->[$y] = ' ';
                } elsif ($xydirmap->($x, $y, DOWN) eq 'M') {
                    $xydirmap->($x, $y, DOWN) = 'd';
                    $map->[$x]->[$y] = ' ';
                    $quit = 1;  # XXXXXX smooshed mario
                } else {
                    $map->[$x]->[$y] = 'D';
                }
            }

            # wood blocks

            if( $tile eq 'W' ) {
                # $wood_rigid_unit->($x, $y);
                if ( $isempty->($x, $y, DOWN) and $isempty->($x, $y, DOWNLEFT ) and $isempty->($x, $y, DOWNRIGHT ) ) {
                    $map->[$x]->[$y] = 'w';
                }
            }

            if( $tile eq 'w' ) {
                if ($isempty->($x, $y, DOWN)) {
                    $xydirmap->($x, $y, DOWN) = 'w';
                    $map->[$x]->[$y] = ' ';
                } elsif ($xydirmap->($x, $y, DOWN) eq 'M') {
                    $xydirmap->($x, $y, DOWN) = 'w';
                    $map->[$x]->[$y] = ' ';
                    $quit = 1;  # XXXXXX smooshed mario
                } else {
                    $map->[$x]->[$y] = 'W';
                }
            }

            # fireflies

            if( grep $tile eq $_, 'F1', 'F2', 'F3', 'F4' ) {
                my $dir = { F1 => LEFT, F2 => UP, F3 => RIGHT, F4 => DOWN }->{ $tile };
                my $newdir = $rotateLeft->($dir);  defined $newdir or die;
                if ($isrockford->($x, $y, UP) || $isrockford->($x, $y, DOWN) || $isrockford->($x, $y, LEFT) || $isrockford->($x, $y, RIGHT)) {
                    $explode->($x, $y);
                # else if (this.isamoeba(p, DIR.UP) || this.isamoeba(p, DIR.DOWN) || this.isamoeba(p, DIR.LEFT) || this.isamoeba(p, DIR.RIGHT))
                #  this.explode(p);
                } elsif ($isempty->($x, $y, $newdir)) {
                    # this.move(p, newdir, FIREFLIES[newdir]);
                    my $firefly = $FIREFLIES->[ $newdir ];  defined $firefly or die or die;
                    $xydirmap->($x, $y, $newdir) = $firefly;
                    $map->[$x]->[$y] = ' ';
                } elsif ($isempty->($x, $y, $dir)) {
                    # this.move(p, dir, FIREFLIES[dir]);
                    my $firefly = $FIREFLIES->[ $dir ]; defined $firefly or die;
                    $xydirmap->($x, $y, $dir) = $firefly;
                    $map->[$x]->[$y] = ' ';
                } else {
                    # this.set(p, FIREFLIES[rotateRight(dir)]);
                    my $firefly = $FIREFLIES->[ $rotateRight->($dir) ]; defined $firefly or die;
                    $map->[$x]->[$y] = $firefly;
                }
            }

            if( $tile eq 'E1' ) {
                $map->[$x]->[$y] = 'E2';
            } elsif ( $tile eq 'E2' ) {
                $map->[$x]->[$y] = 'E3';
            } elsif ( $tile eq 'E3' ) {
                $map->[$x]->[$y] = 'E4';
            } elsif ( $tile eq 'E4' ) {
                $map->[$x]->[$y] = ' ';
            }

        }
    }

    if( $tile_properties{ $map->[ $player_x ]->[ $player_y ] }->{diggable} ) {
        $map->[$player_x]->[$player_y] = ' '; # XXX improve
    }

    if( $xydirmap->($player_x, $player_y, DOWN) eq 'D' and $Pad_Holding & $PAD_DOWN ) {
        $xydirmap->($player_x, $player_y, DOWN) = ' ';        
    }

    if( $map->[$player_x]->[$player_y] eq '#' ) {
        $map->[$player_x]->[$player_y] = 'M';
    }

    $map->[$player_x]->[$player_y] = ' ' if $map->[$player_x]->[$player_y] eq 'M'; # undo marking where mario is XXXX
    # $map->[$player_x]->[$player_y] = $player_tile_save; # highly experimental... 

}

sub Player_Control {

        # ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        # ; Player_Control
        # ;
        # ; Pretty much all controllable Player actions like ducking,
        # ; sliding, tile detection response, doors, vine climbing, and 
        # ; including basic power-up / suit functionality (except the actual 
        # ; throwing of fireballs / hammers for some reason!)
        # ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
      Player_Control:
        $Player_FlipBits_OLD = $Player_FlipBits;
        $Player_InAir_OLD = $Player_InAir;
        goto PRG008_A6D2 if $Player_EndLevel;          # If Player is running off at the end of the level, jump to PRG008_A6D2
        goto PRG008_A6DA if $Player_VibeDisable == 0;  # If Player is not "vibrationally disabled", jump to PRG008_A6DA
        $Player_VibeDisable--;
      PRG008_A6D2:
        # Remove horizontal velocity and cancel controller inputs
        $Player_XVel = $Pad_Holding = $Pad_Input = 0;

      PRG008_A6DA:
        goto PRG008_A6E5 if $Player_Slide == 0;        # If Player is NOT sliding down slope, jump to PRG008_A6E5
        $Pad_Input &= ~ $PAD_B;                        # Otherwise (sdw: if player is sliding), disable 'B' button; sdw: AND #~PAD_B

      PRG008_A6E5:
        # LDA Level_Objects+1
        # CMP #OBJ_TOADANDKING
        # BNE PRG008_A6F2         ; If first object is not "Toad and the King" (i.e. we're in the end of world castle), jump to PRG008_A6F2
        # LDA <Pad_Holding
        # AND #~(PAD_LEFT | PAD_RIGHT | PAD_UP | PAD_DOWN)
        # STA <Pad_Holding    ; Otherwise, disable all directional inputs
      # PRG008_A6F2:
        $y = $Player_Suit;
        goto PRG008_A70E if $y == 0;         # If Player is small, jump to PRG008_A70E
        goto PRG008_A70E if $y == $PLAYERSUIT_FROG; # If Player is Frog, jump to PRG008_A70E
        $a = $Player_IsHolding | $Player_Slide | $Player_Kuribo;
        goto PRG008_A70E if $a != 0; # If Player is holding something, sliding down a slope, or in a Kuribo's shoe, jump to PRG008_A70E 
        $a = $Player_InAir;
        goto PRG008_A71C if $a == 0; # If Player is NOT mid air, jump to PRG008_A71C
        $a = $Player_InWater;
        goto PRG008_A715 if $a == 0; # If Player is NOT in water, jump to PRG008_A715

      PRG008_A70E:
        # Forcefully disable any ducking
        $Player_IsDucking = 0;
        goto PRG008_A736;            # Jump (technically always) to PRG008_A736

      PRG008_A715:
        $a = $Player_IsDucking;
        goto PRG008_A733 if $a != 0;   # If Player is ducking down, jump to PRG008_A733
        goto PRG008_A736 if $a == 0;   # Otherwise, jump to PRG008_A736

      PRG008_A71C:
        $Player_IsDucking = 0;
        $a = $Level_SlopeEn;
        goto PRG008_A72B if $a == 0;   # If slopes are not enabled, jump to PRG008_A72B
        $a = $Player_SlideRate; 
        goto PRG008_A736 if $a != 0;   # If Player has a slide magnitude, jump to PRG008_A736

      PRG008_A72B:
        $a = $Pad_Holding;
        $a &= ($PAD_LEFT | $PAD_RIGHT | $PAD_UP | $PAD_DOWN);
        goto PRG008_A736 if $a != $PAD_DOWN;  # If Player is not just holding down, jump to PRG008_A736

      PRG008_A733:
        $Player_IsDucking = $y; # Set ducking flag (uses non-zero suit value); sdw: from $y = $Player_Suit; player not ducking unless not small

      PRG008_A736:
        $y = 20;                       # Y = 20 (ducking or small)
        $a = $Player_Suit;
        goto PRG008_A743 if $a == 0;   # If Player is small, jump to PRG008_A743
        $a = $Player_IsDucking;
        goto PRG008_A743 if $a != 0;   # If Player is ducking, jump to PRG008_A743
        $y = 10;                       # Otherwise, Y = 10 (not ducking, not small)

      PRG008_A743:
        $Temp_Var10 = $y;              # Temp_Var10 (Y offset) = 20 or 10
        $a = 0x08;
        $Temp_Var11 = $a;              # Temp_Var11 (X offset) = 8
        Player_GetTileAndSlope();      # Get tile above Player
        $Level_Tile_Positions->[ 0 ] = [ ($Player_X >> 4) + $Temp_Var11, ($Player_Y >> 4) + $Temp_Var10  ]; # hacked up
        $Level_Tile_Head = $a;         # -> Level_Tile_Head ; sdw: this variable seems to be the space the players head occupies and isn't used for much except for low-clearance detection; in normal play, it never is anything but space
# warn ">>$a<< -- 'Get tile above Player' -- actually, tile where the players head is"; # XXX this never ever gets set to anything
        $Temp_Var1 = $a;               # -> Temp_Var1
        $Temp_Var2 = $Level_Tile_GndL; # Get left ground tilee -> Temp_Var2 # 
        $a = $Player_Behind_En = $Player_Behind;  # Default enable with being behind the scenes
        goto PRG008_A77E if $a == 0;   # If Player is not behind the scenes, jump to PRG008_A77E
        $a = $Counter_1;
        $carry = $a & 0x01;
        goto PRG008_A766 if ! $carry;  # Every other tick, jump to PRG008_A766
        $Player_Behind--;

      PRG008_A766:
        $y = 0;                        # Y = 0 (disable "behind the scenes")
        # If tile behind Player's head is $41 or TILE1_SKY, jump to PRG008_A77B
        $a = $Temp_Var1;
        goto PRG008_A77B if $a == $TILE1_SKY;
        $y++;                                     # Y = 1 (enable "behind the scenes")
        $a = $Player_Behind;
        goto PRG008_A77B if $a != 0;              # If Player is behind the scenes, jump to PRG008_A77B
        $Player_Behind = $y;                      # Set Player as behind the scenes

      PRG008_A77B:
        $Player_Behind_En = $y;                   # Store whether Player is actually behind scenery

      PRG008_A77E:
        $a = $Temp_Var1;                          # sdw: came from Level_Tile_Head, after Player_GetTileAndSlope()
        # $a &= 0b11000000;                         # sdw: was $c0; XX also, have to do this a different way
        # was ASL, ROL, ROL, which cycles the top two bits through the carry flag and then into the low order bits (ASL brings 0 into the low order bit)
        # $a >>= 6; # sdw, have to do this a different way
        # $y = $a;                                  # Y = uppermost 2 bits down by 6 (thus 0-3, depending on which "quadrant" of tiles we're on, $00, $40, $80, $C0) XXX this won't work unless we number our tiles the same

        # Checks for solid tile at Player's head
        # $a = $Temp_Var1;
        # sdw, from the Tile_AttrTable comments:
        # In levels, both "halves" define the first tile of a quadrant to be solid
        # The first half is solid at the ground (i.e. Player can stand on it)
        # The second half is solid at the head and walls (i.e. Player bumps head on it, typically "full solidity" when combined above)
        # sdw: my reading of this is that there are four pages of graphics tiles.  each page contains a mixture of solid and enterable tiles.
        # sdw: two tables are kept.  one for blocks that can be stood on, and another for blocks with solid walls/bottom.
        # sdw: $solidity_table->[ which kind of solidity we're checking ]->[ which page of tiles ] = number of first solid on that page
        # sdw: so this goto if less than is probably executing the goto if we haven't hit our head; the tile is numbered below the number of the
        # sdw: first solid tile
        # goto PRG008_A7AD if $a < $Tile_AttrTable->[ $y + 4 ];  # CMP Tile_AttrTable+4,Y    ; Wall/ceiling-solid tile quadrant limits begin at Tile_AttrTable+4 # XXX Tile_AttrTable is a bunch of allocated space that data gets copied in to at the start of the level; doing this differnetly, for now; If tile index is less than value in Tile_AttrTable (not solid for wall/ceiling), jump to PRG008_A7AD
# warn "tile ``$a'' above head is solid: " . $tile_properties{ $a }->{solid_bottom};

        goto PRG008_A7AD if ! $tile_properties{ $a }->{solid_bottom}; # $y = 0 for feet; sdw, goto if we haven't hit our head; continue on if we have hit our head
        
        $a = $Player_InAir | $Player_InWater; # | $Level_PipeMove; XXX
        goto PRG008_A7AD if $a != 0;   # If Player is mid air, in water, or moving in a pipe, jump to PRG008_A7AD

        # Solid tile at Player's head; Player is stuck in a low clearance (or worse stuck in the wall!)

        # A is logically zero here...
        $a = 0; # sdw:  doesn't hurt to make sure

        # Stop Player horizontally, disable controls
        $Player_XVel = $a;
        $Pad_Input = $a;

        $a &= ~ $PAD_A;
        $Pad_Input = $a;   # ?? it's still zero?

        $a = 0x01;
        $Player_LowClearance = $a;         # Player_LowClearance = 1 (Player is in a "low clearance" situation!)

        # This makes the Player "slide" when he's in a space too narrow
        # $a += $Player_X; 
        # $carry = $a > 255 ? 1 : 0;  $a -= 256 if $a > 255;
        # $Player_X = $a;    # Player_X += 1
        # goto PRG008_A7AD if ! $carry; # not needed
        # $Player_XHi++;       # Otherwise, apply carry    # combine both of these into one variable?  yes.  this is not needed.
        # $Player_X += (1 << 4); # sdw XXXXX temp disabling this; don't like how it interacts with sand.  does work though.

      PRG008_A7AD:

        # This will be used in Level_CheckIfTileUnderwater 
        # as bits 2-3 of an index into Level_MinTileUWByQuad
        # LDA Level_TilesetIdx
        # ASL A
        # ASL A
        # STA <Temp_Var3     ; Temp_Var3 = Level_TilesetIdx << 2
        # $Temp_Var3 = $a;    # sdw, do this tile property check another way

        # $x = 0;             # Checks Temp_Var1 for tile and $40 override bit in UNK_584
        # Level_CheckIfTileUnderwater();

        # Carry is set by Level_CheckIfTileUnderwater if tile was in the
        # "solid floor" region regardless of being "underwater" # XXXX do this another way
        goto PRG008_A7BE if $carry; # BCS PRG008_A7BE     ; If carry set (tile was in solid region), jump to PRG008_A7BE

        # 'Y' is the result of Level_CheckIfTileUnderwater:
        # 0 = Not under water, 1 = Underwater, 2 = Waterfall
        # TYA         
        # BNE PRG008_A812     ; If Y <> 0 (somehow under water), jump to PRG008_A812

      PRG008_A7BE:

        # NOT underwater!

        $a = $Player_InWater;
        goto PRG008_A827 if $a == 0;     # If Player was not previously in water, jump to PRG008_A827

        $a = $Player_InAir;
        goto PRG008_A7CB if $a != 0;     # If Player is mid air, jump to PRG008_A7CB

        # Player is NOT flagged as mid air...

        goto PRG008_A827 if $carry;     # If tile was in the floor solid region, jump to PRG008_A827
        goto PRG008_A80B if ! $carry;   # If tile was NOT in the floor solid region, jump to PRG008_A80B

      PRG008_A7CB:

        # Player is known as mid air!

        goto PRG008_A7D1 if $carry;    # If tile was in floor solid region, jump to PRG008_A7D1

        $a = $Player_YVel;
        goto PRG008_A7E2 if $a < 0;    # If Player's Y velocity < 0 (moving upward), jump to PRG008_A7E2

      PRG008_A7D1:

        # Player's Y velocity >= 0...
        # OR Player just hit a solid tile with the head

        $a = $carry ? 0x80 : 0x00;   # The important concept here is to save the previous carry flag
        $Temp_Var16 = $a;            # Temp_Var16 (most importantly) contains the previous carry flag in bit 7

        $x = 0x01;                   # Checks Temp_Var2 for tile and $80 override bit in UNK_584
        Level_CheckIfTileUnderwater();

        goto PRG008_A7DE if $carry;  # If tile was in the floor solid region, jump to PRG008_A7DE
        $a = $y;
        goto PRG008_A80B if $a == 0; # If Y = 0 (Not underwater), jump to PRG008_A80B

      PRG008_A7DE:
        $a = $Temp_Var16;
        goto PRG008_A812 if $a < 0 or $a & 0x80; # If we had a floor solid tile in the last check, jump to PRG008_A812; sdw: bit 7 was set to mark it negative

        # Did NOT hit a solid floor tile with head last check

      PRG008_A7E2:
        $y = $Player_YVel;
        goto PRG008_A7EA if $y > - 0x0c;   # If Player_YVel >= -$0C, jump to PRG008_A7EA

        # Prevent Player_YVel from being less than -$0C
        $y = - 0x0C;

      PRG008_A7EA:
        $a = $Counter_1 & 0x07;
        goto PRG008_A7F1 if $a != 0;
        $y++;         # 1:8 chance velocity will be dampened just a bit

      PRG008_A7F1:
        $Player_YVel = $y;    # Update Player_YVel

        $a = $Pad_Input & ~ $PAD_A;
        $Pad_Input = $a;     # Strip out 'A' button press

        $y = $Pad_Holding;
        $a = $y;          # Y = Pad_Holding

        $a &= ~ $PAD_UP;  # Strip out 'Up'
        $Pad_Holding = $a; 

        $y = $a;
        $a &= ( $PAD_UP | $PAD_A );
        goto PRG008_A827 if $a != ( $PAD_UP | $PAD_A ); # If Player is not pressing UP + A, jump to PRG008_A827

        # Player wants to exit water!
        $a = - 0x34;
        $Player_YVel = $a;   # Player_YVel = -$34 (exit velocity from water)

      PRG008_A80B:

        # Player NOT marked as "in air" and last checked tile was NOT in the solid region
        # OR second check tile was not underwater

        $y = 0;
        $Player_SwimCnt = $y;    # Player_SwimCnt = 0
        goto PRG008_A819;        # Jump (technically always) to PRG008_A819

      PRG008_A812:

        # Solid floor tile at head last check

        $y = $Temp_Var15;
        goto PRG008_A827 if $y == $Player_InWater;   # If Player_InWater = Temp_Var15 (underwater flag = underwater status), jump to PRG008_A827

      PRG008_A819:

        # Player's underwater flag doesn't match the water he's in...

        $a = $y;
        $a |= $Player_InWater;
        $Player_InWater = $y;
        goto PRG008_A827 if $a == 0x02;    # If it equals 2, jump to PRG008_A827; sdw, thanks for that useful comment, asshole

        # JSR Player_WaterSplash     ; Hit water; splash! XXX

      PRG008_A827:

       # Player not flagged as "under water"
       # Player not flagged as "mid air" and last checked tile was in solid region

       $a = $Player_FlipBits & 0b01111111;
       $Player_FlipBits = $a;                 # Clear vertical flip on sprite XXXXX use this to select left/right animation sets

       # $y = $Level_TilesetIdx;     # Y = Level_TilesetIdx XXX
       # $a = #TILEA_DOOR2;
       # SUB <Temp_Var1    
       # BEQ PRG008_A83F     ; If tile is DOOR2's tile, jump to PRG008_A83F

       # Only fortresses can use DOOR1
       # CPY #$01
       # BNE PRG008_A86C     ; If Level_TilesetIdx <> 1 (fortress style), jump to PRG008_A86C

       # CMP #$01
       goto PRG008_A86C; # XXX # BNE PRG008_A86C     ; If tile is not DOOR1, jump to PRG008_A86C

     # PRG008_A83F:

       # DOOR LOGIC

       # LDA <Pad_Input
       # AND #PAD_UP
       # BEQ PRG008_A86C     ; If Player is not pressing up in front of a door, jump to PRG008_A86C

       # LDA <Player_InAir
       # BNE PRG008_A86C     ; If Player is mid air, jump to PRG008_A86C

       # If Level_PipeNotExit is set, we use Level_JctCtl = 3 (the general junction)
       # Otherwise, a value of 1 is used which flags that pipe should exit to map

       # LDY #$01    ; Y = 1

       # LDA Level_PipeNotExit
       # BEQ PRG008_A852     ; If pipe should exit to map, jump to PRG008_A852

       # LDY #$03     ; Otherwise, Y = 3

     # PRG008_A852:
       # STY Level_JctCtl ; Set appropriate value to Level_JctCtl

       # LDY #0
       # STY Map_ReturnStatus     ; Map_ReturnStatus = 0

       # STY <Player_XVel     ; Player_XVel = 0

       # LDA <Player_X
       # AND #$08
       # BEQ PRG008_A864     ; If Player is NOT halfway across door, jump to PRG008_A864

       # LDY #16         ; Otherwise, Y = 16

     # PRG008_A864:
       # TYA    
       # ADD <Player_X     ; Add offset to Player_X if needed
       # AND #$F0     ; Lock to nearest column (place directly in doorway)
       # STA <Player_X     ; Update Player_X

    PRG008_A86C:

      # VINE CLIMBING LOGIC; sdw: skips to here after it rules out a door entrence

      # LDA Player_InWater
      # ORA Player_IsHolding
      # ORA Player_Kuribo
      # BNE PRG008_A890     ; If Player is in water, holding something, or in Kuribo's shoe, jump to PRG008_A890
      goto PRG008_A890; # XXX

      # LDA <Temp_Var1
      # CMP #TILE1_VINE
      # BNE PRG008_A890     ; If tile is not the vine, jump to PRG008_A890

      # LDA Player_IsClimbing
      # BNE PRG008_A898     ; If climbing flag is set, jump to PRG008_A898

      # LDA <Pad_Holding
      # AND #(PAD_UP | PAD_DOWN)
      # BEQ PRG008_A890     ; If Player is not pressing up or down, jump to PRG008_A890

      # LDY <Player_InAir
      # BNE PRG008_A898     ; If Player is in the air, jump to PRG008_A898

      # AND #%00001000
      # BNE PRG008_A898     ; If Player is pressing up, jump to PRG008_A898

    PRG008_A890:
      $a = 0;
      $Player_IsClimbing = $a;      # Player_IsClimbing = 0 (Player is not climbing)
      goto PRG008_A8F9;             # Jump to PRG008_A8F9

    PRG008_A898:
      $a = 0x01;
      $Player_IsClimbing = 1;       # Player_IsClimbing = 1 (Player is climbing)

      # Kill Player velocities
      $a = 0x00;
      $Player_XVel = $a;
      $Player_YVel = $a;

      $y = 0x10;     # Y = $10 (will be Y velocity down if Player is pressing down)

      $a = $Pad_Holding & ($PAD_UP | $PAD_DOWN);
      goto PRG008_A8CA if $a != 0;                # If Player is not pressing up or down, jump to PRG008_A8CA

      # Player is pressing UP or DOWN...

      $a &= $PAD_UP;
      goto PRG008_A8C8 if $a == 0;    # If Player is NOT pressing UP, jump to PRG008_A8C8

      # Player is pressing UP...

      $y = 16;
      $a = $Player_Suit;
      goto PRG008_A8B7 if $a == 0;  # If Player is small, jump to PRG008_A8B7

      $y = 0;           #  Otherwise, Y = 0

    PRG008_A8B7:
    
      $Temp_Var10 = $y;     # Temp_Var10 = 16 or 0 (if small) (Y Offset for Player_GetTileAndSlope)

      $a = 0x08;
      $Temp_Var11 = $a;     # Temp_Var11 = 8 (X Offset for Player_GetTileAndSlope)

      Player_GetTileAndSlope();    # Get tile; sdw: this is the block directly behind the player's body or, if he's large, behind his torso/head; it doesn't correspond to any of the Level_Tile_Array positions

      # goto PRG008_A8CA if $a != #TILE1_VINE; # XXX constant  # If tile is NOT another vine, jump to PRG008_A8CA
      goto PRG008_A8CA; # sdw XXX okay, let's just say that the tile isn't another vine; XXX jump-fly-flutter detects InAir

      $y = - 0x10;
      $Player_InAir = $y;      # Flag Player as "in air"

    PRG008_A8C8:
      $Player_YVel = $y;       # Set Player's Y Velocity

    PRG008_A8CA:
      $y = 0x10;     # Y = $10 (rightward X velocity)

      $a = $Pad_Holding & ($PAD_LEFT | $PAD_RIGHT);
      goto PRG008_A8DA if $a == 0;   # If Player is NOT pressing LEFT or RIGHT, jump to PRG008_A8DA

      $a &= $PAD_LEFT;
      goto PRG008_A8D8 if $a == 0;    # If Player is NOT pressing LEFT, jump to PRG008_A8D8

      $y = - 0x10;

    PRG008_A8D8:
      $Player_XVel = $y;   # Set Player's X Velocity

    PRG008_A8DA:
      $a = $Player_IsClimbing;
      goto PRG008_A8EC if $a == 0;      # If Player is NOT climbing, jump to PRG008_A8EC

      # Player is climbing...

      $a = $Player_InAir;
      goto PRG008_A8EC if $a != 0;C     # If Player is in air, jump to PRG008_A8EC

      $a = $Pad_Holding & ($PAD_UP | $PAD_DOWN);
      goto PRG008_A8EC if $a != 0;     # If Player is pressing UP or DOWN, jump to PRG008_A8EC

      $Player_IsClimbing = $a;     # Set climbing flag

    PRG008_A8EC:

      # Apply Player's X and Y velocity for the vine climbing
      Player_ApplyXVelocity();
      Player_ApplyYVelocity();

      # Player_DoClimbAnim();     # Animate climbing XXX
      # Player_Draw();     # Draw Player XXX
      return; # RTS         # Return

    PRG008_A8F9:

      # Player not climbing...

      $a = $Player_SlideRate;
      goto PRG008_A906 if $a == 0;      # If Player sliding rate is zero, jump to PRG008_A906

      # Otherwise, apply it
      $a = $Player_XVel + $Player_SlideRate;
      $Player_XVel = $a;

    PRG008_A906:
      Player_ApplyXVelocity();     # Apply Player's X Velocity

      $a = $Player_SlideRate;    
      goto PRG008_A916 if $a == 0;     # If Player is not sliding, jump to PRG008_A916

      # Otherwise, apply it AGAIN; sdw, no, unapply it after having used it in Player_ApplyXVelocity() once
      $a = $Player_XVel - $Player_SlideRate;
      $a = $Player_XVel;

    PRG008_A916:

      $a = 0x00;
      $Player_SlideRate = $a;     # Player_SlideRate = 0 (does not persist)

      $y = 0x02;     # Y = 2 (moving right)

      $a = $Player_XVel;
      goto PRG008_A925 if $a > 0; # If Player's X Velocity is rightward, jump to PRG008_A925

      $a = - $a;                  # Negate X Velocity (get absolute value)
      $y--;                       # Y = 1 (moving left)

    PRG008_A925:
      goto PRG008_A928 if $a != 0;    # If Player's X Velocity is not zero (what is intended by this check), jump PRG008_A928

      # Player's velocity is zero
      $y = $a;         # And thus, so is Y (not moving left/right)

    PRG008_A928:
      $Temp_Var3 = $a;     # Temp_Var3 = absolute value of Player's X Velocity
      $Player_MoveLR = $y; # Set Player_MoveLR appropriately
      $a = $Player_InAir; 
      goto PRG008_A940 if $a == 0;   # If Player is not mid air, jump to PRG008_A940
      # $a = $Player_YHi; # XXX
      goto PRG008_A93D; # goto PRG008_A93D if( ($Player_Y>>4) < $app->h/2);  # BPL PRG008_A93D     # If Player is on the upper half of the screen, jump to PRG008_A93D; hacked up a bit # XXXX disabling this for testing XXXX no, making this always go for testing; alright, this makes jumping work again.  shitty screen position testing was breaking that.

      # Player is mid air, lower half of screen...

      $a = ( $Player_Y >> 4);
      # goto PRG008_A93D if( $a > ($app->h/4)*3 ); # BMI PRG008_A93D     # If Player is beneath the half point of the lower screen, jump to PRG008_A93D; sdw XXX hacked up a bit; also, what is the "half point of the lower screen"? XXXX disabling this for testing for a bit

      $a = $Player_YVel;
      goto PRG008_A940 if $a < 0;     # If Player is moving upward, jump to PRG008_A940

    PRG008_A93D:
      Player_ApplyYVelocity();     # Apply Player's Y velocity

    PRG008_A940:
      # Player_CommonGroundAnims();    # Perform common ground animation routines XXX

      $a = $Player_Kuribo;
      goto PRG008_A94C if $a == 0;      # If Player is not wearing Kuribo's shoe, jump to PRG008_A94C

      # If in Kuribo's shoe...

      $a = 14;         # A = 14 (Kuribo's shoe code pointer) # XXX
      goto PRG008_A956;     # Jump (technically always) to PRG008_A956 # XXX

    PRG008_A94C:
      $a = $Player_Suit;

      $y = $Player_InWater;
      goto PRG008_A956 if $y == 0;    # If Player is not under water, jump to PRG008_A956

      $a += 0x07;                     # Otherwise, add 7 (underwater code pointers)

    PRG008_A956:

      # ASL A         # 2-byte pointer; sdw; not needed
      $y = $a; 

      # MOVEMENT LOGIC PER POWER-UP / SUIT

      # NOTE: If you were ever one to play around with the "Judgem's Suit"
      # glitch power-up, and wondered why he swam in the air and Kuribo'ed
      # in the water, here's the answer!

      # Get proper movement code address for power-up 
      # (ground movement, swimming, Kuribo's shoe)
      # LDA PowerUpMovement_JumpTable,Y # XXX todo
      # STA <Temp_Var1
      # LDA PowerUpMovement_JumpTable+1,Y
      # STA <Temp_Var2
      # JMP [Temp_Var1]     # Jump into the movement code!
      GndMov_Small(); # XXX for now

    # PowerUpMovement_JumpTable:
      # Ground movement code
      # .word GndMov_Small    # 0 - Small
      # .word GndMov_Big    # 1 - Big
      # .word GndMov_FireHammer    # 2 - Fire
      # .word GndMov_Leaf    # 3 - Leaf
      # .word GndMov_Frog    # 4 - Frog
      # .word GndMov_Tanooki    # 5 - Tanooki
      # .word GndMov_FireHammer    # 6 - Hammer
      # .word Swim_SmallBigLeaf    # 0 - Small  -- Underwater movement code
      # .word Swim_SmallBigLeaf    # 1 - Big
      # .word Swim_FireHammer    # 2 - Fire
      # .word Swim_SmallBigLeaf    # 3 - Leaf
      # .word Swim_Frog        # 4 - Frog
      # .word Swim_Tanooki    # 5 - Tanooki
      # .word Swim_FireHammer    # 6 - Hammer
      # .word Move_Kuribo          # Kuribo's shoe

}

sub GndMov_Small {
      Player_GroundHControl(); # Do Player left/right input control
      Player_JumpFlyFlutter(); # Do Player jump, fly, flutter wag

      # LDA Player_SandSink
      #LSR A         
      #BCS PRG008_A9A3     # If bit 0 of Player_SandSink was set, jump to PRG008_A9A3 (RTS)

      $a = $Player_AllowAirJump;
      goto PRG008_A9A3 if $a != 0;     # If Player_AllowAirJump, jump to PRG008_A9A3 (RTS)

      $a = $Player_InAir;
      goto PRG008_A9A3 if $a == 0;     # If Player is not mid air, jump to PRG008_A9A3 (RTS)

      # Player is mid-air...

      $a = $PF_JUMPFALLSMALL;    # Standard jump/fall frame

      $y = $Player_FlyTime;
      goto PRG008_A9A1 if $y == 0;      # If Player_FlyTime = 0, jump to PRG008_A9A1

      $a = $PF_FASTJUMPFALLSMALL;     # High speed jump frame

    PRG008_A9A1:
      $Player_Frame = $a;             # Set appropriate frame

    PRG008_A9A3:
      return; # RTS
}

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#; Player_GroundHControl
#;
#; Routine to control based on Player's left/right pad input (not
#; underwater); configures walking/running
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_GroundHControl {

    my $moving_left = 0; # XXX hackish

    $a = $Player_UphillFlag;
    goto PRG008_AB56 if $a == 0; # If Player is not going up hill, jump to PRG008_AB56

    $Player_WalkAnimTicks++;

    $y = 10;       # Y = 10 (Player NOT holding B)

    goto PRG008_AB5B if ! ( $Pad_Holding & $PAD_B ); # If Player is NOT holding 'B', jump to PRG008_AB5B

    $y = 1;        # Y = 1 (Player holding B)
    goto PRG008_AB5B;     # Jump (technically always) to PRG008_AB5B

  PRG008_AB56:

    # Use override value
    
    $y = $Player_UphillSpeedIdx;
    goto PRG008_AB62 if $y == 0;     # If Player_UphillSpeedIdx = 0 (not walking uphill), jump to PRG008_AB62

  PRG008_AB5B:
    $a = $Player_UphillSpeedVals->[ $y ];     # Get uphill speed value
    $y = $a;             # -> Y
    goto PRG008_AB83;     # Jump to PRG008_AB83

  PRG008_AB62:
    $y = 24; # $y = #Pad_Input; sdw #Pad_Input seems to be the disassembler being overzealous in trying to replace a constant with a label

    goto PRG008_AB83 if ! ( $Pad_Holding & $PAD_B ); # If Player is NOT holding 'B', jump to PRG008_AB83 

    # Player is holding B...

    $a = $Player_InAir | $Player_Slide;
    goto PRG008_AB78 if $a != 0;    # If Player is mid air or sliding, jump to PRG008_AB78

    $a = $Temp_Var3;   # sdw; this value set in PRG008_A928 in Player_Control
    goto PRG008_AB78 if $a - $PLAYER_TOPRUNSPEED < 0; # If Player's X Velocity magnitude is less than PLAYER_TOPRUNSPEED, jump to PRG008_AB78

    # Player is going fast enough while holding B on the ground; flag running!
    $Player_RunFlag++; # Player_RunFlag = 1

  PRG008_AB78:
    # Start with top run speed
    $y = $PLAYER_TOPRUNSPEED;

    $a = $Player_Power;
    goto PRG008_AB83 if $a - 0x7f != 0;    # If Player has not hit full power, jump to PRG008_AB83

    # Otherwise, top power speed
    $y = $PLAYER_TOPPOWERSPEED;     # Y = PLAYER_TOPPOWERSPEED

  PRG008_AB83:
    $Temp_Var14 = $y;     # Store top speed -> Temp_Var14

    $y = $Player_Slippery;
    goto PRG008_AB98 if $y == 0; # If ground is not slippery at all, jump to PRG008_AB98

    $Player_WalkAnimTicks++;

    $y--;
    $a = $y;
    $a <<= 3;  # sdw: ASL A x 3
    $a += 0x40;
    $y = $a;         # Y = ((selected top speed - 1) << 3) + $40 ??
    goto PRG008_AB9E if $y != 0;     # And as long as that's not zero, jump to PRG008_AB9E

  PRG008_AB98:
    $a = $Player_Suit;
    $a <<= 3;  # sdw: ASL A x 3
    $y = $a;         # Y = Player_Suit << 3
  
  PRG008_AB9E:
    goto PRG008_ABA6 if ! ( $Pad_Holding & $PAD_B);     # BIT <Pad_Holding, BVC PRG008_ABA6 ... If Player is NOT pressing 'B', jump to PRG008_ABA6
    # If Player is NOT pressing LEFT, jump to PRG008_ABA6 

    # Otherwise...
    $y += 4; # Y += 4 (offset 4 inside Player_XAccel* tables)

  PRG008_ABA6:
    $a = $Pad_Holding;
    $a &= ($PAD_LEFT | $PAD_RIGHT);
    goto PRG008_ABB8 if $a != 0;     # If Player is pressing LEFT or RIGHT, jump to PRG008_ABB8

    # Player not pressing LEFT/RIGHT...

    $a = $Player_InAir;
    goto PRG008_AC01 if $a != 0;    # If Player is mid air, jump to PRG008_AC01 (RTS)

    $a = $Player_XVel;
    goto PRG008_AC01 if $a == 0;    # If Player is not moving horizontally, jump to PRG008_AC01 (RTS)
    goto PRG008_ABD3 if $a < 0;     # If Player is moving leftward, jump to PRG008_ABD3
    goto PRG008_ABEB if $a > 0;     # If Player is moving rightward, jump to PRG008_ABEB

  PRG008_ABB8:

    # Player is pressing left/right...
    # sdw: where we branched from, $a is holding $Pad_Holding &'d with ($PAD_LEFT | $PAD_RIGHT)

    $y += 2;    # Y += 2 (offset 2 within Player_XAccel* tables, the "skid" rate)

    $a &= $Player_MoveLR;   # sdw; again: "1 - Moving left, 2 - Moving right (reversed from the pad input)"
    goto PRG008_ABCD if $a != 0;   # If Player suddenly reversed direction, jump to PRG008_ABCD

    $y--;         # Y-- (back one offset, the "normal" rate)

    $a = $Temp_Var3;
    goto PRG008_AC01 if $a - $Temp_Var14 == 0; # If Player's current X velocity magnitude is the same as the selected top speed, jump to PRG008_AC01 (RTS)
    goto PRG008_ABCD if $a - $Temp_Var14 < 0;  # If it's less, then jump to PRG008_AC01

    $a = $Player_InAir;
    goto PRG008_AC01 if $a != 0;   # If Player is mid air, jump to PRG008_AC01

    $y--;         # Y-- (back one offset, the "friction" stopping rate)

  PRG008_ABCD:

    # At this point, 'Y' contains the current power-up in bits 7-3, 
    # bit 2 is set if Player pressed B, bit 1 is set if the above
    # block was jumped, otherwise bit 0 is set if the X velocity is
    # less than the specified maximum, clear if over the max

    $a = $Pad_Holding & $PAD_RIGHT;
    goto PRG008_ABEB if $a != 0; # If Player is holding RIGHT, jump to PRG008_ABEB (moving rightward code)

  PRG008_ABD3:

    $moving_left = 1;
    # XXX then fall through to PRG008_ABEB / Player moving rightward

    # Player moving leftward

    # LDA #$00
    # SUB Player_XAccelPseudoFrac,Y ; Negate value from Player_XAccelPseudoFrac[Y]
    # STA <Temp_Var1    ; -> Temp_Var1
   
    # LDA Player_XAccelMain,Y ; Get Player_XAccelMain[Y]
    # EOR #$ff     ; Negate it (sort of)
    # STA <Temp_Var2   ; -> Temp_Var2
   
    # LDA <Temp_Var1
    # BNE PRG008_ABF5  ; If Temp_Var1 <> 0, jump to PRG008_ABF5
   
    # INC <Temp_Var2   ; Otherwise, Temp_Var2++
    # JMP PRG008_ABF5  ; Jump to PRG008_ABF5

    #$a = $Player_XAccelPseudoFrac->[ $y ];  # Negate value from Player_XAccelPseudoFrac[Y]
    ## $a = - $a XXX
    #$Temp_Var1 = $a;      # -> Temp_Var1

    #$a = $Player_XAccelMain->[ $y ];  # Get Player_XAccelMain[Y]
    ## poke( (\$a + 12), $a ^ 0xffffffff ); # XXX 32bit; 10^0xffffffff = 4294967285, as the IV gets its IsUV bit set, forcing it to be interpreted as an integer; was: EOR #$ff     # Negate it (sort of)
    #$Temp_Var2 = $a;     # -> Temp_Var2

    #$a = $Temp_Var1;
    ## goto PRG008_ABF5 if $a != 0;      # If Temp_Var1 <> 0, jump to PRG008_ABF5

    ## $Temp_Var2++;     # Otherwise, Temp_Var2++; sdw: this finishes the negation; xor 0xffffffff goes from 10 to -11, for example; this puts it back to -10; sdw XXX why it only does this if Player_XAccelPseudoFrac comes back non-zero is a mystery to me; maybe it has to do with increased chance of carry with negative numbers
    # goto PRG008_ABF5;

  PRG008_ABEB:

    # Player moving rightward

    $a = $Player_XAccelPseudoFrac->[ $y ]; # Get value from Player_XAccelPseudoFrac[Y]
    $Temp_Var1 = $a;      # -> Temp_Var1

    $a = $Player_XAccelMain->[ $y ]; # Get value from Player_XAccelMain[Y]
    $Temp_Var2 = $a;      # -> Temp_Var2

  PRG008_ABF5: 
    $a = $Temp_Var1;
    if( abs($a) + $Counter_Wiggly > 255 ) { 
        # actual value not used, looking for a semi-random carry XXX this is tricky as a negative number is far more likely to roll over into carry, hence the abs()
        $carry = 1;
        $a -= 255;
    } else {
        $carry = 0;
    }
    # $carry = - $carry if $Temp_Var1 < 0;

    $a = $Player_XVel;
    if( $moving_left ) {
        $a -= ( $Temp_Var2 + $carry);
    } else {
        $a += $Temp_Var2 + $carry;
    }
    $Player_XVel = $a;    # Player_XVel += Temp_Var2 (and sometimes carry)

  PRG008_AC01:
    return; # RTS         # Return

}

# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# ; Level_CheckIfTileUnderwater
# ;
# ; This checks if the given tile in Temp_Var1/2 (depending on 'X')
# ; is "underwater"...
# ;
# ; CARRY: The "carry flag" will be set and the input tile not
# ; otherwise tested if the tile is in the "solid floor" region!
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Level_CheckIfTileUnderwater { 
    # XXX hacked up
    my $tile = $x ? $Temp_Var1 : $Temp_Var2;
    $a = 0;  # not underwater XXX
    $carry = 0;
# warn "tile ``$a'' solid_top: " . $tile_properties{ $a }->{solid_top};
    $carry = 1 if $tile_properties{ $tile }->{solid_top};
}

sub Player_JumpFlyFlutter {

    $a = $Player_AllowAirJump;
    goto PRG008_AC30 if $a == 0;  #If Player_AllowAirJump = 0, jump to PRG008_AC30

    $Player_AllowAirJump--;

  PRG008_AC30:

    $a = $Pad_Input & $PAD_A;
    $Temp_Var1 = $a;           # Temp_Var1 = $80 if Player is pressing 'A', otherwise 0
    goto PRG008_AC9E if $a == 0; # If Player is NOT pressing 'A', jump to PRG008_AC9E

    $a = $Player_AllowAirJump;
    goto PRG008_AC41 if $a != 0; # If Player_AllowAirJump <> 0, jump to PRG008_AC41

    $a = $Player_InAir;
    goto PRG008_AC9E if $a != 0;    # If Player is mid air, jump to PRG008_AC9E

  PRG008_AC41:

    # Play jump sound
    # LDA Sound_QPlayer
    # ORA #SND_PLAYERJUMP     
    # STA Sound_QPlayer

    $a = $Player_StarInv;
    goto PRG008_AC6C if $a == 0;   # If Player is not invincible by star, jump to PRG008_AC6C

    $a = $Player_Power;
    goto PRG008_AC6C if $a == 0x7f; # If Player is at max power, jump to PRG008_AC6C

    $a = $Player_IsHolding;
    goto PRG008_AC6C if $a != 0;     # If Player is holding something, jump to PRG008_AC6C

    $a = $Player_Suit;
    goto PRG008_AC6C if $a == 0;                   # If Player is small, jump to PRG008_AC6C
    goto PRG008_AC6C if $a == $PLAYERSUIT_FROG;    # If Player is wearing frog suit, jump to PRG008_AC6C

    # Otherwise, mark as mid air AND backflipping
    # $Player_Flip = $a; # XXX
    $Player_InAir = $a;

    $a = 0;
    $Player_AllowAirJump = $a;     # Cut off Player_AllowAirJump

  PRG008_AC6C:

    # Get absolute value of Player's X velocity
    $a = $Player_XVel;
    goto PRG008_AC73 if $a > 0;
    $a = - $a;
  PRG008_AC73:

    $a >>= 4;
    $x = $a;    # X = Magnitude of Player's X Velocity >> 4 (the "whole" part)

    $a = $Player_RootJumpVel;         # Get initial jump velocity
    $a -= $Player_SpeedJumpInc->[ $x ];     # Subtract a tiny bit of boost at certain X Velocity speed levels
    $Player_YVel = $a;         # -> Y velocity

    $a = 0x01;
    $Player_InAir = $a;   # Flag Player as mid air

    $a = 0;
    $Player_WagCount = $a;         # Player_WagCount = 0
    $Player_AllowAirJump = $a;     # Player_AllowAirJump = 0

    $a = $Player_Power;
    goto PRG008_AC9E if $a != 0x7f; # If Player is not at max power, jump to PRG008_AC9E

    $a = $Player_FlyTime;
    goto PRG008_AC9E if $a != 0; # If Player still has flight time left, jump to PRG008_AC9E

    $a = 0x80;
    $Player_FlyTime = $a;    # Otherwise, Player_FlyTime = $80

  PRG008_AC9E:
    $a = $Player_InAir;
    goto PRG008_ACB3 if $a != 0;        # If Player is mid air, jump to PRG008_ACB3

    $y = $Player_Suit;
    $a = $PowerUp_Ability->[$y];    # Get "ability" flags for this power up
    $a &= 0b01;
    goto PRG008_AD1A if $a != 0;       # If power up has flight ability, jump to PRG008_AD1A

    $a = 0;
    $Player_FlyTime = 0;    # Otherwise, Player_FlyTime = 0 :(
    goto PRG008_AD1A;     # Jump to PRG008_AD1A

  PRG008_ACB3:

    # Player is mid air...

    $y = 5;     # Y = 5

    $a = $Player_YVel;
    goto PRG008_ACC8 if $a >= - 0x20;      # If Player's Y velocity >= -$20, jump to PRG008_ACC8

    $a = $Player_mGoomba;
    goto PRG008_ACCD if $a != 0;      # If Player has got a microgoomba stuck to him, jump to PRG008_ACCD

    $a = $Pad_Holding;
    goto PRG008_ACC8 if ! ( $a & $PAD_A );   # If Player is NOT pressing 'A', jump to PRG008_ACC8; was using BPL to test that bit 7 was 0

    $y = 1;     # Y = 1
    goto PRG008_ACCD;      # Jump (technically always) to PRG008_ACCD

  PRG008_ACC8:
    $a = 0;
    $Player_mGoomba = 0; # Player_mGoomba = 0

  PRG008_ACCD:
    $a = $y;
    $a += $Player_YVel;
    $Player_YVel = $a; # Player_YVel += Y

    $a = $Player_WagCount;
    goto PRG008_ACD9 if $a == 0;    #  If Player_WagCount = 0, jump to PRG008_ACD9

    $Player_WagCount--; # Otherwise, $F0--

  PRG008_ACD9:
    $a = $Player_Kuribo;
    goto PRG008_ACEF if $a != 0; # If Player is wearing Kuribo's shoe, jump to PRG008_ACEF

    $x = $Player_Suit;

    $a = $PowerUp_Ability->[ $x ];    # Get "ability" flags for this power up
    $a &= 0b0001;
    goto PRG008_ACEF if $a == 0;          # If this power up does not have flight, jump to PRG008_ACEF

    $y = $Temp_Var1;        # Y = $80 if Player was pressing 'A' when this all began
    goto PRG008_ACEF if $y == 0; # And if he wasn't, jump to PRG008_ACEF

    $a = 0x10;
    $Player_WagCount = $a;     # Otherwise, Player_WagCount = $10

  PRG008_ACEF:
    $a = $Player_WagCount;
    goto PRG008_AD1A if $a == 0; # If Player has not wag count left, jump to PRG008_AD1A

    # RACCOON / TANOOKI TAIL WAG LOGIC

    $a = $Player_YVel;
    goto PRG008_AD1A if $a < $PLAYER_FLY_YVEL; # If Player's Y velocity is < PLAYER_FLY_YVEL, jump to PRG008_AD1A

    $y = $PLAYER_FLY_YVEL;     # Y = PLAYER_FLY_YVEL

    $a = $Player_FlyTime;
    goto PRG008_AD0E if $a == 0; # If Player is not flying, jump to PRG008_AD0E

    goto PRG008_AD18 if $a >= 0x0f; # If Player has a great amount of flight time left, jump to PRG008_AD18

    # Player has a small amount of flight time left

    $y = 0xF0;
    $a &= 0x08;
    goto PRG008_AD18 if $a != 0; # Every 8 ticks, jump to PRG008_AD18

    $y = 0;     # Y = 0 (at apex of flight, Player no longer rises)
    goto PRG008_AD18;     # Jump (technically always) to PRG008_AD18

  PRG008_AD0E:
    $a =  $Player_YVel;
    goto PRG008_AD1A if $a < 0;      # If Player's Y velocity < 0 (moving upward), jump to PRG008_AD1A

    goto PRG008_AD1A if $a < $PLAYER_TAILWAG_YVEL; # If Player's Y velocity < PLAYER_TAILWAG_YVEL, jump to PRG008_AD1A
    $y = $PLAYER_TAILWAG_YVEL; # Y = PLAYER_TAILWAG_YVEL; sdw, otherwise, cap Y velocity at PLAYER_TAILWAG_YVEL

  PRG008_AD18:
    $Player_YVel =  $y; # Set appropriate Y velocity

  PRG008_AD1A:
    $a = $Player_UphillSpeedIdx;
    goto PRG008_AD2E if $a == 0;      # If Player_UphillSpeedIdx = 0 (not walking uphill), jump to PRG008_AD2E

    $a >>= 1;
    $y = $a;         # Y = Player_UphillSpeedIdx >> 1

    $a = $Player_YVel;
    goto PRG008_AD2E if $a >= 0; # If Player's Y vel >= 0, jump to PRG008_AD2E (RTS)

    goto PRG008_AD2E if $a < $PRG008_AC22->[ $y ]; # If Player's uphill speed < Y velocity, jump to PRG008_AD2E

    $a = 0x20;
    $Player_YVel = $a; # Player_YVel = $20

  PRG008_AD2E:
    return; # RTS
}


##;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
## Player_ApplyYVelocity
##   
## Applies Player's Y velocity and makes sure he's not falling
## faster than the cap value (FALLRATE_MAX)
##;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_ApplyYVelocity {
    $a = $Player_YVel;
    goto PRG008_BFF9 if $a < 0;  # If Player_YVel < 0, jump to PRG008_BFF9
    
    goto PRG008_BFF9 if $a < $FALLRATE_MAX;  # BLS PRG008_BFF9  # If Player_YVelo < FALLRATE_MAX, jump to PRG008_BFF9
    
    # Cap Y velocity at FALLRATE_MAX
    $a = $FALLRATE_MAX;
    $Player_YVel = $a; # Player_YVel = FALLRATE_MAX

  PRG008_BFF9:
    $x = 1; # LDX #(Player_YVel - Player_XVel) # Do the Y velocity # pointer arith; sdw, not actually 1, but faking it
    Player_ApplyVelocity();     # Apply it!
    
    # RTS      # Return
}

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# Player_ApplyXVelocity
#
# Applies Player's X velocity and makes sure he's not moving
# faster than the cap value (PLAYER_MAXSPEED)
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_ApplyXVelocity {
    $x = 0;    # X = 0
    $y = $PLAYER_MAXSPEED;    # Y = PLAYER_MAXSPEED
   
    $a = $Player_XVel;
    goto PRG008_BFAC if $a >= 0; # BPL PRG008_BFAC  # If Player_XVel >= 0, jump to Player_ApplyXVelocity
   
    $y = - $PLAYER_MAXSPEED;    # Y = -PLAYER_MAXSPEED
 
    # Negate Player_XVel (get absolute value)
    $a = - $a;

  PRG008_BFAC:
    $Temp_Var16 = $a;     # Store absolute value Player_XVel -> Temp_Var16
    goto &Player_ApplyVelocity if $a < $PLAYER_MAXSPEED; # BLS Player_ApplyVelocity # If we haven't hit the PLAYER_MAXSPEED yet, apply it!
    $Player_XVel = $y;     # Otherwise, cap at max speed!

    # falls through to Player_ApplyVelocity
    goto &Player_ApplyVelocity;

}

##;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
## Player_ApplyVelocity
##
## Applies Player's velocity for X or Y (depending on register 'X')
##;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_ApplyVelocity {
    $Player_X += ($Player_XVel + $Player_XVelAdj) if $x == 0; # sdw, in the game, 4 bits of Player_YVel and Player_XVel are fractional; but that's okay because so are the flast four bits fo $Player_X and $Player_Y
    $Player_Y += $Player_YVel if $x > 0;
}

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#; Player_GetTileAndSlope
#;   
#; Gets tile and attribute of tile for either non-vertical or
#; vertical levels based on Player's position
#;
#; Temp_Var10 is a Y offset (e.g. 0 for Player's feet, 31 for Player's head)
#; Temp_Var11 is an X offset
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_GetTileAndSlope {
    my $y = ($Player_Y >> 4) + $Temp_Var10;
    my $x = ($Player_X >> 4) + $Temp_Var11;
    $x >>= 4; # again; go from pixels to tiles, and tiles at 16 pixels wide
    $y >>= 4; # ditto
    # X/Y were not modified, so as inputs:
    # X = 0 (going down) or 1 (going up)
    # Y = Player_YVel
    #     JSR Player_GetTileAndSlope_Normal    ; Set Level_Tile and Player_Slopes; ... this sets Level_Tile and A
    # JSR Player_GetTileV  ; Get tile, set Level_Tile
    $a = $map->[$x]->[$y]; # XXX okay, where do we stick this?  A, it looks like, and $Level_Tile too, but so far, it's only a temp nothing uses
# warn "-->$a<-- Player_GetTileAndSlope for delta $Temp_Var11, $Temp_Var10";
}


# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# ; Player_DetectSolids
# ;
# ; Handles Player's collision against solid tiles (wall and ground,
# ; handles slopes and sliding on them too!)
# ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Player_DetectSolids {

	$a = 0;
	$Player_HitCeiling = $a; # Clear Player_HitCeiling

	$a = $Level_PipeMove;
    goto PRG008_B47E if $a == 0;     # If not going through a pipe, jump to PRG008_B47E
    return;

  PRG008_B47E:
    # $a = $Slope_LUT_Addr;
    # $Level_GndLUT_Addr = $a;

    # LDA Slope_LUT_Addr+1
    # STA <Level_GndLUT_Addr+1

    # LDA Level_SlopeEn
    # BEQ PRG008_B4A5     # If not a sloped level, jump to PRG008_B4A5
    goto PRG008_B4A5; # XXX sdw; skipping the slope stuff, for now

    # LDA Level_Tileset
    # CMP #$03
    # BEQ PRG008_B4A2     # If Level_Tileset = 3 (Hills style), jump to PRG008_B4A2
    # CMP #14
    # BEQ PRG008_B4A2     # If Level_Tileset = 14 (Underground style), jump to PRG008_B4A2

    # Non-sloped levels use this:
    # RAS: NOTE: I don't think this really means anything; this ends up pointing to
    # Level_LayPtrOrig_AddrH (original layout pointer high byte), which doesn't make
    # sense, but Level_GndLUT_Addr/H isn't used in a non-slope level anyway, so this is
    # probably some bit of "dead" code or something...

    # LDA NonSlope_LUT_Addr
    # STA <Level_GndLUT_Addr

    # LDA NonSlope_LUT_Addr+1
    # STA <Level_GndLUT_Addr+1

  # PRG008_B4A2:
    # JMP PRG000_B9D8     # Jump to PRG000_B9D8

  PRG008_B4A5:
    # Slopes not enabled...

    $y = 32 + 6; # LDY #(TileAttrAndQuad_OffsFlat_Sm - TileAttrAndQuad_OffsFlat) + 6    # 6 = 3 * 2 (the offset we start on below) and work backwards from; sdw: 32 moves us from TileAttrAndQuad_OffsFlat to the start of the data for TileAttrAndQuad_OffsFlat_Sm, which got combined into there

    $a = $Player_Suit;
    goto PRG008_B4B2 if $a == 0; # If Player is small, jump to PRG008_B4B2

    $a = $Player_IsDucking;
    goto PRG008_B4B2 if $a != 0;    # If Player is ducking, jump to PRG008_B4B2

    $y = 6;        # 6 = 3 * 2 (the offset we start on below) and work backwards from

  PRG008_B4B2:
    $x = 3;     # X = 3 (the reason for +6 above)

    $a = $Player_YVel; 
    goto PRG008_B4BD if $a >= 0;   # If Player_YVel >= 0 (moving downward), jump to PRG008_B4BD

    # Otherwise, add 16 to index
    $a = $y;
    $a += 16;
    $y = $a;

  PRG008_B4BD:
    $a = $Player_X>>4; # sdw, our $Player_X has the fractal part in it, so chopping that off
    $a &= 0x0f;
    goto PRG008_B4CA if $a < 0x08; # If Player is on the left half of the tile, jump to PRG008_B4CA

    # If on the right half, add 8 to index
    $a = $y;
    $a += 0x08;
    $y = $a;

  PRG008_B4CA:
    $a = $y;
    push @stack, $a; # PHA         # Save offset

    # Get X/Y offset for use in detection routine
    $a = $TileAttrAndQuad_OffsFlat->[ $y ];
    $Temp_Var10 = $a;     # Temp_Var10 (Y offset)
    $a = $TileAttrAndQuad_OffsFlat->[ $y + 1 ]; 
    $Temp_Var11 = $a;     # Temp_Var11 (X offset)

    Player_GetTileAndSlope();     # Get tile
    ${ $Level_Tile_Array->[ $x + 1 ] } = $a;    # STA Level_Tile_GndL,X     # Store i; sdw Level_Tile_GndL is at offset 1 in the array, so +1

    $Level_Tile_Positions->[ $x + 1 ] = [ ($Player_X >> 4) + $Temp_Var11, ($Player_Y >> 4) + $Temp_Var10  ]; # hacked up

    push @stack, $a;  # PHA         # Save tile

    # AND #%11000000     # Get quadrant XXX sdw todo
    # ASL A         
    # ROL A         
    # ROL A         #
    # STA Level_Tile_Quad,X     # Store quadrant number

    $a = pop @stack; # PLA         # Restore tile

    Level_DoCommonSpecialTiles();     # Handle tile apporiately

    $a = pop @stack; # PLA         
    $y = $a;  # TAY         # Restore 'Y' index
    $y -= 2;  # Y -= 2 (next pair of offsets)

    $x--;

    goto PRG008_B4F3 if $x < 0;     # If X < 0, jump to PRG008_B4F3
    goto PRG008_B4CA;     # Otherwise, loop!

  PRG008_B4F3:
    # Wall hit detection
    $y = 2;     # Y = 2 (checking "in front" tiles, lower and upper)

    Level_CheckGndLR_TileGTAttr();
    goto PRG008_B53B if ! $carry;     # If not touching a solid tile, jump to PRG008_B53B; sdw, this counts as the ceiling collision

    $a = $Player_LowClearance;
    goto PRG008_B53B if $a != 0;      # If Player_LowClearance is set, jump to PRG008_B53B

    $Player_WalkAnimTicks++;

    $y = 1;
    $x = 0;

    $a = $Player_X >> 4; # sdw, chop off fractional bits
    $a &= 0x0f;
    goto PRG008_B511 if $a >= 0x08; # If Player is on the right side of the tile, jump to PRG008_B511

    # Otherwise...
    $y = -1;
    $x++;         # X = 1

  PRG008_B511:
    $a = $Player_Suit;
    goto PRG008_B517 if $a != 0;    # If Player is NOT small, jump to PRG008_B517

    $x += 2;         # X += 2 (X = 2 or 3)

  PRG008_B517:
    $a = $PRG008_B3AC->[ $x ];
    $a += ( $Player_X >> 4 ); # sdw, added the >>4    # Add appropriate offset to Player_X

    $a &= 0x0f;
    goto PRG008_B53B if $a == 0;     # If Player is on new tile, jump to PRG008_B53B (sdw: that's the not-a-hit condition)

    $a = $y;         # A = 1 or -1; sdw: -1 if player is on right side of the tile, 1 otherwise

    $Player_X = $a * (1<<4) + $Player_X; # deal with $Player_X<<4 stuff # ADD <Player_X     # Add +1/-1 to Player_X # STA <Player_X     # Update Player_X
    # $a = $Player_X>>4; # sdw, without fractal part into $a, if the code were to actually use that value

    $y++;

    $a = $Player_XVel;
    goto PRG008_B536 if $a >= 0; # If Player_XVel >= 0, jump to Player_XVel

    # This basically amounts to a single decrement of 'Y' if Player_XVel < 0
    $y -= 2;

  PRG008_B536:
    $a = $y;
    goto PRG008_B53B if $a != 0; # If Y <> 0, jump to PRG008_B53B  (sdw: that's the not-a-hit condition)

    $Player_XVel  = $a; # Otherwise, halt Player horizontally

  PRG008_B53B:
    # sdw: this is where stuff branches to when the player did not run into a solid tile side to side (X axis)
    $a = $Player_YVel;
    goto PRG008_B55B if $a >= 0;    # If Player Y velocity >= 0 (moving downward), jump to PRG008_B55B

    $a = $Player_InAir;
    goto PRG008_B55B if $a == 0;    # If Player is NOT mid air, jump to PRG008_B55B; sdw, that is, if he isn't marked as mid-air, but we're going to check again

    $y = 0;     # Y = 0

    Level_CheckGndLR_TileGTAttr();
    goto PRG008_B55A if ! $carry;   # If not touching a solid tile, jump to PRG008_B55A; sdw: not touching a solid tile with our feet... except that when we're heading upwards, the slot for checking feet becomes above our head, so it's really misnamed

    $y++;         # Y = 1
    $Player_HitCeiling = $y;    # Flag Player as having just hit head off ceiling

    # LDA Level_AScrlVVel    # Get autoscroll vertical velocity # XXX
    # JSR Negate     # Negate it
    # BPL PRG008_B558     # If positive, jump to PRG008_B558

    # Otherwise, just use 1
    # LDA #$01    

  # PRG008_B558:
    # STA <Player_YVel # Update Player_YVel
    $Player_YVel = 1;

  PRG008_B55A:
    return;

  PRG008_B55B:
    # sdw: check tiles to see if the player is in mid-air or landed
    # LDX Level_Tile_Quad+1     # Get right tile quadrant
    $a = $Level_Tile_GndR;     # Get right tile
    # CMP Tile_AttrTable,X    
    # BGE PRG008_B57E          # If the tile is >= the attr value, jump to PRG008_B57E; sdw, branch if the tile is solid
    goto PRG008_B57E if $tile_properties{ $a }->{solid_top};

    # LDX Level_Tile_Quad     # Get left tile quadrant
    $a = $Level_Tile_GndL;     # Get left tile
    # CMP Tile_AttrTable,X    
    # BGE PRG008_B57E          # If the tile is >= the attr value, jump to PRG008_B57E; sdw, branch if the tile is solid
    goto PRG008_B57E if $tile_properties{ $a }->{solid_top};

    $a = $Player_InAir;
    goto PRG008_B5BB if $a != 0;    # If Player is mid air, jump to PRG008_B5BB

    # Otherwise...

# warn "halted player vertically";
    $Player_YVel = $a; # Halt Player vertically

    $a = 1; 
    $Player_InAir = $a; # Mark Player as mid air

    goto PRG008_B5BB;     # Jump to PRG008_B5BB

  PRG008_B57E:
    # sdw, sent here when either of the players feet are on a solid topped tile
    $a = $Temp_VarNP0; # XXX this var not used or set before here; hope it doesn't have an important value it's initialized to
    goto PRG008_B59C if $a == 0;       # If did not use "high" Y last call to Player_GetTileAndAttr, jump to PRG008_B59C

    # sdw: hacked this up a bit to deal with preserving the fractal part that we merged into $Player_Y
    # sdw: also, it currently won't ever run as $Temp_VarNP0 is stuck at 0
    $a = ( $Player_Y >> 4);         # Get Player Y
    # SUB Level_VertScroll    # Make scroll relative
    $a &= 0xf0; # AND #$F0         # Nearest 16
    $a += 1; # ADD #$01         # +1
    # ADD Level_VertScroll    # Make un-relative
    $Player_Y = ( ($a<<4) | ( $Player_Y & 0b01111) ); # STA <Player_Y        # Set Player_Y!

    # LDA #$00
    # ADC #$00
    # STA <Player_YHi        # Apply carry if needed
    # BPL PRG008_B5B2         # If carry >= 0, jump to PRG008_B5B2; XXX sdw this kills the player.  why?  guess with the VertScroll added in, carry indicates off the bottom of the screen... maybe?

  PRG008_B59C:
    # sdw: this happens when the player is in contact with a solid tile; extra $Player_Y--'s make him bounce in place
    $a = ( $Player_Y >> 4 );
    $a &= 0x0f; # AND #$0f    # Relative to tile vertical position
    # die "a >= 6 XXX" if $a >= 6; # XXX happens when the player gets stuck part way through the ground
    goto PRG008_B5BB if $a >= 6; # If Player's vertical tile position >= 6, jump to PRG008_B5BB; sdw, player stuck in ground XXXXX commenting this out makes the bug where we fall through the floor vanish
    # goto PRG008_B5BB if $a >= 10; # If Player's vertical tile position >= 6, jump to PRG008_B5BB; sdw, player stuck in ground XXXXX commenting this out makes the bug where we fall through the floor vanish; XXX using a higher value for this seems to cure the problem too; XXXX real probably is probably that Mario is falling too fast; yeah, looks like YVel was being added twice, but that actually made jumping work. grr!

    $a = ( $Player_Y >> 4);
    $a &= 0x0f;                       # Relative to tile vertical position
    goto PRG008_B5B2 if $a == 0;      # If zero, jump to PRG008_B5B2; sdw, player is exactly on the ground; mark him as landed

    goto PRG008_B5B0 if $a == 1; # If 1, jump to PRG008_B5B0; sdw, player is one pixel into the ground; move up him and mark him as landed

    # sdw: this would happen with values from 2-5; inch the player upwards a little
    $Player_Y -= (1<<4);     # Player_Y--

  PRG008_B5B0:
    $Player_Y -= (1<<4);     # Player_Y--

  PRG008_B5B2:
    # sdw:  the player hit the ground
    $a = 0;
    $Player_InAir = 0; # Player NOT mid air
    $Player_YVel = 0;  # Halt Player vertically
    $Kill_Tally = 0;   # Reset Kill_Tally

  PRG008_B5BB:
    return;         # Return

}

# This checks if the given tile is greater-than-or-equal-to
# the related "AttrTable" slot and, if so, returns 'carry set'
# sdw: carry set indicates that we're touching a solid
# sdw: Y is index into $Level_Tile_Array (not relative to the beginning but starting at _GndL and _GndR) 
# sdw: XXX since this uses the same offset into the Tile_AttrTable and into $Level_Tile, I think this means that head, feet, side of player each have different values that tile numbers are compared to; what I've read supports this
# sdw: likely, Y is either 0 to check GndL and GndR, or is 2 to check InFL, InFU; yup, comments in the code back this up
# sdw: solid_top is checked in two other places, including Level_CheckIfTileUnderwater; this routine is only called to check
# sdw: if we've hit our head while going up, or if we're running into a wall while going forward

sub Level_CheckGndLR_TileGTAttr {

    # LDX Level_Tile_Quad+1,Y # Get this particular "quad" (0-3) index
    $a = ${ $Level_Tile_Array->[ $y + 2 ] };       # LDA Level_Tile_GndR,Y # Check the tile here; sdw, it goes _Head, _GndL, _GndR, _InFL, then _InFU (in front lower, in front upper), and it was starting at Level_Tile_GndR, so +2 skips ahead in the array to match the ponter arith
    # CMP Tile_AttrTable+4,X # XXXXXXX X indicates which attribute to check
    # BGE PRG008_B5D0         # If the tile is >= the attr value, jump to PRG008_B5D0 (NOTE: Carry set when true)

    # LDX Level_Tile_Quad,Y       # Get this particular "quad" (0-3) index
    $a = ${ $Level_Tile_Array->[ $y + 1 ] };       # LDA Level_Tile_GndL,Y # Check the tile here; sdw, was relative to Level_Tile_GndL, which is +1 in $Level_Tile
    # CMP Tile_AttrTable+4,X      # Set carry if tile is >= the attr value XXXX X indicates which attribute to check

    my $tile1 = ${ $Level_Tile_Array->[ $y + 2 ]; };       # as above
    my $tile2 = ${ $Level_Tile_Array->[ $y + 1 ]; };      # as above

    $carry = 0;
    # $carry = 1 if $y == 0 and ( $tile_properties{ $tile1 }->{solid_top} or $tile_properties{ $tile2 }->{solid_top} ); # $y = 0 for feet (or head if we're moving upwards!) # XXX
    $carry = 1 if $y == 0 and ( $tile_properties{ $tile1 }->{solid_bottom} or $tile_properties{ $tile2 }->{solid_bottom} ); # $y = 0 for feet (or head if we're moving upwards!)
    $carry = 1 if $y == 2 and ( $tile_properties{ $tile1 }->{solid_bottom} or $tile_properties{ $tile2 }->{solid_bottom} ); # $y = 2 for front; solid bottom and solid sides are the same thing

# warn "tile ``$tile1'' with y=$y is solid top: " . $tile_properties{ $tile1 }->{solid_top} . " an solid bottom: " . $tile_properties{ $tile1 }->{solid_bottom};
# warn "tile ``$tile2'' with y=$y is solid top: " . $tile_properties{ $tile2 }->{solid_top} . " an solid bottom: " . $tile_properties{ $tile2 }->{solid_bottom};
# warn "Level_CheckGndLR_TileGTAttr carry = $carry when testing ($y=) " . ( $y == 0 ? "feet" : "front" );

  PRG008_B5D0:

    # NOTE: The return value is "carry set" for true!

    return;      # Return

}

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# Read_Joypads
#
# This subroutine reads the status of both joypads 
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# sdw: this is called from IntNMI

sub Read_Joypads {

	# Read joypads
	$y = 0; # LDY #$01	 # Joypad 2 then 1; sdw, only doing one joypad

  PRG031_FEC0:
    Read_Joypad(); # Read Joypad Y

	# FIXME: I THINK this is for switch debouncing?? sdw, don't need to do this; no, not for debouncing, for dealing with lost bits as explained in http://wiki.nesdev.com/w/index.php/Standard_controller
  # PRG031_FEC3:
    $a = $Temp_Var1;      # Pull result out of $00 -> A
    # push @stack, $a;          # Push A
    # JSR Read_Joypad     # Read Joypad
    # PLA         # Pull A
    # CMP <Temp_Var1     # Check if same
    # BNE PRG031_FEC3     # If not, do it again

    $a |= $Temp_Var2; # ORA <Temp_Var2     #  sdw, not sure what gets read from hardware into $Temp_Var2
    push @stack, $a;          # Push A
    $a &= 0x0f;     # A &= $0F
    $x = $a;          # A -> X
    $a = pop @stack;         # Pull A
    $a &= 0xf0;
    # sdw: not sure what the | $Temp_Var2 is about, but $x gets up/down/left/right and $a gets select/start/A/B

    # warn "a $a x $x Read_Joypads_UnkTable $Read_Joypads_UnkTable->[$x]";
    $a |= $Read_Joypads_UnkTable->[ $x ]; # ORA Read_Joypads_UnkTable,X     # FIXME: A |= Read_Joypads_UnkTable[X]
    push @stack, $a;              # Save A
    $Temp_Var3 = $a;          # Temp_Var3 = A
    $a ^= $Controller1; # EOR Controller1,Y    # sdw XX, ignoring controller 2
    $a &= $Temp_Var3; 
    $Controller1Press = $a; # STA Controller1Press,Y    # Figures which buttons have only been PRESSED this frame as opposed to those which are being held down; sdw XX ignoring controller 2
    $Pad_Input = $a;
    $a = pop @stack;
    $Controller1 = $a; # STA Controller1,Y    # XX ignoring controller 2
    $Pad_Holding = $a;
    # DEY         # Y-- ; sdw XX, only doing one joypad
    # BPL PRG031_FEC0     # If Y hasn't gone negative (it should just now be 0), Read other joypad; sdw XX, only doing one joypad

    # Done reading joypads
    $y = $Player_Current;
    goto PRG031_FF11 if $y == 0;     # If Player_Curren = 0 (Mario), jump to PRG031_FF11

    # sdw:  stuff related to pulling in controller data for Luigi
    #LDA <Controller1
    #AND #$30
    #STA <Temp_Var1
    #LDA <Controller2
    #AND #$cf
    #ORA <Temp_Var1
    #STA <Pad_Holding
    #LDA <Controller1Press
    #AND #$30
    #STA <Temp_Var1
    #LDA <Controller2Press
    #AND #$cf
    #ORA <Temp_Var1
    #STA <Pad_Input

PRG031_FF11:
    return;        # Return
}

#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
# Read_Joypad
#
# This subroutine does some tricky business to read out the joypad
# into Temp_Var1 / Temp_Var2
# Register Y should be 0 for Joypad 1 and 1 for Joypad 2
#;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

sub Read_Joypad {
    # $FF12
    # Joypad reading is weird, and actually requires 8 accesses to the joypad I/O to get all the buttons:
    # Read #1: A 
    #      #2: B 
    #      #3: Select
    #      #4: Start 
    #      #5: Up    
    #      #6: Down  
    #      #7: Left  
    #      #8: Right 

    # This Resets BOTH controllers
    # LDA #$01     # A = 1 (strobe)
    # STA JOYPAD     # Strobe joypad 1 (hi)
    # LSR A         # A = 0 (clear), 1 -> Carry
    # STA JOYPAD     # Clear strobe joypad 1

    # Needs cleanup and commentary, but basically this does 8 loops to
    # read all buttons and store the result for return
    # sdw: http://wiki.nesdev.com/w/index.php/Standard_controller states:
    # The first 8 reads will indicate which buttons are pressed (1 if pressed, 0 if not pressed); all subsequent reads will return D=1 on an authentic controller but may return D=0 on third party controllers.
    # Button status for each controller is returned in the following order: A, B, Select, Start, Up, Down, Left, Right. 
    # sdw:  http://wiki.nesdev.com/w/index.php/Standard_controller doesn't say what bit 1 is
    # LDX #$08     # X = 8
  # Read_Joypad_Loop:
    # LDA JOYPAD,Y     # Get joypad data
    # LSR A                    # sdw: JOYPAD,Y bit 0 -> C
    # ROL <Temp_Var1           # sdw: C -> Temp_Var1 bit 0
    # LSR A                    # sdw: JOYPAD,Y bit 1 -> C
    # ROL <Temp_Var2           # sdw: C -> Temp_Var2 bit 0
    # DEX
    # BNE Read_Joypad_Loop     # Loop until 8 reads complete

    # RTS         # Return

    $Temp_Var2 = 0; # XXX not sure what this would be in real hardware, but it gets |'d against $Temp_Var1

    $Temp_Var1 = 0;
    $Temp_Var1 |= $PAD_A       if $pressed->{A};
    $Temp_Var1 |= $PAD_B       if $pressed->{B};
    $Temp_Var1 |= $PAD_SELECT  if $pressed->{select}; # XXX
    $Temp_Var1 |= $PAD_START   if $pressed->{start}; # XXX
    $Temp_Var1 |= $PAD_UP      if $pressed->{up};
    $Temp_Var1 |= $PAD_DOWN    if $pressed->{down};
    $Temp_Var1 |= $PAD_LEFT    if $pressed->{left};
    $Temp_Var1 |= $PAD_RIGHT   if $pressed->{right};

};

#
# Level_DoCommonSpecialTiles
#

# Handle all common special tiles (ice blocks, P-Switches, bump blocks, etc.)
# Does not include things like instant-kill lava tiles...
# sdw: A contains the tile number of the block we're currently looking at
# sdw: X is the index into our $Level_Tile_Array thing; it tells us where the block is that we're currently looking at
# sdw: the routine calls this one, Player_DetectSolids, loops over $Level_Tile_GndL, $Level_Tile_GndR, $Level_Tile_InFL, $Level_Tile_InFU
# XXX todo

sub Level_DoCommonSpecialTiles {

    $a = $y;                     # TYA         # A = Y (offset into TileAttrAndQuad_OffsSloped)
    push @stack, $a;             # PHA         # Save it

    $y = $Player_Kuribo;         # LDY Player_Kuribo
    goto PRG008_B604 if $y != 0; # BNE PRG008_B604     # If Player is in Kuribo's shoe, jump to PRG008_B604

    # LDA #TILEA_ICEBLOCK # XXX
    # CMP Level_Tile_GndL,X
    goto PRG008_B604; # XXX # BNE PRG008_B604     # If Player is not touching an ice block, jump to PRG008_B604
 
    # # Player is touching an ice block...
    # BIT <Pad_Input
    # BVC PRG008_B604     # If Player is not pushing 'B', jump to PRG008_B604

    # CPX #$03
    # BEQ PRG008_B604     # If tile at head, jump to PRG008_B604

    # LDA Level_ChgTileEvent
    # BNE PRG008_B604     # If Level_ChgTileEvent <> 0 (tile change already queued), jump to PRG008_B604

    # TXA
    # PHA         # Save 'X' (current tile index) 

    # JSR Level_IceBlock_GrabNew # Grab a new ice block object!  (If there's room)

    # # Of note, if there was no room for an Ice Block, X = $FF (-1) right now
    # TXA         # Transfer new object index 'X' -> 'A'
    # ASL A         # Shift left 1 (setting carry if there was no room for Ice Block)

    # PLA         # Restore current tile index -> 'A'
    # TAX         # X = A

    # BCS PRG008_B604     # If we didn't have room for an ice block, jump to PRG008_B604

    # # Otherwise...

    # LDA #$00
    # STA Player_TailAttack     # Disable any tail attacking

    # LDA #CHNGTILE_DELETETOBG
    # JSR Level_QueueChangeBlock     # Queue a block change to erase to background!

    # JMP PRG008_B652     # Jump to PRG008_B652

  PRG008_B604:

    # Not an ice block or if it was, Player was not interested in it...

    $a = ${ $Level_Tile_Array->[ $x+1 ] };   # LDA Level_Tile_GndL,X
# warn ">>$a<<  " . (qw/Level_Tile_Head Level_Tile_GndL Level_Tile_GndR Level_Tile_InFL Level_Tile_InFU/)[ $x+1 ];
    # CMP #TILEA_COIN # XXX
    goto PRG008_B623; # XXX # BNE PRG008_B623     # If Player is not touching coin, jump to PRG008_B623

    # LDA #CHNGTILE_DELETECOIN
    # JSR Level_QueueChangeBlock     # Queue a block change to erase to background!
    # JSR Level_RecordBlockHit     # Record having grabbed this coin so it does not come back

    # # Play coin collected sound!
    # LDA Sound_QLevel1
    # ORA #SND_LEVELCOIN
    # STA Sound_QLevel1

    # LDA #$00
    # STA Level_Tile_GndR    # Clear this tile detect (probably to prevent "double collecting" a coin the Player is straddling)

    # JMP PRG008_B652     # Jump to PRG008_B652

  PRG008_B623:

    # Player not touching coin...

    # XXX # CMP #TILEA_PSWITCH
    goto PRG008_B64F; # XXX BNE PRG008_B64F     # If Player is not touching P-Switch, jump to PRG008_B64F

    # Player touching P-Switch...

    # CPX #$02
    # BGS PRG008_B64F     # If it is being detected by Player's head, then jump to PRG008_B64F (don't hit with head!)

    # LDA #CHNGTILE_PSWITCHSTOMP    # P-Switch hit tile change

    # CMP Level_ChgTileEvent
    # BEQ PRG008_B64F     # If we've already got a tile change in the queue, jump to PRG008_B64F

    # # Queue tile change 9!
    # JSR Level_QueueChangeBlock

    # LDA #$10
    # STA Level_Vibration    # Level_Vibration = $10 (little shake effect)

    # # Wham! sound effect
    # LDA Sound_QLevel1
    # ORA #SND_LEVELBABOOM
    # STA Sound_QLevel1

    # LDA #$80     
    # STA Level_PSwitchCnt     # Level_PSwitchCnt = $80 (duration of switch)

    # # Play P-Switch song
    # LDA #MUS2B_PSWITCH
    # STA Sound_QMusic2

    goto PRG008_B652;          # JMP PRG008_B652     # Jump to PRG008_B652

  PRG008_B64F:
    Level_DoBumpBlocks();     # Handle any bumpable blocks (e.g. ? blocks, note blocks, etc.)

PRG008_B652:
    $a = pop @stack;          # PLA         
    $y = $a;                  # TAY         # Restore offset into TileAttrAndQuad_OffsSloped -> 'Y'

    return;                   # RTS         # Return
}

#
#
#

my $Level_ActionTiles = [
    # Tiles activated anytime
    $TILEA_GNOTE, $TILEA_HNOTE, $TILEA_NOTE, $TILEA_WOODBLOCKBOUNCE,
   
    # Tiles activated only when Player is moving upward
    $TILEA_QBLOCKFLOWER, $TILEA_INVISCOIN, $TILEA_NOTEINVIS,
];


# Logic to handle "bump blocks", e.g. ? blocks, note blocks, etc.
# sdw: A contains the tile number of the block we're currently looking at -- maybe
# sdw: X is the index into our $Level_Tile_Array thing; it tells us where the block is that we're currently looking at
# sdw: Level_Tile_InFL Level_Tile_InFU really are the blocks in front of us; this routine will never detect something we hit with our head... XXX but wait, how does "Checks for solid tile at Player's head" in Player_Control manage it?  oh, right, it feeds custom set of offsets to Player_GetTileAndSlope that represent the space where the players head is

sub Level_DoBumpBlocks {

    # LDA <Player_YVel # XXX some blocks don't bump if we're moving downards
    # BPL PRG008_B6EF  ; If Player is moving downward, jump to PRG008_B6EF

    $a = ${ $Level_Tile_Array->[ $x + 1 ] };
    # warn ">>$a<< Player_YVel = $Player_YVel Level_DoBumpBlocks " . (qw/Level_Tile_Head Level_Tile_GndL Level_Tile_GndR Level_Tile_InFL Level_Tile_InFU/)[ $x+1 ];
    # $tile_properties{ $a }->{hittable} ...
    if( $a eq 'X' and $Player_YVel < 0 and ( $x == 0 or $x == 1 ) ) {
        (my $x, my $y ) = @{ $Level_Tile_Positions->[ $x + 1 ] };
        $x >>= 4;   # go from pixel position to block position
        $y >>= 4;
        $map->[$x]->[$y] = ' '; 
    }
    if( $a eq '?' and $Player_YVel < 0 and ( $x == 0 or $x == 1 ) ) {
        (my $x, my $y ) = @{ $Level_Tile_Positions->[ $x + 1 ] };
        $x >>= 4;   # go from pixel position to block position
        $y >>= 4;
# XXXX spit out a powerup
        $map->[$x]->[$y] = '.'; 
    }
}

$app->run();

__END__

XXX to convert:

Swim_SmallBigLeaf:
    JSR Player_UnderwaterHControl # Do Player left/right input for underwater
    JSR Player_SwimV # Do Player up/down swimming action
    JSR Player_SwimAnim # Do Player swim animations
    RTS         # Return

GndMov_Big:
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag
    JSR Player_SoarJumpFallFrame # Do Player soar/jump/fall frame
    RTS         # Return

    RTS         # Return?

GndMov_FireHammer:
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag
    JSR Player_SoarJumpFallFrame # Do Player soar/jump/fall frame
    JSR Player_ShootAnim # Do Player shooting animation
    RTS         # Return

Swim_FireHammer:
    JSR Player_UnderwaterHControl # Do Player left/right input for underwater
    JSR Player_SwimV # Do Player up/down swimming action
    JSR Player_SwimAnim # Do Player swim animations
    JSR Player_ShootAnim # Do Player shooting animation
    RTS         # Return

GndMov_Leaf:
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag
    JSR Player_AnimTailWag # Do Player's tail animations
    JSR Player_TailAttackAnim # Do Player's tail attack animations
    RTS         # Return

    RTS         # Return?

GndMov_Frog:
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag

    LDA Player_IsHolding
    BNE PRG008_AA23     # If Player is holding something, jump to PRG008_AA23

    LDA <Player_InAir
    BEQ PRG008_AA00     # If Player is NOT in mid air, jump to PRG008_AA00

    LDA Player_SandSink
    LSR A
    BCS PRG008_AA00     # If bit 0 of Player_SandSink is set, jump to PRG008_AA00

    LDA #$00
    STA Player_FrogHopCnt     # Player_FrogHopCnt = 0

    LDY #$01     # Y = 1
    JMP PRG008_AA1E     # Jump to PRG008_AA1E

PRG008_AA00:
    LDA Player_FrogHopCnt
    BNE PRG008_AA1A     # If Player_FrogHopCnt <> 0, jump to PRG008_AA1A

    STA <Player_XVel    # Player_XVel = 0
    LDA <Pad_Holding    
    AND #(PAD_LEFT | PAD_RIGHT)
    BEQ PRG008_AA1A     # If Player is not pressing left/right, jump to PRG008_AA1A

    # Play frog hop sound
    LDA Sound_QPlayer
    ORA #SND_PLAYERFROG
    STA Sound_QPlayer

    LDA #$1f
    STA Player_FrogHopCnt # Player_FrogHopCnt = $1f

PRG008_AA1A:
    LSR A
    LSR A
    LSR A
    TAY     # Y = Player_FrogHopCnt >> 3

PRG008_AA1E:
    LDA Player_FrogHopFrames,Y    # Get frog frame
    STA <Player_Frame        # Store as frame

PRG008_AA23:
    RTS         # Return

Frog_SwimSoundMask:
    .byte $03, $07

    # Base frame for the different swimming directions of the frog
Frog_BaseFrame:
    # Down, Up, Left/Right
    .byte PF_FROGSWIM_DOWNBASE, PF_FROGSWIM_UPBASE, PF_FROGSWIM_LRBASE

    # Frame offset to frames above
Frog_FrameOffset:
    .byte $02, $02, $02, $01, $00, $01, $02, $02

    # Base velocity for frog swim right/down, left/up
Frog_Velocity:
    .byte 16, -16

Swim_Frog:
    LDX #$ff     # X = $FF

    LDA <Pad_Holding
    AND #(PAD_UP | PAD_DOWN)
    BEQ PRG008_AA61     # If Player is NOT pressing up/down, jump to PRG008_AA61

    # 
    STA <Player_InAir

    LSR A
    LSR A
    LSR A
    TAX         # X = 1 if pressing up, else 0

    LDA Frog_Velocity,X    # Get base frog velocity
    BPL PRG008_AA4D     # If value >= 0 (if pressing down), jump to PRG008_AA4D

    LDY Player_AboveTop
    BPL PRG008_AA4D     # If Player is not off top of screen, jump to PRG008_AA4D

    LDA #$00     # A = 0

PRG008_AA4D:
    LDY <Pad_Holding
    BPL PRG008_AA52     # If Player is not pressing 'A', jump to PRG008_AA52

    ASL A         # Double vertical speed

PRG008_AA52:
    CMP #(PLAYER_FROG_MAXYVEL+1)
    BLT PRG008_AA5C     

    LDY <Player_InAir
    BNE PRG008_AA5C     # If Player is swimming above ground, jump to PRG008_AA5C

    LDA #PLAYER_FROG_MAXYVEL     # Cap swim speed

PRG008_AA5C:
    STA <Player_YVel # Set Y Velocity
    JMP PRG008_AA6E     # Jump to PRG008_AA6E

PRG008_AA61:
    LDY <Player_YVel
    BEQ PRG008_AA6E     # If Y Velocity = 0, jump to PRG008_AA6E

    INY         # Y++

    LDA <Player_YVel
    BMI PRG008_AA6C     # If Player_YVel < 0, jump to PRG008_AA6C

    DEY
    DEY         # Y -= 2

PRG008_AA6C:
    STY <Player_YVel # Update Y Velocity

PRG008_AA6E:
    LDA <Pad_Holding
    AND #(PAD_LEFT | PAD_RIGHT)
    BEQ PRG008_AA84     # If Player is not pressing left or right, jump to PRG008_AA84

    # Player is pressing left/right...

    LSR A
    TAY
    LDA Frog_Velocity,Y    # Get base frog velocity

    LDY <Pad_Holding
    BPL PRG008_AA7E     # If Player is not pressing 'A', jump to PRG008_AA7E

    ASL A         # Double horizontal velocity

PRG008_AA7E:
    STA <Player_XVel # Update X Velocity

    LDX #$02     # X = 2
    BNE PRG008_AA9C     # Jump (technically always) to PRG008_AA9C

PRG008_AA84:
    LDY <Player_XVel
    BEQ PRG008_AA94     # If Player is not moving horizontally, jump to PRG008_AA94

    INY         # Y++

    LDA <Player_XVel
    BMI PRG008_AA8F     # If Player_XVel < 0, jump to PRG008_AA8F

    DEY
    DEY         # Y -= 2

PRG008_AA8F:
    STY <Player_XVel # Update X Velocity
    JMP PRG008_AA9C     # Jump to PRG008_AA9C

PRG008_AA94:
    LDA <Player_InAir
    BNE PRG008_AA9C     # If Player is swimming above ground, jump to PRG008_AA9C

    LDA #$15     # A = $15
    BNE PRG008_AAD2     # Jump (technically always) to PRG008_AAD2

PRG008_AA9C:
    TXA         
    BMI PRG008_AAC8     # If X < 0, jump to PRG008_AAC8

    LDA <Counter_1
    LSR A
    LSR A

    LDY #$00     # Y = 0

    BIT <Pad_Holding
    BMI PRG008_AAAB     # If Player is holding 'A', jump to PRG008_AAAB

    LSR A         # Otherwise, reduce velocity adjustment
    INY         # Y++

PRG008_AAAB:
    AND #$07
    TAY    
    BNE PRG008_AABF    

    LDA <Counter_1
    AND Frog_SwimSoundMask,Y
    BNE PRG008_AABF     # If timing is not right for frog swim sound, jump to PRG008_AABF

    # Play swim sound
    LDA Sound_QPlayer
    ORA #SND_PLAYERSWIM
    STA Sound_QPlayer

PRG008_AABF:
    LDA Frog_BaseFrame,X
    ADD Frog_FrameOffset,Y
    BNE PRG008_AAD2

PRG008_AAC8:
    LDY #PF_FROGSWIM_IDLEBASE

    LDA <Counter_1
    AND #$08
    BEQ PRG008_AAD1

    INY

PRG008_AAD1:
    TYA

PRG008_AAD2:
    STA <Player_Frame # Update Player_Frame
    RTS         # Return

GndMov_Tanooki:
    JSR Player_TanookiStatue  # Change into/maintain Tanooki statue (NOTE: Will not return here if statue!)
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag
    JSR Player_AnimTailWag # Do Player's tail animations
    JSR Player_TailAttackAnim # Do Player's tail attack animations
    RTS         # Return

Swim_Tanooki:
    JSR Player_TanookiStatue # Change into/maintain Tanooki statue (NOTE: Will not return here if statue!)
    JSR Player_UnderwaterHControl # Do Player left/right input for underwater
    JSR Player_SwimV # Do Player up/down swimming action
    JSR Player_SwimAnim # Do Player swim animations
    RTS         # Return

Move_Kuribo:
    JSR Player_GroundHControl # Do Player left/right input control
    JSR Player_JumpFlyFlutter # Do Player jump, fly, flutter wag

    LDA <Player_InAir
    BNE PRG008_AAFF     # If Player is mid air, jump to PRG008_AAFF

    STA Player_KuriboDir     # Clear Player_KuriboDir

PRG008_AAFF:
    LDA Player_KuriboDir
    BNE PRG008_AB17     # If Kuribo's shoe is moving, jump to PRG008_AB17

    LDA <Player_InAir
    BNE PRG008_AB25     # If Player is mid air, jump to PRG008_AB25

    LDA <Pad_Holding
    AND #(PAD_LEFT | PAD_RIGHT)
    STA Player_KuriboDir     # Store left/right pad input -> Player_KuriboDir
    BEQ PRG008_AB25         # If Player is not pressing left or right, jump to PRG008_AB25
    INC <Player_InAir     # Flag as in air (Kuribo's shoe bounces along)

    LDY #-$20
    STY <Player_YVel     # Player_YVel = -$20

PRG008_AB17:
    LDA <Pad_Input
    BPL PRG008_AB25     # If Player is NOT pressing 'A', jump to PRG008_AB25

    LDA #$00
    STA Player_KuriboDir     # Player_KuriboDir = 0

    LDY Player_RootJumpVel     # Get initial jump velocity
    STY <Player_YVel     # Store into Y velocity

PRG008_AB25:
    LDY <Player_Suit
    BEQ PRG008_AB2B     # If Player is small, jump to PRG008_AB2B

    LDY #$01     # Otherwise, Y = 1

PRG008_AB2B:

    # Y = 0 if small, 1 otherwise

    LDA Player_KuriboFrame,Y    # Get appropriate Kuribo's shoe frame
    STA <Player_Frame        # Store as active Player frame

    LDA <Counter_1
    AND #$08    
    BEQ PRG008_AB38         # Every 8 ticks, jump to PRG008_AB38

    INC <Player_Frame    # Player_Frame++

PRG008_AB38:
    RTS         # Return

sub force_signed {
    my $ref = shift;
    my $ob = B::svref_2object( $ref ) or die;
    # define SVf_IVisUV  0x80000000  /* use XPVUV instead of XPVIV */
    $ob->FLAGS( $ob->FLAGS & ~ 0x80000000 );
}

sub force_unsigned {
    my $ref = shift;
    my $ob = B::svref_2object( $ref ) or die;
    # define SVf_IVisUV  0x80000000  /* use XPVUV instead of XPVIV */
    $ob->FLAGS( $ob->FLAGS | 0x80000000 );
}

