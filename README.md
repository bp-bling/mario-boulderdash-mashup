mario-boulderdash-mashup
========================

SMB3 jump/momentum/run/collision logic translated to Perl/SDL from 6502, with Boulder Dash and other physics added

This was part of my presentation for YAPC 2012 where I talked about programming games in Perl.  Most of the video was lost.

The engine works.  You can run, jump, break blocks, and mess with the physics.  I think the Boulder Dash
logic isn't quite right, and things are missing, such as tunneling, breaking blocks next to you, magic walls,
and other things.  Fireflys do fly around and blow up.  There are no diamonds.  The goal of each level is
just to escape and continue on.  It needs more levels.  I also should have been running the 6502 code in
Acme::6502 rather than painfully translating it to Perl.
