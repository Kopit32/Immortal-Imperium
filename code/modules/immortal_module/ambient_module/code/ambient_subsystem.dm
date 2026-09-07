// ============================================================================
// SSplayer_audio: реестр зон/джобов, тик всех компонентов, авто-аттач.
// Госты и мобы без клиента не аттачатся — звука на них нет.
// ============================================================================

SUBSYSTEM_DEF(player_audio)
	name = "Player Audio"
	wait = PA_TICK_WAIT

	var/list/tracked = list()              // живые компоненты
	var/list/zone_registry = list()        // тип area -> datum/zone_audio
	var/list/zone_cache = list()           // тип area -> resolve; инвалидируется при регистрации
	var/list/job_combat_registry = list()  // "Job Title" -> list(треки)
	var/list/audio_groups = list()         // имя группы -> datum/zone_audio
	var/datum/zone_audio/default_zone = null
	var/list/default_combat = list()
	var/pa_last_fire = 0

/datum/controller/subsystem/player_audio/Initialize(start_timeofday)
	. = ..()
	setup_player_audio()

/datum/controller/subsystem/player_audio/fire()
	var/now = world.time
	var/dt = min((now - pa_last_fire) / 10, PA_DT_CAP)
	pa_last_fire = now
	// авто-аттач: покрывает спавн, лейтджоин, переселение в тела
	for(var/mob/M in GLOB.player_list)
		if(!M.client || !istype(M, /mob/living))
			continue
		if(M.GetExactComponent(/datum/component/player_audio))
			continue
		M.AddComponent(/datum/component/player_audio)
	// тик: обратная итерация — безопасное удаление мёртвых без Copy()
	for(var/i = tracked.len; i > 0; i--)
		var/datum/component/player_audio/PA = tracked[i]
		if(QDELETED(PA))
			tracked.Cut(i, i + 1)
			continue
		PA.tick(dt)

/datum/controller/subsystem/player_audio/proc/register_component(datum/component/player_audio/PA)
	tracked |= PA

/datum/controller/subsystem/player_audio/proc/unregister_component(datum/component/player_audio/PA)
	tracked -= PA

// Registry: точный тип -> вверх по иерархии area -> default -> тишина.
// Регистрировать самый общий тип: дети унаследуют. Результат кэшируется.
/datum/controller/subsystem/player_audio/proc/resolve_zone(zone_type)
	if(zone_type in zone_cache)
		return zone_cache[zone_type]
	var/datum/zone_audio/found
	var/current = zone_type
	while(current)
		var/datum/zone_audio/Z = zone_registry[current]
		if(Z)
			found = Z
			break
		if(current == /area)
			break
		current = type2parent(current)
	if(!found)
		found = default_zone
	zone_cache[zone_type] = found
	return found

// Выбор боевого трека: джоб (alt-титул специфичнее базового) -> зона -> default -> тишина.
// exclude — не повторять играющий трек (если в пуле больше одного).
/datum/controller/subsystem/player_audio/proc/pick_combat_track(mob/M, zone_type, exclude)
	var/list/pool = get_job_combat_pool(M)
	if(!pool || !pool.len)
		pool = get_zone_combat_pool(zone_type)
	if(!pool || !pool.len)
		pool = default_combat
	if(!pool || !pool.len)
		return null
	if(exclude && pool.len > 1)
		pool = pool - list(exclude)
	return pick(pool)

/datum/controller/subsystem/player_audio/proc/get_job_combat_pool(mob/M)
	if(!M || !M.mind)
		return null
	var/alt = M.mind.role_alt_title
	if(alt)
		var/list/pool = job_combat_registry[alt]
		if(pool && pool.len)
			return pool
	var/role = M.mind.assigned_role
	return role ? job_combat_registry[role] : null

/datum/controller/subsystem/player_audio/proc/get_zone_combat_pool(zone_type)
	var/datum/zone_audio/Z = zone_type ? resolve_zone(zone_type) : null
	return (Z && Z.combat.len) ? Z.combat : null

// ---- API конфига ------------------------------------------------------------

/datum/controller/subsystem/player_audio/proc/register_zone(area_type, list/ambient, list/combat, list/bed, ambient_volume, bed_volume, silent, silence_min, silence_max, group)
	if(!ispath(area_type, /area))
		warn("register_zone: [area_type] — не /area, пропущено")
		return
	var/datum/zone_audio/Z = group ? audio_groups[group] : null
	if(Z)
		if(ambient || combat || bed)
			warn("register_zone: группа \"[group]\" уже определена — треки [area_type] проигнорированы, используйте attach_zone")
	else
		Z = new(group)
		Z.silent = !!silent
		if(isnum(ambient_volume)) Z.ambient_volume = ambient_volume
		if(isnum(bed_volume))     Z.bed_volume = bed_volume
		if(isnum(silence_min))    Z.silence_min = silence_min
		if(isnum(silence_max))    Z.silence_max = silence_max
		Z.ambient = normalize_tracks(ambient)
		Z.combat = combat ? combat.Copy() : list()
		Z.bed = normalize_tracks(bed)
		if(group)
			audio_groups[group] = Z
	zone_registry[area_type] = Z
	zone_cache.Cut()

// Привязать зону к существующей группе, не таская списки треков.
/datum/controller/subsystem/player_audio/proc/attach_zone(area_type, group)
	if(!ispath(area_type, /area) || !istext(group))
		warn("attach_zone: плохие аргументы ([area_type], [group])")
		return
	var/datum/zone_audio/Z = audio_groups[group]
	if(!Z)
		warn("attach_zone: группа \"[group]\" не найдена ([area_type])")
		return
	zone_registry[area_type] = Z
	zone_cache.Cut()

/datum/controller/subsystem/player_audio/proc/register_job_combat(job_title, list/tracks)
	if(!istext(job_title) || !job_title)
		warn("register_job_combat: пустое имя джоба")
		return
	if(!tracks || !tracks.len)
		warn("register_job_combat: пустой список треков для \"[job_title]\"")
		return
	job_combat_registry[job_title] = tracks.Copy()

/datum/controller/subsystem/player_audio/proc/set_default_ambient(list/ambient, ambient_volume)
	var/datum/zone_audio/Z = default_zone || new /datum/zone_audio
	if(isnum(ambient_volume))
		Z.ambient_volume = ambient_volume
	Z.ambient = normalize_tracks(ambient)
	default_zone = Z
	zone_cache.Cut()

/datum/controller/subsystem/player_audio/proc/set_default_combat(list/combat)
	default_combat = combat ? combat.Copy() : list()

/datum/controller/subsystem/player_audio/proc/get_track_duration(track)
	var/duration = GLOB.new_sound_system_tracks[track]
	return isnum(duration) && duration > 0 ? duration : 0

// Плоский список ('a','b') -> веса 1; ассоц ('a' = w, ...) -> вес w.
// Прямое tracks[track] на плоском списке вернуло бы ИНДЕКС, отсюда эвристика.
/datum/controller/subsystem/player_audio/proc/normalize_tracks(list/tracks)
	var/result = list()
	if(!tracks || !tracks.len)
		return result
	var/assoc = FALSE
	var/i = 0
	for(var/k in tracks)
		i++
		if(tracks[k] != i)
			assoc = TRUE
			break
	if(assoc)
		for(var/k in tracks)
			var/w = tracks[k]
			result[k] = (isnum(w) && w > 0) ? w : 1
	else
		for(var/k in tracks)
			result[k] = 1
	return result

/datum/controller/subsystem/player_audio/proc/warn(msg)
	world.log << "SSplayer_audio: [msg]"

/datum/controller/subsystem/player_audio/proc/register_legacy_bed(list/areas, track)
	var/list/bed_tracks = list()
	bed_tracks[track] = 1
	for(var/area_type in areas)
		if(!ispath(area_type, /area))
			warn("register_legacy_bed: [area_type] — не /area, пропущено")
			continue
		var/datum/zone_audio/Z = zone_registry[area_type]
		if(!Z)
			Z = new
		Z.bed = bed_tracks.Copy()
		zone_registry[area_type] = Z
	zone_cache.Cut()

/proc/setup_player_audio()
	//ZONES
	SSplayer_audio.register_zone(/area/cadiaoutpost/oa/engineering,
		ambient = list('code/modules/immortal_module/ambient_module/sounds/ambient.ogg' = 10),
		ambient_volume = 25, silence_min = 200, silence_max = 400)
	// пример переноса старого зонального эмбиента в bed:
	// SSplayer_audio.register_zone(/area/..., bed = list('sounds/zone_loop.ogg'), bed_volume = 12)

	SSplayer_audio.register_zone(/area/cadiaoutpost/new_hive/hive_city, group = "hive_city",
		ambient = list('code/modules/immortal_module/ambient_module/sounds/city_ambient1_atoma_prime.ogg' = 10,
		'code/modules/immortal_module/ambient_module/sounds/city_ambient2_city_of_tertium.ogg' = 10,
		'code/modules/immortal_module/ambient_module/sounds/city_ambient3_imperium_of_man.ogg' = 10,
		'code/modules/immortal_module/ambient_module/sounds/city_ambient4_hive_city_lowers_levels.ogg' = 10),
		silence_min = 180, silence_max = 500, ambient_volume = 20)
	SSplayer_audio.attach_zone(/area/cadiaoutpost/oa/service/kitchen, "hive_city")
	SSplayer_audio.attach_zone(/area/cadiaoutpost/oa/supply, "hive_city")
	SSplayer_audio.attach_zone(/area/cadiaoutpost/oa/service/enforcer, "hive_city")
	SSplayer_audio.attach_zone(/area/cadiaoutpost/oa/service/kitchen, "hive_city")

	SSplayer_audio.set_default_combat(list(
		'code/modules/immortal_module/ambient_module/sounds/combat_music/dispose_unite.ogg',
		'code/modules/immortal_module/ambient_module/sounds/combat_music/immortal_imperium.ogg',
		'code/modules/immortal_module/ambient_module/sounds/combat_music/imperial_advance.ogg',
		'code/modules/immortal_module/ambient_module/sounds/combat_music/light_of_imperium.ogg',
		'code/modules/immortal_module/ambient_module/sounds/combat_music/reject_unite.ogg'
		))

	// Legacy Cadia area music, now used as the passive bed layer.
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/new_hive/caves,
		/area/cadiaoutpost/gma/air,
		/area/cadiaoutpost/magosship1,
		/area/cadiaoutpost/oa/farm,
		/area/cadiaoutpost/oa/groxpen,
		/area/cadiaoutpost/oa/supply/mining,
		/area/cadiaoutpost/oa/caves,
		/area/cadiaoutpost/oa/village,
		/area/cadiaoutpost/oa/villageinside,
		/area/cadiaoutpost/oa/gatehouse,
		/area/cadiaoutpost/oa/shuttle/aquila
	), 'sound/newmusic/General_Ambient2.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/gma/inquisitoracolyte,
		/area/cadiaoutpost/rtship1,
		/area/cadiaoutpost/rtship2,
		/area/cadiaoutpost/govship1,
		/area/cadiaoutpost/govship2,
		/area/cadiaoutpost/magosship2,
		/area/cadiaoutpost/oa/governor,
		/area/cadiaoutpost/oa/hangarpact,
		/area/cadiaoutpost/oa/hangarpact2,
		/area/cadiaoutpost/oa/hangarmech,
		/area/cadiaoutpost/oa/medicae/virology,
		/area/cadiaoutpost/oa/villageinside/lab,
		/area/cadiaoutpost/oa/shuttle/inquisition,
		/area/cadiaoutpost/oa/shuttle/station1,
		/area/cadiaoutpost/oa/shuttle/station2,
		/area/cadiaoutpost/oa/shuttle/roguet,
		/area/cadiaoutpost/oa/shuttle/inquisitionpact,
		/area/cadiaoutpost/oa/shuttle/governor,
		/area/cadiaoutpost/oa/shuttle/mechanicus,
		/area/cadiaoutpost/oa/shuttle/magos,
		/area/cadiaoutpost/oa/shuttle/tau1,
		/area/cadiaoutpost/oa/shuttle/tau2,
		/area/cadiaoutpost/oa/shuttle/g1,
		/area/cadiaoutpost/oa/shuttle/g2,
		/area/cadiaoutpost/oa/tauship,
		/area/cadiaoutpost/oa/krootship
	), 'sound/newmusic/Lab_Experiment.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/mechiferry1,
		/area/cadiaoutpost/mechiferry2,
		/area/cadiaoutpost/cha1,
		/area/cadiaoutpost/cha2,
		/area/cadiaoutpost/oa/bridge/hallway,
		/area/cadiaoutpost/oa/departures,
		/area/cadiaoutpost/oa/hallway,
		/area/cadiaoutpost/oa/magistratumpost,
		/area/cadiaoutpost/oa/security,
		/area/cadiaoutpost/oa/maintenance/department/security,
		/area/cadiaoutpost/oa/bridge/offices/heir,
		/area/cadiaoutpost/oa/bridge/offices/commissar,
		/area/cadiaoutpost/oa/bridge/offices/magoserrant,
		/area/cadiaoutpost/oa/bridge/offices/magosexplorator,
		/area/cadiaoutpost/oa/bridge/offices/planetarygovernor,
		/area/cadiaoutpost/oa/bridge,
		/area/cadiaoutpost/oa/hangar,
		/area/cadiaoutpost/oa/engineering,
		/area/cadiaoutpost/oa/engineering/engine/enginesmes,
		/area/cadiaoutpost/oa/medicae,
		/area/cadiaoutpost/oa/research,
		/area/cadiaoutpost/oa/tradefloor,
		/area/cadiaoutpost/oa/maintenance/central,
		/area/cadiaoutpost/oa/maintenance/department/bridge,
		/area/cadiaoutpost/oa/maintenance/department/supply/cargo,
		/area/cadiaoutpost/oa/maintenance/department/service/bar,
		/area/cadiaoutpost/oa/maintenance/department/engineering,
		/area/cadiaoutpost/oa/maintenance/north,
		/area/cadiaoutpost/oa/maintenance/west,
		/area/cadiaoutpost/oa/maintenance/east,
		/area/cadiaoutpost/oa/crew_quarters,
		/area/cadiaoutpost/oa/storage,
		/area/cadiaoutpost/oa/vault,
		/area/cadiaoutpost/oa/shuttle/mechiferry,
		/area/cadiaoutpost/oa/shuttle/chacha
	), 'sound/newmusic/Outpost1.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/wilds/dungeonlower,
		/area/cadiaoutpost/oa/shuttle/cargo2,
		/area/cadiaoutpost/oa/engineering/engine/enginewaste,
		/area/cadiaoutpost/oa/shuttle/cargo1
	), 'sound/newmusic/DUNGEONLOWER.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/wilds
	), 'sound/newmusic/WILDERNESS.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/dungeon1,
		/area/cadiaoutpost/oa/dungeon3,
		/area/cadiaoutpost/oa/theforest
	), 'sound/newmusic/Caves_Terror.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/dungeon2,
		/area/cadiaoutpost/oa/dungeon4
	), 'sound/newmusic/lovecraft2.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/mechanicusdig
	), 'sound/newmusic/lovecraft1.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/bridge/offices/sisterhospitaller,
		/area/cadiaoutpost/oa/bridge/offices/sistersuperior,
		/area/cadiaoutpost/oa/service/chapel,
		/area/cadiaoutpost/oa/maintenance/department/service/chapel
	), 'sound/newmusic/Chapel1.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/service/bar,
		/area/cadiaoutpost/oa/service/hydroponics,
		/area/cadiaoutpost/oa/service/kitchen/cafeteria,
		/area/cadiaoutpost/oa/supply/offices/roguetrader,
		/area/cadiaoutpost/oa/service/inn
	), 'sound/newmusic/Inn_Ambient.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/supply,
		/area/cadiaoutpost/oa/service/hab,
		/area/cadiaoutpost/oa/service/enforcer
	), 'sound/newmusic/Hab.ogg')
	SSplayer_audio.register_legacy_bed(list(
		/area/cadiaoutpost/oa/caves/dark,
		/area/cadiaoutpost/oa/caves/undercity,
		/area/cadiaoutpost/oa/caves/terror
	), 'sound/newmusic/Caves_Dark.ogg')
