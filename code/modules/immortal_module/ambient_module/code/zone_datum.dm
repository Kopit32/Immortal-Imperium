// ============================================================================
// /datum/zone_audio — Flyweight: один датум на тип зоны (или группу зон),
// шарится всеми игроками. Только контент, без состояния.
// ============================================================================

/datum/zone_audio
    var/silent = FALSE             // тихая зона (космос и т.п.)
    var/name = ""
    var/ambient_volume = PA_AMBIENT_VOLUME
    var/list/ambient = list()      // 'файл' = вес (взвешенный выбор)
    var/list/combat = list()       // 'файл'
    var/list/bed = list()          // 'файл' = вес: тихий луп-подклад, звучит между окнами
    var/bed_volume = PA_BED_VOLUME
    var/silence_min = 0            // сек тишины между окнами (0 -> глобальный дефолт)
    var/silence_max = 0

/datum/zone_audio/New(_name)
    if(_name)
        name = _name

/datum/zone_audio/proc/pick_ambient()
    return ambient.len ? pickweight(ambient) : null

/datum/zone_audio/proc/pick_bed()
    if(!bed.len)
        return null
    for(var/track in bed)
        return track
    return null