// ============================================================================
// /datum/component/player_audio — весь звук игрока: три слоя (bed-подклад,
// окна эмбиента, боевая музыка), микс-матрица, единственная точка вывода
// к клиенту. Вешается автоматически (SSplayer_audio.fire).
// Потеря клиента -> pause(), возврат -> resume().
// Приоритет: бой > окно эмбиента > bed. Слой ниже приоритетом глушится
// с удержанием канала (hold_muted) — треки продолжаются беззвучно и
// возвращаются с того же места.
// Концы треков — из ручного реестра длительностей (считает слой в play_end).
// Файл без читаемой длины доиграет в тишину и заблокирует канал до
// перетогла боя/смерти/потери клиента — держите треки в .ogg.
// ============================================================================

/datum/component/player_audio
    dupe_mode = COMPONENT_DUPE_HIGHLANDER

    var/datum/audio_layer/bed
    var/datum/audio_layer/ambient
    var/datum/audio_layer/combat
    var/datum/zone_audio/played_zone // чей плейлист играл (тайминги паузы)
    var/datum/zone_audio/bed_zone    // чей bed играет сейчас
    var/pause_until = 0              // ds: пауза, назначаемая доигравшим треком
    var/combat_phase = PA_PHASE_OFF
    var/combat_hold_until = 0
    var/combat_retry_until = 0       // ds: ретрай, если боевой трек не стартовал
    var/ambient_cooldown_frozen_at = 0 // ds: начало паузы cooldown на время боя
    var/bed_switch_ok = 0            // ds: гистерезис смены bed-трека
    var/was_active = FALSE

/datum/component/player_audio/Initialize()
    bed = new(src, CHANNEL_PA_BED, PA_BED_SLEW, 0)
    ambient = new(src, CHANNEL_PA_AMBIENT, PA_AMBIENT_SLEW, 0)
    combat = new(src, CHANNEL_PA_COMBAT, PA_COMBAT_SLEW, PA_COMBAT_LINGER)
    SSplayer_audio.register_component(src)
    if(read_combat_var())
        set_combat_mode(TRUE)
    pause_until = world.time + rand(30 SECONDS, 2 MINUTES)
    remix(is_muted())
    return ..()

/datum/component/player_audio/RegisterWithParent()
    RegisterSignal(parent, COMSIG_MOB_COMBAT_TOGGLED, PROC_REF(on_combat_toggled))

/datum/component/player_audio/UnregisterFromParent()
    UnregisterSignal(parent, COMSIG_MOB_COMBAT_TOGGLED)

/datum/component/player_audio/Destroy()
    SSplayer_audio.unregister_component(src)
    QDEL_NULL(bed)
    QDEL_NULL(ambient)
    QDEL_NULL(combat)
    return ..()

// ---- Комбат-мод -------------------------------------------------------------
// Контракт: SEND_SIGNAL(mob, COMSIG_MOB_COMBAT_TOGGLED, mob, <значение>).
// Толерантен к формам (value) и (src).
/datum/component/player_audio/proc/on_combat_toggled(value, second)
    var/state
    if(!isnull(second))
        state = second
    else if(isnull(value) || ismob(value))
        state = read_combat_var()
    else
        state = value
    set_combat_mode(state ? TRUE : FALSE)

/datum/component/player_audio/proc/read_combat_var()
    #ifdef DEBUG
    if(!(PA_COMBAT_VAR in parent.vars))
        CRASH("player_audio: у [parent] нет переменной [PA_COMBAT_VAR]")
    #endif
    return parent.vars[PA_COMBAT_VAR]


/datum/component/player_audio/proc/set_combat_mode(on)
    if(on)
        if(combat_phase == PA_PHASE_ATTACK)
            return
        combat_phase = PA_PHASE_ATTACK
        combat_hold_until = 0
        // Трек продолжается с того же места, пока жив канал: слышимо играет,
        // затухает (HOLD/FADE) или крутится беззвучно в linger (7 сек после
        // затухания). Новый трек — только если слой убит или трек доиграл.
        // Громкость поднимет remix: base сохранён, target вернётся к base.
        if(!combat.active || (combat.play_end && world.time >= combat.play_end))
            start_combat_track()
    else if(combat_phase != PA_PHASE_OFF)
        combat_phase = PA_PHASE_HOLD // анти-дребезг: музыка доигрывает окно
        combat_hold_until = world.time + PA_COMBAT_HOLD
        combat_retry_until = 0
    remix(is_muted())

// Зона/джоб читаются в момент выбора, не хранятся. repeat=FALSE: трек доигрывает
// и сменяется следующим из пула. rotating=TRUE — ротация по доигрыванию:
// текущий исключается из выбора; kill нужен и при том же файле — continue-ветка
// play() иначе «продолжила» бы доигравший канал с остаточной громкостью.
// Повторный вход в бой (rotating=FALSE) продолжает играющий трек.
/datum/component/player_audio/proc/start_combat_track(rotating = FALSE)
    var/area/A = get_area(parent)
    var/exclude = rotating ? combat.current_file : null
    var/track = SSplayer_audio.pick_combat_track(parent, A ? A.type : null, exclude)
    if(!track)
        // пул пуст: доигравший слой глушим, чтобы микс не держал «бой» вечно
        if(combat.active && combat.play_end && world.time >= combat.play_end)
            combat.kill()
        combat_retry_until = world.time + PA_COMBAT_RETRY
        return
    if(rotating && combat.active && track == combat.current_file)
        combat.kill()
    var/duration_ds = SSplayer_audio.get_track_duration(track) * 10
    if(combat.play(track, PA_COMBAT_VOLUME, duration_ds, FALSE))
        combat_retry_until = 0
    else
        combat_retry_until = world.time + PA_COMBAT_RETRY

// ---- Тик --------------------------------------------------------------------
/datum/component/player_audio/proc/tick(dt)
    if(QDELETED(src) || !parent)
        return
    var/mob/M = parent
    if(!M.client)
        if(was_active)
            pause()
        return
    if(!was_active)
        resume()
    if(combat_phase == PA_PHASE_HOLD && world.time >= combat_hold_until)
        combat_phase = PA_PHASE_FADE
    if(combat_phase == PA_PHASE_FADE && !combat.active)
        combat_phase = PA_PHASE_OFF
    if(combat.active && combat_phase != PA_PHASE_OFF && !ambient_cooldown_frozen_at)
        ambient_cooldown_frozen_at = world.time
    else if((combat_phase == PA_PHASE_OFF || !combat.active) && ambient_cooldown_frozen_at)
        if(pause_until)
            pause_until += world.time - ambient_cooldown_frozen_at
        ambient_cooldown_frozen_at = 0
    // боевой трек доиграл — следующий из пула, не тот же
    if(combat_phase == PA_PHASE_ATTACK && combat.active && combat.play_end && world.time >= combat.play_end)
        start_combat_track(TRUE)
    // боя нет (отказ play, слой погиб в linger) — добираем, с ретрай-гейтом
    else if(combat_phase == PA_PHASE_ATTACK && !combat.active && world.time >= combat_retry_until)
        start_combat_track()
    poll_ambient()
    poll_bed()
    remix(is_muted())
    bed.tick(dt)
    ambient.tick(dt)
    combat.tick(dt)

// Анти-дребезг: окна назначает доигравший трек; под боем и в смерти новых нет.
/datum/component/player_audio/proc/poll_ambient()
    // (1) доигравший трек назначает окно тишины (в любой фазе, даже в бою)
    if(ambient.base > 0 && !pause_until && ambient.play_end && world.time >= ambient.play_end)
        var/smin = (played_zone && played_zone.silence_min) || PA_AMBIENT_SILENCE_MIN
        var/smax = (played_zone && played_zone.silence_max) || PA_AMBIENT_SILENCE_MAX
        pause_until = world.time + rand(smin, smax) * 10
    // (2) окно отыто: канал уводим fade_out — слой сам умрёт на нуле
    if(ambient.base > 0 && pause_until && world.time >= pause_until)
        ambient.fade_out()
        pause_until = 0
    // (3) под боем новых окон нет
    if(combat_phase == PA_PHASE_ATTACK || combat_phase == PA_PHASE_HOLD)
        return
    // (4) мёртв — эмбиентом не управляем
    if(is_muted())
        return
    // (5) звучит или вежливо затухает — не трогаем
    if(ambient.active || ambient.hold_muted)
        return
    // (6) персональная пауза ещё тикает
    if(pause_until && world.time < pause_until)
        return
    fire_ambient()

// Bed-подклад: один зацикленный трек текущей зоны, как в legacy-системе.
// Играет только когда всё остальное молчит (решает remix), а при смене зоны
// старый трек затухает перед запуском нового.
/datum/component/player_audio/proc/poll_bed()
    var/area/A = get_area(parent)
    var/datum/zone_audio/Z = A ? SSplayer_audio.resolve_zone(A.type) : null
    if(!bed.active)
        bed_zone = null
    if(Z && Z == bed_zone && bed.active && bed.current_file)
        bed.base = Z.bed_volume // конфиг могли обновить на ходу
        return
    var/track
    if(Z && !Z.silent && Z.bed.len)
        track = Z.pick_bed()
    if(!track)
        bed_zone = null
        if(bed.base > 0)
            bed.fade_out()
        return
    if(bed.active && bed.current_file != track && bed.volume_cur > 0)
        bed.fade_out() // чужой трек ещё слышим — уводим, займём после тишины
        bed_zone = null
        return
    if(bed.play(track, Z.bed_volume, 0, TRUE))
        bed_zone = Z
        bed_switch_ok = world.time + PA_BED_SWITCH_MIN

/datum/component/player_audio/proc/fire_ambient()
    var/area/A = get_area(parent)
    var/datum/zone_audio/Z = A ? SSplayer_audio.resolve_zone(A.type) : null
    if(!Z || Z.silent || !Z.ambient.len)
        pause_until = world.time + PA_SILENT_RECHECK // тихая/незарегистрированная
        return
    if(ambient.volume_cur > 0)
        pause_until = world.time + rand(PA_RETRY_MIN, PA_RETRY_MAX) // канал ещё затухает
        return
    var/track = Z.pick_ambient()
    var/duration_ds = SSplayer_audio.get_track_duration(track) * 10
    if(!track || !ambient.play(track, Z.ambient_volume, duration_ds, FALSE))
        pause_until = world.time + rand(PA_RETRY_MIN, PA_RETRY_MAX)
        return
    played_zone = Z
    pause_until = 0

// Микс-матрица: единственное место, где решается, ЧТО и КАК ГРОМКО звучит.
// Окно «живо» до конца трека (play_end слоя); после — bed встаёт в тишину
// между окнами. Затухающий хвост (base уже 0) bed по-прежнему уважает.
/datum/component/player_audio/proc/remix(muted)
    var/in_combat = combat.base > 0 && (combat_phase == PA_PHASE_ATTACK || combat_phase == PA_PHASE_HOLD)
    var/window_live = (ambient.base > 0 && ambient.play_end && world.time < ambient.play_end) \
        || (ambient.base == 0 && ambient.volume_cur > PA_VOL_FLOOR)
    var/bed_down = muted || in_combat || window_live
    ambient.hold_muted = in_combat || muted
    ambient.set_volume_target(muted || in_combat ? 0 : ambient.base)
    bed.hold_muted = bed_down
    bed.set_volume_target(bed_down || !bed.base ? 0 : bed.base)
    combat.set_volume_target(in_combat && !muted ? combat.base : 0)

/datum/component/player_audio/proc/is_muted()
    var/mob/living/L = parent
    return istype(L) && L.stat >= DEAD

// Потеря клиента: гасим всё, состояние сбрасываем.
/datum/component/player_audio/proc/pause()
    was_active = FALSE
    played_zone = null
    pause_until = 0
    combat_phase = PA_PHASE_OFF
    combat_hold_until = 0
    combat_retry_until = 0
    ambient_cooldown_frozen_at = 0
    bed.kill()
    ambient.kill()
    combat.kill()

/datum/component/player_audio/proc/resume()
    was_active = TRUE
    // Первый тик вызывает resume() сразу после Initialize(), поэтому стартовый cooldown сохраняется.
    if(read_combat_var())
        set_combat_mode(TRUE)

// ---- Вывод: вся работа с клиентом только здесь ------------------------------
/datum/component/player_audio/proc/send_sound(datum/audio_layer/L)
    var/mob/M = parent
    if(M && M.client && L.snd)
        M.client << L.snd

/datum/component/player_audio/proc/send_stop(channel)
    var/mob/M = parent
    if(M && M.client)
        M.client << sound(null, 0, 0, channel)