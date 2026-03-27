-- Forest Meanies Mod
-- Requires mobs_redo

local S = minetest.get_translator(minetest.get_current_modname())

if not mobs then
    error("[forest_meanies] mobs_redo is required but not found!")
end

local NOTICE_RANGE = 22
local AGGRO_RANGE = 8
local STALK_VELOCITY = 3.2

local HOME_RADIUS = 25
local PATROL_RADIUS = 5

local HUNTER_CHANCE = 10
local HUNTER_RUN_VELOCITY = 6.0

local DAYLIGHT_BURN_LEVEL = 12
local DAYLIGHT_BURN_DAMAGE = 8
local BURN_FIRE_GAIN = 0.6
local BURN_ROAR_GAIN = 1.0

local WIPE_TIME = 0.35
local WIPE_WINDOW = 0.03

local function flat_distance(a, b)
    if not a or not b then return nil end
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function true_distance(a, b)
    if not a or not b then return nil end
    return vector.distance(a, b)
end

local function move_toward(self, pos, speed)
    local obj = self.object
    if not obj then return end

    local my_pos = obj:get_pos()
    if not my_pos or not pos then return end

    local dir = vector.direction(my_pos, pos)
    local vel = vector.multiply(dir, speed)
    vel.y = obj:get_velocity().y
    obj:set_velocity(vel)
    obj:set_yaw(math.atan2(dir.z, dir.x) - math.pi / 2)
end

local function stop_horizontal(self)
    if not self.object then return end
    local v = self.object:get_velocity()
    self.object:set_velocity({x = 0, y = v.y, z = 0})
end

local function fade_stop_whisper(self)
    if not self.whisper_sound_id then return end

    local handle = self.whisper_sound_id
    self.whisper_sound_id = nil

    minetest.sound_fade(handle, 0.8, 0.01)
    minetest.after(0.45, function()
        minetest.sound_stop(handle)
    end)
end

local function fade_stop_roar(self)
    if not self.roar_sound_id then return end

    local handle = self.roar_sound_id
    self.roar_sound_id = nil

    minetest.sound_fade(handle, 0.6, 0.01)
    minetest.after(0.35, function()
        minetest.sound_stop(handle)
    end)
end

local function stop_whisper_now(self)
    if not self.whisper_sound_id then return end
    minetest.sound_stop(self.whisper_sound_id)
    self.whisper_sound_id = nil
end

local function stop_burn_fire(self)
    if not self.burn_fire_sound_id then return end
    minetest.sound_stop(self.burn_fire_sound_id)
    self.burn_fire_sound_id = nil
end

local function stop_burn_roar(self)
    if not self.burn_roar_sound_id then return end
    minetest.sound_stop(self.burn_roar_sound_id)
    self.burn_roar_sound_id = nil
end

local function play_burn_fire(self)
    if self.burn_fire_sound_id then return end
    self.burn_fire_sound_id = minetest.sound_play("fire_fire", {
        object = self.object,
        gain = BURN_FIRE_GAIN,
        max_hear_distance = 16,
        loop = true,
    })
end

local function play_burn_roar(self)
    if self.burn_roar_sound_id then return end
    self.burn_roar_sound_id = minetest.sound_play("forest_meanie_roar", {
        object = self.object,
        gain = BURN_ROAR_GAIN,
        max_hear_distance = NOTICE_RANGE,
        loop = true,
    })
end

local function do_melee_damage(self, target, dtime)
    if not self.object or not target or not target:is_player() then return end

    local my_pos = self.object:get_pos()
    local target_pos = target:get_pos()
    local dist = true_distance(my_pos, target_pos)

    self.attack_cooldown = self.attack_cooldown or 0
    self.attack_cooldown = math.max(0, self.attack_cooldown - dtime)

    if dist and dist <= 2.2 and self.attack_cooldown <= 0 then
        target:punch(self.object, 1.0, {
            full_punch_interval = 1.0,
            damage_groups = {fleshy = self.damage or 8},
        }, nil)

        self.attack_cooldown = 1.0
    end
end

local function burn_in_daylight(self, dtime, pos)
    if not self.object then return end

    self.daylight_burn_timer = (self.daylight_burn_timer or 0) + dtime
    self.daylight_fx_timer = (self.daylight_fx_timer or 0) + dtime

    if self.daylight_fx_timer >= 0.15 then
        self.daylight_fx_timer = 0

        -- flames across the whole body
        minetest.add_particlespawner({
            amount = 14,
            time = 0.15,
            minpos = {x = pos.x - 0.45, y = pos.y + 0.1, z = pos.z - 0.25},
            maxpos = {x = pos.x + 0.45, y = pos.y + 1.95, z = pos.z + 0.25},
            minvel = {x = -0.08, y = 0.25, z = -0.08},
            maxvel = {x =  0.08, y = 0.85, z =  0.08},
            minacc = {x = 0, y = 0.2, z = 0},
            maxacc = {x = 0, y = 0.5, z = 0},
            minexptime = 0.3,
            maxexptime = 0.7,
            minsize = 3,
            maxsize = 6,
            texture = "fire_basic_flame.png",
            glow = 8,
        })

        -- smoke column above head (~2 nodes high)
        minetest.add_particlespawner({
            amount = 8,
            time = 0.25,
            minpos = {x = pos.x - 0.18, y = pos.y + 2.1, z = pos.z - 0.18},
            maxpos = {x = pos.x + 0.18, y = pos.y + 2.4, z = pos.z + 0.18},
            minvel = {x = -0.04, y = 0.8, z = -0.04},
            maxvel = {x =  0.04, y = 1.3, z =  0.04},
            minacc = {x = 0, y = 0.05, z = 0},
            maxacc = {x = 0, y = 0.15, z = 0},
            minexptime = 1.0,
            maxexptime = 1.6,
            minsize = 4,
            maxsize = 7,
            texture = "default_cloud.png",
        })
    end

    if self.daylight_burn_timer >= 1.0 then
        self.daylight_burn_timer = 0
        self.object:set_hp(self.object:get_hp() - DAYLIGHT_BURN_DAMAGE)
    end
end

local function get_orbit_target(self)
    if not self.home_pos then return nil end

    self.orbit_angle = self.orbit_angle or (math.random() * math.pi * 2)
    self.orbit_radius = self.orbit_radius or (4 + math.random())
    self.orbit_dir = self.orbit_dir or (math.random(0, 1) == 0 and -1 or 1)

    local x = self.home_pos.x + math.cos(self.orbit_angle) * self.orbit_radius
    local z = self.home_pos.z + math.sin(self.orbit_angle) * self.orbit_radius

    local base = {
        x = x,
        y = self.home_pos.y,
        z = z
    }

    for y = 4, -6, -1 do
        local check = {x = base.x, y = base.y + y, z = base.z}
        local above = {x = check.x, y = check.y + 1, z = check.z}
        local below = {x = check.x, y = check.y - 1, z = check.z}

        local node = minetest.get_node_or_nil(check)
        local above_node = minetest.get_node_or_nil(above)
        local below_node = minetest.get_node_or_nil(below)

        if node and above_node and below_node then
            local nd = minetest.registered_nodes[node.name]
            local ad = minetest.registered_nodes[above_node.name]
            local bd = minetest.registered_nodes[below_node.name]

            if nd and ad and bd and not nd.walkable and not ad.walkable and bd.walkable then
                return check
            end
        end
    end

    return nil
end

local function advance_orbit(self, amount)
    self.orbit_angle = (self.orbit_angle or 0) + amount * (self.orbit_dir or 1)
end

mobs:register_mob("forest_meanies:meanie", {
    type = "monster",
    passive = false,
    attack_players = true,
    attack_type = "dogfight",

    reach = 2,
    damage = 8,

    hp_min = 80,
    hp_max = 120,
    armor = 80,

    collisionbox = {-0.35, 0.0, -0.35, 0.35, 1.9, 0.35},
    selectionbox = {-0.35, 0.0, -0.35, 0.35, 1.9, 0.35},

    visual = "mesh",
    mesh = "forest_meanie.b3d",
    textures = {{"forest_meanie.png"}},
    visual_size = {x = 1.08, y = 1.08},
    glow = 3,

    makes_footstep_sound = true,
    sounds = {
        random = "forest_meanie_roar",
    },

    walk_velocity = 1.2,
    run_velocity = 4.5,
    view_range = 25,

    jump = true,
    stepheight = 1.1,
    fear_height = 4,

    lava_damage = 5,
    light_damage = 0,
    water_damage = 1,

    knock_back = 1,
    blood_amount = 15,

    animation = {
        speed_normal = 15,
        speed_run = 25,
        stand_start = 0,
        stand_end = 79,
        walk_start = 168,
        walk_end = 187,
        run_start = 168,
        run_end = 187,
        punch_start = 200,
        punch_end = 219,
    },

    do_custom = function(self, dtime)
        self.sound_timer = self.sound_timer or 0
        self.orbit_timer = self.orbit_timer or 0
        self.wipe_checked = self.wipe_checked or false
        self.meanie_state = self.meanie_state or "orbiting"
        self.roared = self.roared or false
        self.whisper_sound_id = self.whisper_sound_id or nil
        self.roar_sound_id = self.roar_sound_id or nil
        self.burn_fire_sound_id = self.burn_fire_sound_id or nil
        self.burn_roar_sound_id = self.burn_roar_sound_id or nil
        self.attack_cooldown = self.attack_cooldown or 0
        self.daylight_burn_timer = self.daylight_burn_timer or 0
        self.daylight_fx_timer = self.daylight_fx_timer or 0
        self.home_pos = self.home_pos or vector.round(self.object:get_pos())

        if self.is_hunter == nil then
            self.is_hunter = (math.random(1, 100) <= HUNTER_CHANCE)
        end

        local pos = self.object:get_pos()
        if not pos then return end

        local tod = minetest.get_timeofday()
        local in_wipe_window = tod >= WIPE_TIME and tod < (WIPE_TIME + WIPE_WINDOW)

        if in_wipe_window and not self.wipe_checked then
            self.wipe_checked = true

            if self.meanie_state ~= "burning" then
                fade_stop_whisper(self)
                fade_stop_roar(self)
                stop_burn_fire(self)
                stop_burn_roar(self)
                self.object:remove()
                return
            end
        elseif not in_wipe_window then
            self.wipe_checked = false
        end

        local light = minetest.get_node_light(pos) or 0
        if light >= DAYLIGHT_BURN_LEVEL then
            self.attack = nil
            self.last_seen = nil
            self.roared = false
            self.meanie_state = "burning"
            stop_horizontal(self)
            fade_stop_whisper(self)
            fade_stop_roar(self)

            local heard_by_player = false
            for _, obj in ipairs(minetest.get_objects_inside_radius(pos, NOTICE_RANGE)) do
                if obj:is_player() then
                    heard_by_player = true
                    break
                end
            end

            if heard_by_player then
                play_burn_fire(self)
                play_burn_roar(self)
            else
                stop_burn_fire(self)
                stop_burn_roar(self)
            end

            self.object:set_animation({x = 200, y = 219}, 35, 0, true)

            burn_in_daylight(self, dtime, pos)
            return
        end

        stop_burn_fire(self)
        stop_burn_roar(self)

        local chase_speed = self.is_hunter and HUNTER_RUN_VELOCITY or self.run_velocity

        self.sound_timer = math.max(0, self.sound_timer - dtime)
        self.orbit_timer = math.max(0, self.orbit_timer - dtime)

        local nearby_players = {}
        for _, obj in ipairs(minetest.get_objects_inside_radius(pos, NOTICE_RANGE + 12)) do
            if obj:is_player() then
                local ppos = obj:get_pos()
                if ppos and flat_distance(pos, ppos) <= NOTICE_RANGE then
                    table.insert(nearby_players, obj)
                end
            end
        end

        local target = nearby_players[1]
        local dist = target and flat_distance(pos, target:get_pos()) or nil

        if target then
            self.last_seen = vector.new(target:get_pos())

            if dist and dist <= AGGRO_RANGE then
                self.meanie_state = "aggressive"
            else
                self.meanie_state = "stalking"
            end
        else
            self.attack = nil

            if self.is_hunter and self.last_seen then
                self.meanie_state = "searching"
            else
                self.last_seen = nil

                if self.home_pos and flat_distance(pos, self.home_pos) > 2 then
                    self.meanie_state = "returning_home"
                else
                    self.roared = false
                    fade_stop_roar(self)
                    self.meanie_state = "orbiting"
                end
            end
        end

        if self.meanie_state == "aggressive" and target then
            stop_whisper_now(self)

            if not self.roar_sound_id then
                self.roar_sound_id = minetest.sound_play("forest_meanie_roar", {
                    object = self.object,
                    gain = 1.6,
                    max_hear_distance = 32,
                    loop = true,
                })
            end

            self.roared = true

        elseif self.meanie_state == "stalking" and target and dist and dist > AGGRO_RANGE and dist <= NOTICE_RANGE then
            fade_stop_roar(self)

            if self.sound_timer <= 0 and not self.whisper_sound_id then
                self.whisper_sound_id = minetest.sound_play("forest_meanie_whisper", {
                    object = self.object,
                    gain = 0.5,
                    loop = true,
                    max_hear_distance = NOTICE_RANGE
                })
                self.sound_timer = 3
            end
        else
            fade_stop_whisper(self)
            fade_stop_roar(self)
        end

        if self.meanie_state == "stalking" and target then
            self.attack = nil
            move_toward(self, target:get_pos(), STALK_VELOCITY)

        elseif self.meanie_state == "aggressive" and target then
            self.attack = target

            if dist and dist > 1.2 then
                move_toward(self, target:get_pos(), chase_speed)
            else
                stop_horizontal(self)
            end

            do_melee_damage(self, target, dtime)

        elseif self.meanie_state == "searching" and self.last_seen then
            self.attack = nil
            move_toward(self, self.last_seen, self.walk_velocity)

            if flat_distance(pos, self.last_seen) < 1.5 then
                self.last_seen = nil
                self.roared = false
                fade_stop_roar(self)

                if self.home_pos and flat_distance(pos, self.home_pos) > 2 then
                    self.meanie_state = "returning_home"
                else
                    self.meanie_state = "orbiting"
                end
            end

        elseif self.meanie_state == "returning_home" and self.home_pos then
            self.attack = nil
            self.roared = false
            fade_stop_roar(self)

            if flat_distance(pos, self.home_pos) > 1.5 then
                move_toward(self, self.home_pos, self.walk_velocity)
            else
                stop_horizontal(self)
                self.orbit_timer = 0
                self.meanie_state = "orbiting"
            end

        elseif self.meanie_state == "orbiting" and self.home_pos then
            self.attack = nil
            self.roared = false
            fade_stop_roar(self)

            if self.orbit_timer <= 0 or not self.orbit_target or flat_distance(pos, self.orbit_target) < 1.5 then
                advance_orbit(self, 0.8)
                self.orbit_target = get_orbit_target(self)
                self.orbit_timer = 1.5
            end

            if self.orbit_target then
                move_toward(self, self.orbit_target, self.walk_velocity)
            else
                stop_horizontal(self)
            end
        end
    end,

    on_spawn = function(self)
        local pos = self.object:get_pos()
        self.home_pos = pos and vector.round(pos) or nil
        self.is_hunter = (math.random(1, 100) <= HUNTER_CHANCE)
        self.orbit_angle = math.random() * math.pi * 2
        self.orbit_radius = 4 + math.random()
        self.orbit_dir = (math.random(0, 1) == 0 and -1 or 1)
        self.orbit_timer = 0
        self.orbit_target = get_orbit_target(self)

        self.object:set_properties({
            visual_size = {x = 1.08, y = 1.08}
        })
    end,

    on_death = function(self)
        fade_stop_whisper(self)
        fade_stop_roar(self)
        stop_burn_fire(self)
        stop_burn_roar(self)
    end,
})

mobs:spawn({
    name = "forest_meanies:meanie",
    nodes = {"default:dirt_with_grass"},
    neighbors = {"group:tree"},
    min_light = 0,
    max_light = 7,
    interval = 30,
    chance = 9000,
    active_object_count = 8,
    min_height = 1,
    max_height = 200,
})

mobs:register_egg("forest_meanies:meanie", "Forest Meanie", "default_tree.png", 1)
