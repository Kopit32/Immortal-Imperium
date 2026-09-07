// ============================================================================
// Player Audio: определения.
// Каналы 100-102: в билде не используются (playsound играет на канале 0).
// Тайминги — в децисекундах (ds, 10 = 1 сек), кроме помеченных «сек»
// (физика фейда и домен конфига зон).
// ============================================================================

// Имя переменной комбат-мода на мобе (страховка при возврате клиента)
#define PA_COMBAT_VAR "combat_mode"

#ifndef PROC_REF
#define PROC_REF(X) (nameof(.proc/##X))
#endif

// Каналы
#define CHANNEL_PA_AMBIENT 100
#define CHANNEL_PA_COMBAT  101
#define CHANNEL_PA_BED     102

#ifndef SOUND_UPDATE
#define SOUND_UPDATE 1
#endif

// Фазы боевой музыки (State)
#define PA_PHASE_OFF    0
#define PA_PHASE_ATTACK 1
#define PA_PHASE_HOLD   2
#define PA_PHASE_FADE   3

// Тайминги, ds
#define PA_TICK_WAIT      2    // тик сабсистемы (0.2 сек): 5 Гц — ступенек фейда не слышно
#define PA_COMBAT_HOLD    20   // музыка доигрывает после выключения (2 сек)
#define PA_COMBAT_LINGER  150  // беззвучное удержание боевого канала (15 сек)
#define PA_COMBAT_RETRY   50   // ретрай поиска боевого трека (5 сек)
#define PA_RETRY_MIN      20   // страховочный ретрай эмбиента (2 сек)
#define PA_RETRY_MAX      40   // (4 сек)
#define PA_SILENT_RECHECK 600  // перепроверка тихой/пустой зоны (60 сек)
#define PA_BED_SWITCH_MIN 100  // гистерезис смены bed-трека (10 сек)

// Физика фейда, секунды («тау» e-шкалы: скорость ≈ 8.686/тау дБ/с)
#define PA_AMBIENT_SLEW 0.9  // ~9.7 дБ/с: эмбиент вкатывается ~3.5 с
#define PA_COMBAT_SLEW  0.4  // боевой вкат ~1.5-1.8 с: пик слышен уже в короткой стычке
#define PA_BED_SLEW     2.0  // ~4.3 дБ/с: подклад вкатывается медленно, ~6 с
#define PA_DT_CAP       1.0  // потолок dt: лаг не заминает фейд, но и не даёт прыжка
#define PA_VOL_FLOOR    2    // ниже — фейд в тишину считается доехавшим

// Громкость 0..100; дальше умножается на клиентский слайдер — потолок не здесь
#define PA_AMBIENT_VOLUME 25
#define PA_COMBAT_VOLUME  70
#define PA_BED_VOLUME     40

// Окна эмбиента, секунды (домен конфига зон)
#define PA_AMBIENT_SILENCE_MIN 300
#define PA_AMBIENT_SILENCE_MAX 480
#define PA_TRACK_TYPICAL       240 // оценка длины эмбиент-трека, если зона не задала track_len
#define PA_COMBAT_TRACK_LEN    180 // оценка длины боевого трека, если зона не задала combat_len

#define COMBAT_TRACK_HOLD_TIME 80 //Удержание проигрывания комбат трека после его отключения



#define MATH_E 2.7182
#define PA_AMBIENT_TAU    3.0   // сек: константа времени фейда эмбиента

// Длительности треков в секундах. BYOND не заполняет sound.len для этих OGG,
// поэтому конец одноразового трека считается по этому реестру.
GLOBAL_LIST_INIT(new_sound_system_tracks, list(
	'code/modules/immortal_module/ambient_module/sounds/ambient.ogg' = 105,
	'code/modules/immortal_module/ambient_module/sounds/city_ambient1_atoma_prime.ogg' = 233,
	'code/modules/immortal_module/ambient_module/sounds/city_ambient2_city_of_tertium.ogg' = 120,
	'code/modules/immortal_module/ambient_module/sounds/city_ambient3_imperium_of_man.ogg' = 160,
	'code/modules/immortal_module/ambient_module/sounds/city_ambient4_hive_city_lowers_levels.ogg' = 207,
	'code/modules/immortal_module/ambient_module/sounds/combat.ogg' = 180,
	'code/modules/immortal_module/ambient_module/sounds/combat_music/dispose_unite.ogg' = 213,
	'code/modules/immortal_module/ambient_module/sounds/combat_music/immortal_imperium.ogg' = 232,
	'code/modules/immortal_module/ambient_module/sounds/combat_music/imperial_advance.ogg' = 120,
	'code/modules/immortal_module/ambient_module/sounds/combat_music/light_of_imperium.ogg' = 272,
	'code/modules/immortal_module/ambient_module/sounds/combat_music/reject_unite.ogg' = 230
))

