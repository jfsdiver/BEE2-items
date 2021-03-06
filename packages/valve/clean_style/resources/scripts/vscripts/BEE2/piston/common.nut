// Coordinates the different parts of the piston platform-style items.

// Used with the PistonPlatform Result - places instances, and this script.
// Entities we control:
// -script: Us
// -pist1 - 4: The func_movelinears, needs SetPosition, OnFullyOpen, OnFullyClosed

inst_name <- self.GetName().slice(0, -7);

pos <- 0;  // Position we want to be at.
// Layout:
// pos, pist
// 4    _ _
//       4
// 3    _4_
//       3
// 2    _3_
//       2 
// 1    _2_  ___
//       1    |
// 0 ____1____|_

// 1-4 = ents, may be null.
pistons <- {};
// positions - where the door is right now.
POS_UP <- 1;
POS_DN <- -1;
POS_MOVING <- 0;
positions <- {};
cur_moving <- -1;

START_SND <- "";
STOP_SND <- "";

// If true, we spawned extended.
SPAWN_UP <- false;

has_dn_fizz <- false;
dn_fizz_on <- false;
dn_fizz_allowed <- false;
door_pos <- null;
crush_count <- 0;


function Precache() {
	if(START_SND) self.PrecacheSoundScript(START_SND);
	if(STOP_SND)  self.PrecacheSoundScript(STOP_SND);
}

function OnPostSpawn() {
	// Grab our pistons - may not be there if the ents won't exist.
	local pist = null;
	local found_pist = false;
	local start_pos = (SPAWN_UP) ? POS_UP : POS_DN;
	local highest_pos = 0;
	for (local i=1; i<=4; i++) {
		pist = Entities.FindByName(null, inst_name + "-pist" + i);
		pistons[i] <- pist;
		// Hookup IO to notify us when they've reached the ends.
		// We set the position to the correct value, then call _up() or _dn().
		if (pist != null) {
			EntFireByHandle(pist, "AddOutput", "OnFullyOpen " + self.GetName() + ":RunScriptCode:positions[" + i + "]=" + POS_UP + ";_up():0:-1", 0, self, self);
			EntFireByHandle(pist, "AddOutput", "OnFullyClosed " + self.GetName() + ":RunScriptCode:positions[" + i + "]=" + POS_DN + ";_dn():0:-1", 0, self, self);
			positions[i] <- start_pos;
			found_pist = true;
			highest_pos = i;
		} else {
			// Piston not there, so we need to assume bottom ones are up,
			// top ones are down.
			// if found_pist = true, we're past the bottom ones...
			positions[i] <- found_pist ? POS_DN : POS_UP;
		}
	}
	if (SPAWN_UP) {
		pos = highest_pos;
	}
	
	snd_source_ent <- self.GetMoveParent();
	if (snd_source_ent == null) {
		snd_source_ent = self;
	} else {
		// No use for the parent now we know about it.
		EntFireByHandle(self, "ClearParent", "", 0, self, self);
	}
	
	// If present, trigger whenever we start moving to wake cubes.
	enable_motion_trig <- Entities.FindByName(null, inst_name + "-wake_trig");
	
	// If we have these, turn them on while going down.
	// We can't store the handle to it, since there's a hurt and fizzler.
	has_dn_fizz <- Entities.FindByName(null, inst_name + "-dn_fizz") != null;
}

function moveto(new_pos) {
	local old_pos = pos;
	pos = new_pos;
	
	// printl("Moving: " + old_pos + " -> " + new_pos);
	
	if (old_pos == new_pos) {
		return; // No change.
	}
	
	if (cur_moving == -1) {
		if(START_SND) {
			self.EmitSound(START_SND);
		}
		if(self.GetClassname() == "ambient_generic") {
			EntFireByHandle(self, "PlaySound", "", 0.00, self, self);
		}
		if (enable_motion_trig != null) {
			EntFireByHandle(enable_motion_trig, "Enable", "", 0, self, self);
			EntFireByHandle(enable_motion_trig, "Disable", "", 0.1, self, self);
		}
	}
	
	if (old_pos < new_pos) {
		door_pos = null;
		if (has_dn_fizz) {
			dn_fizz_allowed = false;
			if (dn_fizz_on) {
				dn_fizz_on = false;
				EntFire(inst_name + "-dn_fizz", "Disable", "", 0, self);
			}
		}
		_up();
	} else if (old_pos > new_pos) {
		_dn();
		if (has_dn_fizz) {
			dn_fizz_allowed <- true;
		}
	}
}

// These two funcs find the first platform in their direction that's wrong,
// and trigger it.
// The pistons then trigger them again when they finish, so we loop until done.
function _up() {
	for(local i=1; i<=pos; i++) {
		if (positions[i] != POS_UP) {
			positions[i] = POS_MOVING;
			EntFireByHandle(pistons[i], "Open", "", 0, self, self);
			cur_moving = i;
			return;
		}
	}
	// Finished.
	cur_moving = -1;
	if (STOP_SND) {
		snd_source_ent.EmitSound(STOP_SND);
	}
	if(self.GetClassname() == "ambient_generic") {
		EntFireByHandle(self, "StopSound", "", 0.00, self, self);
	}
}

function _dn() {
	// Do not include piston[pos].
	for(local i=4; i>pos; i--) {
		if (positions[i] != POS_DN) {
			positions[i] = POS_MOVING;
			EntFireByHandle(pistons[i], "Close", "", 0, self, self);
			cur_moving = i;
			door_pos = pistons[i].GetOrigin();
			crush_count = 0;
			return;
		}
	}
	// Finished.
	cur_moving = -1;
	if (STOP_SND) {
		snd_source_ent.EmitSound(STOP_SND);
	}
	if(self.GetClassname() == "ambient_generic") {
		EntFireByHandle(self, "StopSound", "", 0.00, self, self);
	}
	if (has_dn_fizz && dn_fizz_on) {
		dn_fizz_on = false;
		dn_fizz_allowed = false;
		door_pos = null;
		EntFire(inst_name + "-dn_fizz", "Disable", "", 0, self);
	}
}

// Used by pistons that can fizzle objects below them.
// If it gets stuck (stops moving), activate.
function FizzThink() {
	// Lotsa checks here.
	// Only run if:
	// * allowed to.
	// * Not already on
	// * Currently moving
	// * We have a valid previous position
	// It has to trigger twice consecuatively.
    if (dn_fizz_allowed && !dn_fizz_on && cur_moving != -1 && door_pos != null) {
		local new_pos = pistons[cur_moving].GetOrigin();
		if ((new_pos - door_pos).LengthSqr() < 1) {
			crush_count++;
			if (crush_count > 2) {
				// Stuck...
				dn_fizz_on = true;
				EntFire(inst_name + "-dn_fizz", "Enable", "", 0, self);
			}
		} else {
			crush_count = 0;
		}
		door_pos = new_pos;
   		return 0.05;
    }
    return 0.25;
}
