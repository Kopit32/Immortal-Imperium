// ============================================================================
// /datum/audio_layer — один канал BYOND + экспоненциальный фейд к целевой
// громкости (fade-by-target): включение, глушение и рестарт — одна операция
// «задать цель», дребезг безопасен by design. Экспонента — под логарифмичность
// слуха (ровное затухание в децибелах).
//
// linger: на громкости 0 BYOND продолжает беззвучно крутить трек. Канал
// удерживается linger ds (combat: повторный вход продолжит трек) либо пока
// держится hold_muted (ambient/bed: пауза на время боя/смерти/окна).
//
// ВАЖНО: active = «канал зарезервирован нами», а не «звук слышен». Окончание
// не-лупящегося трека задаётся вручную при play() и считается по play_end.
// ============================================================================

/datum/audio_layer
    var/datum/component/player_audio/owner
    var/channel = 0
    var/sound/snd = null       // кэш: громкость обновляется перепосылкой этого же датума
    var/current_file = null
    var/base = 0               // «сырая» громкость трека (без мьютов)
    var/volume_cur = 0
    var/volume_target = 0
    var/tau = 1                // сек
    var/linger = 0             // ds удержания канала на нуле
    var/hold_muted = FALSE     // внешний мьют: на нуле канал не убивать (пишет только remix)
    var/active = FALSE         // канал занят
    var/track_duration = 0     // ds: длительность текущего трека; 0 = неизвестна
    var/play_end = 0           // ds: когда кончится не-лупящийся трек; 0 = луп/неизвестно
    var/linger_until = 0
    var/last_sent = -1

/datum/audio_layer/New(datum/component/player_audio/_owner, _channel, _tau, _linger)
    owner = _owner
    channel = _channel
    tau = _tau
    linger = _linger

/datum/audio_layer/Destroy()
    kill()
    owner = null
    return ..()

// Запросить трек. Тот же трек ещё слышимо играет (пусть и затухает) —
// продолжаем. Слышимо играет другой — отказ (вызывающий сделает ретрай).
// Канал с ДОИГРАВШИМ треком (play_end прошёл) не считается занятым.
/datum/audio_layer/proc/play(new_file, new_base, duration_ds = 0, repeat = TRUE)
    if(!new_file)
        return FALSE
    // continue только пока громкость не на нуле: на нуле канал либо в linger
    // с возможно доигравшим треком — тогда честный рестарт, иначе «привидение»
    if(active && current_file == new_file && volume_cur > 0 \
            && (!play_end || world.time < play_end))
        base = new_base
        volume_target = new_base
        if(volume_target > 0)
            linger_until = 0
        return TRUE
    if(active && volume_cur > 0 && (!play_end || world.time < play_end))
        return FALSE // реально слышно играет другой трек
    kill()
    current_file = new_file
    base = new_base
    track_duration = duration_ds
    snd = sound(new_file, repeat, 0, channel, 0)
    play_end = (!repeat && track_duration > 0) ? world.time + track_duration : 0
    volume_cur = 0
    volume_target = new_base
    last_sent = 0
    active = TRUE
    owner.send_sound(src)
    return TRUE

/datum/audio_layer/proc/set_volume_target(target)
    volume_target = max(0, min(100, target))
    if(volume_target > 0)
        linger_until = 0

/datum/audio_layer/proc/fade_out()
    volume_target = 0
    base = 0

// Мгновенно освободить канал.
/datum/audio_layer/proc/kill()
    if(active)
        owner.send_stop(channel)
    active = FALSE
    current_file = null
    snd = null
    base = 0
    track_duration = 0
    volume_cur = 0
    volume_target = 0
    play_end = 0
    last_sent = -1
    linger_until = 0

// Тик: dt в секундах.
/datum/audio_layer/proc/tick(dt)
    if(!active)
        return
    if(volume_cur != volume_target)
        var/growth = MATH_E ** (dt / tau)
        if(volume_cur < volume_target)
            if(volume_cur < 1)
                volume_cur = 1 // старт с ~-40 дБ вместо «хлопка» с нуля
            volume_cur *= growth
            if(volume_cur >= volume_target - 0.75)
                volume_cur = volume_target
        else
            volume_cur /= growth
            if(volume_cur <= volume_target + 0.75)
                volume_cur = volume_target
            else if(volume_target == 0 && volume_cur <= PA_VOL_FLOOR)
                volume_cur = 0 // хвост ниже слышимости не тянем
    var/to_send = round(volume_cur)
    if(to_send != last_sent && snd)
        snd.volume = to_send
        snd.status = SOUND_UPDATE
        owner.send_sound(src)
        last_sent = to_send
    if(volume_target == 0 && volume_cur == 0)
        if(hold_muted)
            return // канал держится беззвучно до конца внешнего мьюта
        if(linger > 0)
            if(!linger_until)
                linger_until = world.time + linger
            else if(world.time >= linger_until)
                kill()
        else
            kill()