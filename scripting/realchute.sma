/*******************************************************************************
*
*	RealChute (ya, another parachute plugin)
*	by Vet(3TT3V)
*
*	SPECIAL THANKS to KRoTaL & JTP10181
*		Their Parachute V1.3 plugin was an inspiration for this plugin
*
*	Tested on Windows server with Day of Defeat 1.3 and Counter-Strike 1.6
*		(No other mods/OS have been tested)
*
*	Features:
*		Uses the Fakemeta module
*		Players must press a key bound to the command "ripcord" to
*			use the parachute. (ex: bind "x" "ripcord")
*		Configurable for 1 chute per life or unlimited chutes. But
*			only 1 chute deployment allowed per usage
*		Player must be 'catching air' to avoid chute malfunction
*		Chute displays 'deploy', 'idle' and 'detach' animations
*		Logs chute status changes with admin's name
*		Interprets being IN_WATER the same as being ON_GROUND
*		Uses 'realchute.mdl' model. (Same as 'parachute.mdl' but
*			without the gay "I'm flying WHEE" on it)
*
*	CVARs:
*		realchute_ctrl <0|1|2> - defaults is 1 (1 chute per life)
*
*	Commands:
*		amx_realchute <0|1|2|?> (command access level 'h' required)
*			0 - Plugin disabled
*			1 - Plugin enabled, 1 chute per life
*			2 - Plugin enabled, unlimited chutes
*
*		ripcord - Starts the parachute deploy. (Must be off the ground)
*		say "/chutes" - Displays RealChute status
*		say "/chute" - Displays your parachute status
*
********************************************************************************/

/***********************************************************
*
*	Model reference data
*
*	Deploy: Sequence = 0, Frames = 85 (0 - 84), FPS = 35
*		Frames 1 - 5 'Pack'
*		Frames 6 - 30 'Deploy'
*		Frames 31 - 54 'Balancing'
*		Frames 55 - 84 'Idle'
*
*	Idle: Sequence = 1, Frames = 40 (0 - 39), FPS = 10
*
*	Detach: Sequence = 2, Frames = 30 (0 - 29), FPS = 15
*
************************************************************/

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>

#define PLUGIN "RealChute"
#define VERSION "1.92"
#define AUTHOR "Vet(3TT3V)"
#define SVARIABLE "RealChute"
#define SVALUE "v1.92 by Vet(3TT3V)"

#define DEPLOY_START_FRAME 6.0
#define DEPLOY_END_FRAME 170.0
#define DEPLOY_STEP 1.0
#define DETACH_START_FRAME 0.0
#define DETACH_END_FRAME 210.0
#define DETACH_STEP 2.5
#define DEPLOYED_GRAVITY 0.1
#define NORMAL_GRAVITY 1.0
#define FALLRATE_TRIGGER 50.0
#define CHUTE_MODEL "models/realchute.mdl"
#define GROUNDED (FL_ONGROUND | FL_INWATER)

// From Ven's fakemeta_util include
#define fm_create_entity(%1) engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, %1))
#define fm_entity_set_model(%1,%2) engfunc(EngFunc_SetModel, %1, %2)
#define fm_remove_entity(%1) engfunc(EngFunc_RemoveEntity, %1)

new Float:g_frame[33]
new g_entity[33]
new g_status[33]
new g_control

public plugin_precache()
{
	if (file_exists(CHUTE_MODEL))
		precache_model(CHUTE_MODEL)
	else
		set_fail_state("Disabling realchute.amxx plugin. (Chute model not found)")
}

public plugin_init()
{
	g_control = register_cvar("realchute_ctrl", "1" )

	register_plugin(PLUGIN, VERSION, AUTHOR)
	register_forward(FM_PlayerPreThink, "client_prethink")
	register_event("ResetHUD", "player_spawn", "be")
	register_concmd("amx_realchute", "ctrlchutes", ADMIN_CFG, "<0|1|2|?>")
	register_clcmd("say /chutes", "cmdChutes", 0, "Displays server parachute status")
	register_clcmd("say /chute", "cmdChutesP", 0, "Displays your parachute status")
	register_clcmd("ripcord", "cmdRipcord", 0, "Deploy parachute")
	register_clcmd("fullupdate", "cmdFullUpdate", 0, "Block fullupdate")

	register_cvar(SVARIABLE, SVALUE, FCVAR_SERVER|FCVAR_SPONLY)
}

public client_prethink(id)
{ 
	if (g_status[id] < 2)
		return FMRES_IGNORED		// 99.99% of the time = true - exit if not using chute

	if (!get_pcvar_num(g_control))
		return FMRES_IGNORED		// exit if the plugin is disabled

	if (!is_user_alive(id)) {
		chute_reset(id)
		return FMRES_IGNORED		// reset chute and exit if the player died while using chute
	}

	if (g_status[id] < 5) {			// if chute is already detaching, skip ahead
		if (pev(id, pev_flags) & GROUNDED)
			detach_setup(id)
	}

	switch(g_status[id]) {
		case 2: {			// create the chute and set the model to 'deploy'
			g_entity[id] = fm_create_entity("info_target")
			set_pev(g_entity[id], pev_aiment, id)
			set_pev(g_entity[id], pev_movetype, MOVETYPE_FOLLOW)
			fm_entity_set_model(g_entity[id], CHUTE_MODEL)
			set_pev(g_entity[id], pev_sequence, 0)
			g_frame[id] = DEPLOY_START_FRAME
			g_status[id] = 3
		}
		case 3: {			// start the 'deploy' animation, play until the player is falling
			set_pev(g_entity[id], pev_frame, g_frame[id])
			g_frame[id] += DEPLOY_STEP
			if (g_frame[id] > DEPLOY_END_FRAME) {
				client_print(id, print_chat, "Chute Malfunctioned")
				detach_setup(id)
			}
						// when falling, lower the gravity
			if (pev(id, pev_flFallVelocity) > FALLRATE_TRIGGER) {
				set_pev(id, pev_gravity, DEPLOYED_GRAVITY)
				client_print(id, print_chat, "Chute Deployed")
				g_status[id] = 4
			}
		}
		case 4: {			// continue the 'deploy' animation until finished or too slow
			set_pev(g_entity[id], pev_frame, g_frame[id])
			if (pev(id, pev_flFallVelocity) < FALLRATE_TRIGGER) {
				detach_setup(id)
				return FMRES_IGNORED
			}
			g_frame[id] += DEPLOY_STEP
			if (g_frame[id] > DEPLOY_END_FRAME)
				g_frame[id] = DEPLOY_END_FRAME
		}
		case 5: {			// play the 'detach' animation
			set_pev(g_entity[id], pev_frame, g_frame[id])
			g_frame[id] += DETACH_STEP
			if (g_frame[id] > DETACH_END_FRAME)
				g_status[id] = 6
		}
		case 6: {			// reset the chute settings
			chute_reset(id)
		}
	}
	return FMRES_IGNORED
}

public ctrlchutes(id,lvl,cid)
{
	if (!cmd_access(id, lvl, cid, 2))
		return PLUGIN_HANDLED
		
	new tmpstr[32]
	read_argv(1, tmpstr, 31)
	trim(tmpstr)
	if (equal(tmpstr, "?")) {
		console_print(id, "^nRealChute Control: amx_realchute #")
		console_print(id, "  0 - Disables RealChute plugin")
		console_print(id, "  1 - 1 parachute per life")
		console_print(id, "  2 - Unlimited parachutes")
		console_print(id, "RealChute Is Currently Set To: %d^n", get_pcvar_num(g_control))
		return PLUGIN_HANDLED
	}
	new tmpctrl = str_to_num(tmpstr)
	if (tmpctrl < 0 || tmpctrl > 2) {
		console_print(id, "RealChute control parameter out of range (0 - 2)")
		return PLUGIN_HANDLED
	}
	set_cvar_string("realchute_ctrl", tmpstr)
	get_user_name(id, tmpstr, 31)
	console_print(id, "RealChute control changed to %d", tmpctrl)
	log_message("[AMXX] RealChute - Admin %s changed RealChute control to %d", tmpstr, tmpctrl)

	return PLUGIN_HANDLED
}

public cmdChutes(id)
{
	client_print(0, print_chat,"Parachutes are %s", get_pcvar_num(g_control) ? "Enabled" : "Disabled")
	return PLUGIN_CONTINUE
}

public cmdChutesP(id)
{
	client_print(id, print_chat,"Your parachute %s", g_status[id] ? "is Ready" : "has been Used")
	return PLUGIN_CONTINUE
}

public cmdRipcord(id)
{
	if ((g_status[id] == 1) && !(pev(id, pev_flags) & GROUNDED) && is_user_alive(id)) 
		g_status[id] = 2
	return PLUGIN_HANDLED
}

public detach_setup(id)
{
	g_frame[id] = DETACH_START_FRAME
	set_pev(g_entity[id], pev_sequence, 2)
	set_pev(id, pev_gravity, NORMAL_GRAVITY)
	g_status[id] = 5
}

public chute_reset(id)
{
	if (g_entity[id] > 0) {
		if (pev_valid(g_entity[id])) {
			fm_remove_entity(g_entity[id])
			g_entity[id] = 0
		}
	}
	set_pev(id, pev_gravity, NORMAL_GRAVITY)
	g_status[id] = get_pcvar_num(g_control) > 1 ? 1 : 0
}

public player_spawn(id)
{
	chute_reset(id)
	g_status[id] = 1
}

public client_putinserver(id)
{
	chute_reset(id)
}

public client_disconnect(id)
{
	chute_reset(id)
}

public cmdFullUpdate(id)
{
	return PLUGIN_HANDLED_MAIN
}
