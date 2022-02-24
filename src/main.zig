const std = @import("std");
const SDL = @import("sdl2");
const maths = std.math;
const rand = std.rand;

const Allocator = std.mem.Allocator;

const scancodes = SDL.c.SDL_Scancode;
const gl = SDL.gl;

const log = std.log.info;

const Point = struct {
    x: f32,
    y: f32,

    pub fn add(p1: Point, p2: Point) Point {
        return Point{
            .x = p1.x + p2.x,
            .y = p1.y + p2.y,
        };
    }

    pub fn sub(p1: Point, p2: Point) Point {
        return Point{
            .x = p1.x - p2.x,
            .y = p1.y - p2.y,
        };
    }

    pub fn len2(p: *Point) f32 {
        return p.x * p.x + p.y * p.y;
    }
    pub fn len(p: *Point) f32 {
        return @sqrt(p.x * p.x + p.y * p.y);
    }
    pub fn rot(p: *Point, angle: f32) void {
        const x = p.x;
        p.x = p.x * @cos(angle) - p.y * @sin(angle);
        p.y = p.y * @cos(angle) + x * @sin(angle);
    }
};

pub fn point(x: f32, y: f32) Point {
    return Point{ .x = x, .y = y };
}

const Player = struct {
    pos: Point = point(screen_width / 2, screen_height / 2),
    dpos: Point = point(200, 0),
    rotation: f32 = 0.0,
    rotation_speed: f32 = 0.0,
    dead: bool = false,
    const acceleration = 200;
    const rotation_acceleration = 50;
};

const number_of_bullets = 200;
const GameState = struct {
    score: u32 = 0,
    player: Player,
    // TODO: replace with heap allocated bullets
    bullets: [number_of_bullets]?Bullet,
    //TODO: replace array with O(n) allocation with stack
    // to keep track of free locations, init stack with size
    // of array and range 0..len-1, the pop every allocation
    // to find free index, push index whenever freed
    // OR do a sparse array :)
    asteroids: []?Asteroid,
    debris: []?Debris,
    allocator: *std.heap.ArenaAllocator,
    random: std.rand.Random,
    mode: GameMode,
    menuItem: u8 = 0,

    const Self = @This();
    pub fn play(self: *Self) void {
        self.menuItem = 0;
        self.mode = .Play;
    }

    pub fn restart(self: *Self) void {
        for (self.asteroids) |*a| a.* = null;
        for (self.debris) |*d| d.* = null;
        self.player = Player{};
        self.score = 0;
        timeOffset += timeSinceStart();
    }
};

const GameMode = enum { Play, Pause, MainMenu };

const InputData = struct {
    keystate: SDL.KeyboardState,
    keypressedstate: KeyboardWasPressedState,
    mousestate: SDL.MouseState,

    pub fn updatePressed(inpdata: InputData) void {
        for (inpdata.keypressedstate.states) |*k, i| {
            // if (k.* == 0 and inpdata.keystate.states[i] != 0) log("a - {}", .{~k.*});
            // if (k.* != 0 and inpdata.keystate.states[i] != 0) log("b - {}", .{~k.*});
            k.* = ~inpdata.keypressedstate.oldkeystates[i] & inpdata.keystate.states[i];
        }
        std.mem.copy(u8, inpdata.keypressedstate.oldkeystates, inpdata.keystate.states);
    }
};

var old_keystates_memory = [_]u8{0} ** 512;
var keystates_memory = [_]u8{0} ** 512;

const KeyboardWasPressedState = struct {
    states: []u8,
    oldkeystates: []u8,

    pub fn wasPressed(kwps: @This(), code: SDL.c.SDL_Scancode) bool {
        return kwps.states[@intCast(usize, @enumToInt(code))] != 0;
    }
};

const Bullet = struct {
    pos: Point,
    dpos: Point,
    age: f32,

    const speed = 500;
};

const number_of_asteroids = 30;
const Asteroid = struct {
    const num_points = 10;
    pos: Point,
    dpos: Point,
    geometry: [num_points]Point = undefined,
    transformed_geometry: [num_points]Point = undefined,
    max_radius: f32 = 0.0,
    rotation: f32 = 0.0,
    rotation_speed: f32 = 1,
};

// var asteroidGeometryBuffer: [100][Asteroid.num_points]Point = undefined;
// var asteroidGeometryBufferMaxs: [100]f32 = undefined;

const Debris = struct {
    pos: Point,
    dpos: Point,
    start_point: Point,
    end_point: Point,
    rotation: f32 = 0.0,
    rotation_speed: f32,
    const max_dpos = 30;
};

const screen_height = 480;
const screen_width = 600;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // var allocator = arena.allocator();

    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();

    var randgen = rand.DefaultPrng.init(std.crypto.random.int(u64));
    // var randgen = rand.DefaultPrng.init(0);

    var window = try SDL.createWindow(
        "Space Fighters",
        .{ .centered = {} },
        .{ .centered = {} },
        screen_width,
        screen_height,
        .{ .shown = true },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();

    var keystate = SDL.getKeyboardState();
    var keypressedstate = KeyboardWasPressedState{
        .states = old_keystates_memory[0..keystate.states.len],
        .oldkeystates = keystates_memory[0..keystate.states.len],
    };

    var inputstate = InputData{
        .keystate = keystate,
        .keypressedstate = keypressedstate,
        .mousestate = SDL.getMouseState(),
    };

    //    for (asteroidGeometryBuffer[0..]) |*geom, i| {
    //        var genResult = genAsteroidGeometry(&randgen.random, geom);
    //        asteroidGeometryBufferMaxs[i] = genResult.m;
    //    }

    var gamestate: GameState = undefined;
    try initGame(&gamestate, &arena, randgen.random());

    var last_time: u64 = SDL.getPerformanceCounter();
    var new_time: u64 = last_time;
    var dt: f32 = 0;
    const target: f32 = 1000.0 / 60.0;

    while (true) {
        const request_quit = try gameloop(&gamestate, &inputstate, dt);
        if (request_quit) break;

        try renderer.setColorRGB(0, 0, 0);
        try renderer.clear();

        try renderer.setColor(SDL.Color.parse("#FFFFFF") catch unreachable);
        try drawState(&renderer, &gamestate);

        renderer.present();

        // SDL.delay(10);

        new_time = SDL.getPerformanceCounter();
        dt = @intToFloat(f32, new_time - last_time) / @intToFloat(f32, SDL.getPerformanceFrequency());
        last_time = new_time;

        if (dt < target) SDL.delay(@floatToInt(u32, (target - dt)));

        // log("{d:.2} ms", .{dt * 1000});
    }
}

pub fn initGame(
    gamestate: *GameState,
    arena: *std.heap.ArenaAllocator,
    random: rand.Random,
) !void {
    var asteroids = try arena.allocator().alloc(?Asteroid, number_of_asteroids);
    for (asteroids) |*a| a.* = null;

    var debris = try arena.allocator().alloc(?Debris, number_of_asteroids * Asteroid.num_points);
    for (debris) |*d| d.* = null;

    gamestate.* = GameState{
        .player = Player{},
        .bullets = [_]?Bullet{null} ** number_of_bullets,
        .asteroids = asteroids,
        .debris = debris,
        .allocator = arena,
        .random = random,
        .mode = GameMode.Play,
    };
}

pub fn gameloop(gamestate: *GameState, input: *InputData, dt: f32) !bool {
    const player = &gamestate.player;
    const random = gamestate.random;
    const keystate = &input.keystate;
    const asteroids = gamestate.asteroids;

    while (SDL.pollEvent()) |ev| {
        switch (ev) {
            .quit => {
                return true;
            },
            else => {},
        }
    }

    input.updatePressed();

    if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_ESCAPE))
        gamestate.mode = switch (gamestate.mode) {
            .Play => .Pause,
            .Pause => .Play,
            else => unreachable,
        };

    // restart the game
    if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_R)) {
        gamestate.restart();
        return false;
    }

    if (gamestate.mode != GameMode.Play) {
        if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_DOWN)) {
            gamestate.menuItem += 1;
            gamestate.menuItem %= 3;
        }
        if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_UP)) {
            gamestate.menuItem += 2;
            gamestate.menuItem %= 3;
        }
        if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_RETURN) or
            input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_SPACE))
        {
            switch (gamestate.menuItem) {
                0 => gamestate.play(),
                1 => {
                    gamestate.restart();
                    gamestate.play();
                },
                2 => return true,
                else => unreachable,
            }
        }
    } else {
        if (input.keypressedstate.wasPressed(scancodes.SDL_SCANCODE_SPACE) and !player.dead) {
            createBullet(gamestate.bullets[0..], Bullet{
                .pos = transformed_player_geometry[0],
                .dpos = polarPoint(Bullet.speed, player.rotation).add(player.dpos),
                .age = timeSinceStart() + 1.0,
            });
        }

        if (!player.dead) {
            // if (keystate.isPressed(scancodes.SDL_SCANCODE_UP)) {
            //     player.dpos.x += Player.acceleration * @cos(player.rotation) * dt;
            //     player.dpos.y += Player.acceleration * @sin(player.rotation) * dt;
            // }
            // if (keystate.isPressed(scancodes.SDL_SCANCODE_DOWN)) {
            //     player.dpos.x -= Player.acceleration * @cos(player.rotation) * dt;
            //     player.dpos.y -= Player.acceleration * @sin(player.rotation) * dt;
            // }
            if (keystate.isPressed(scancodes.SDL_SCANCODE_LEFT)) {
                player.rotation_speed -= Player.rotation_acceleration * dt;
            }
            if (keystate.isPressed(scancodes.SDL_SCANCODE_RIGHT)) {
                player.rotation_speed += Player.rotation_acceleration * dt;
            }
        }

        timestepMovement(player, dt);
        player.dpos.rot(player.rotation_speed * dt);
        player.rotation_speed *= 1 - dt * 10;

        if (random.float(f32) < 0.001 * @log(1 + timeSinceStart()))
            createItem(Asteroid, asteroids, newAsteroid(random));

        asteroidloop: for (gamestate.asteroids) |*a| {
            if (a.* == null) continue;
            timestepMovement(&a.*.?, dt);

            const max_radius_sq = a.*.?.max_radius * a.*.?.max_radius;
            const apos = a.*.?.pos;
            for (gamestate.bullets) |*b| {
                if (b.* == null) continue;
                if (apos.sub(b.*.?.pos).len2() < max_radius_sq) {
                    var bpos1 = b.*.?.pos;
                    var bpos2 = bpos1.add(b.*.?.dpos);
                    var isColliding = brk: for (a.*.?.geometry[1..]) |_, j| {
                        if (doLinesCollide(
                            a.*.?.transformed_geometry[j],
                            a.*.?.transformed_geometry[j + 1],
                            bpos1,
                            bpos2,
                        )) break :brk true;
                    } else false;

                    if (isColliding) {
                        for (a.*.?.geometry[1..]) |_, j| {
                            const p1 = a.*.?.transformed_geometry[j];
                            const p2 = a.*.?.transformed_geometry[j + 1];
                            const midpoint = point((p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5);
                            createItem(Debris, gamestate.debris, Debris{
                                .pos = midpoint,
                                .dpos = point(
                                    random.float(f32) * 2 * Debris.max_dpos - Debris.max_dpos,
                                    random.float(f32) * 2 * Debris.max_dpos - Debris.max_dpos,
                                ),
                                .start_point = midpoint.sub(p1),
                                .end_point = midpoint.sub(p2),
                                .rotation_speed = random.float(f32) * 0.05 - 0.025,
                            });
                        }
                        a.* = null;
                        b.* = null;
                        gamestate.score += 10;
                        log("{}", .{gamestate.score});
                        continue :asteroidloop;
                    }
                }
            }

            var isCollidingWithPlayer = brk: for (a.*.?.geometry[1..]) |_, j| {
                for (transformed_player_geometry[1..]) |_, k| {
                    if (doLinesCollide(
                        a.*.?.transformed_geometry[j],
                        a.*.?.transformed_geometry[j + 1],
                        transformed_player_geometry[k],
                        transformed_player_geometry[k + 1],
                    )) break :brk true;
                }
            } else false;

            if (isCollidingWithPlayer) {
                player.dead = true;
            }
        }

        for (gamestate.bullets) |*b| {
            if (b.* == null) continue;
            if (b.*.?.age < timeSinceStart()) {
                b.* = null;
                continue;
            }

            timestepMovement(&b.*.?, dt);
        }

        for (gamestate.debris) |*d| {
            if (d.* == null) continue;
            var de = &d.*.?;
            de.pos.x += de.dpos.x * dt;
            de.pos.y += de.dpos.y * dt;
            de.start_point.rot(de.rotation_speed * dt);
            de.end_point.rot(de.rotation_speed);
            if (!pointRectAABB(de.pos, point(-10.0, -10.0), point(
                screen_width + 10,
                screen_height + 10,
            )).inside)
                d.* = null;
        }
    }

    return false;
}

pub fn drawState(renderer: *SDL.Renderer, state: *GameState) !void {
    try drawBullets(renderer, state.bullets[0..]);
    try drawAsteroids(renderer, state.asteroids);
    try drawDebris(renderer, state.debris);
    try drawMenu(renderer, state);
    try drawPlayer(renderer, &state.player);

    // try drawGeometry(renderer, characters.a[0..]);
}

const player_size = 16;
const player_geometry = [_]Point{
    polarPoint(player_size, 0.0),
    polarPoint(player_size, maths.pi * 5.0 / 6.0),
    polarPoint(player_size, maths.pi * 7.0 / 6.0),
    polarPoint(player_size, 0.0),
};

pub fn polarPoint(r: f32, t: f32) Point {
    return Point{
        .x = r * @cos(t),
        .y = r * @sin(t),
    };
}

var transformed_player_geometry: [player_geometry.len]Point = undefined;

pub fn drawAsteroids(renderer: *SDL.Renderer, asteroids: []?Asteroid) !void {
    for (asteroids) |*a| {
        if (a.* != null) {
            // log("Asteroid being renderered {}", .{a.?.pos.x});
            try drawTransformedShape(renderer, &a.*.?);
        }
    }
}

pub fn drawMenu(renderer: *SDL.Renderer, state: *GameState) !void {
    const cx = @divTrunc(screen_width, 2);
    const cy = @divTrunc(screen_height, 2);
    if (state.mode == .Pause) {
        try drawBox(renderer, cx, cy, 100, 25);
        try drawBox(renderer, cx, cy - 50, 100, 25);
        try drawBox(renderer, cx, cy + 50, 100, 25);

        const cursorPos = cy + 50 * (@as(i32, state.menuItem) - 1);
        try drawThickLine(renderer, cx - 75, cursorPos, cx - 85, cursorPos - 10);
        try drawThickLine(renderer, cx - 75, cursorPos, cx - 85, cursorPos + 10);
    }
}

pub fn drawPlayer(renderer: *SDL.Renderer, player: *Player) !void {
    if (player.dead)
        try renderer.setColor(SDL.Color.parse("#FF0000") catch unreachable);

    transformGeometry(player_geometry[0..], transformed_player_geometry[0..], &player.pos, player.rotation);

    try drawGeometry(renderer, transformed_player_geometry[0..]);
}

pub fn drawTransformedShape(renderer: *SDL.Renderer, shape: anytype) !void {
    transformGeometry(shape.geometry[0..], shape.transformed_geometry[0..], &shape.pos, shape.rotation);
    try drawGeometry(renderer, shape.transformed_geometry[0..]);
}

pub fn drawBullets(renderer: *SDL.Renderer, bullets: []?Bullet) !void {
    for (bullets) |b| {
        if (b != null) {
            const px = @floatToInt(i32, b.?.pos.x);
            const py = @floatToInt(i32, b.?.pos.y);
            try renderer.drawPoint(px, py);
            try renderer.drawPoint(px + 1, py);
            try renderer.drawPoint(px - 1, py);
            try renderer.drawPoint(px, py + 1);
            try renderer.drawPoint(px, py - 1);
        }
    }
}

pub fn drawDebris(renderer: *SDL.Renderer, debris: []?Debris) !void {
    for (debris) |d| {
        if (d != null) {
            try drawThickLine(
                renderer,
                @floatToInt(i32, d.?.start_point.x + d.?.pos.x),
                @floatToInt(i32, d.?.start_point.y + d.?.pos.y),
                @floatToInt(i32, d.?.end_point.x + d.?.pos.x),
                @floatToInt(i32, d.?.end_point.y + d.?.pos.y),
            );
        }
    }
}

pub fn drawBox(renderer: *SDL.Renderer, x: i32, y: i32, w: i32, h: i32) !void {
    const xoff = @divTrunc(w, 2);
    const yoff = @divTrunc(h, 2);

    try drawThickLine(renderer, x - xoff, y + yoff, x + xoff, y + yoff);
    try drawThickLine(renderer, x - xoff, y - yoff - 1, x + xoff, y - yoff - 1);
    try drawThickLine(renderer, x + xoff, y + yoff, x + xoff, y - yoff);
    try drawThickLine(renderer, x - xoff, y + yoff, x - xoff, y - yoff);
}

pub fn drawGeometry(renderer: *SDL.Renderer, geometry: []const Point) !void {
    // const r1 = point(0.0, 0.0);
    // const r2 = point(screen_width, screen_height);

    for (geometry[1..]) |point2, i| {
        const point1 = geometry[i];
        // const aabb1: AABBResult = pointRectAABB(point1, r1, r2);
        // const aabb2: AABBResult = pointRectAABB(point2, r1, r2);
        const p1xi32 = @floatToInt(i32, point1.x);
        const p1yi32 = @floatToInt(i32, point1.y);
        const p2xi32 = @floatToInt(i32, point2.x);
        const p2yi32 = @floatToInt(i32, point2.y);

        // dont even bother to check if you need to draw, just draw its cheap
        // if (aabb1.inside or aabb2.inside) {
        try drawThickLine(renderer, p1xi32, p1yi32, p2xi32, p2yi32);
        //        }
        //        if (aabb1.left or aabb2.left) {
        try drawThickLine(renderer, p1xi32 + screen_width, p1yi32, p2xi32 + screen_width, p2yi32);
        //        }
        //        if (aabb1.right or aabb2.right) {
        try drawThickLine(renderer, p1xi32 - screen_width, p1yi32, p2xi32 - screen_width, p2yi32);
        //        }
        //        if (aabb1.up or aabb2.up) {
        try drawThickLine(renderer, p1xi32, p1yi32 + screen_height, p2xi32, p2yi32 + screen_height);
        //        }
        //        if (aabb1.down or aabb2.down) {
        try drawThickLine(renderer, p1xi32, p1yi32 - screen_height, p2xi32, p2yi32 - screen_height);
        //        }
    }
}

pub fn drawThickLine(renderer: *SDL.Renderer, x0: i32, y0: i32, x1: i32, y1: i32) !void {
    try renderer.drawLine(x0, y0, x1, y1);
    try renderer.drawLine(1 + x0, y0, 1 + x1, y1);
    //try renderer.drawLine(x0 - 1, y0, x1 - 1, y1);
    try renderer.drawLine(x0, 1 + y0, x1, 1 + y1);
    //try renderer.drawLine(x0, y0 - 1, x1, y1 - 1);
}

pub fn transformGeometry(geometry: []const Point, result: []Point, translate: *const Point, rotation: f32) void {
    const crot = @cos(rotation);
    const srot = @sin(rotation);
    for (geometry) |p, i| {
        result[i] = Point{
            .x = p.x * crot - p.y * srot + translate.x,
            .y = p.x * srot + p.y * crot + translate.y,
        };
    }
}

pub fn mutWrapPoint(p: *Point) void {
    p.x = @mod(p.x, screen_width);
    p.y = @mod(p.y, screen_height);
}

pub fn deleteItem(comptime T: type, list: []?T, index: usize) void {
    list[index] = null;
}

pub fn createItem(comptime T: type, list: []?T, newItem: T) void {
    loop: for (list) |elem, i| {
        if (elem == null) {
            list[i] = newItem;
            break :loop;
        }
    }
}

pub fn deleteBullet(blist: []?Bullet, index: usize) void {
    deleteItem(Bullet, blist, index);
}

pub fn createBullet(blist: []?Bullet, newBullet: Bullet) void {
    createItem(Bullet, blist, newBullet);
}

const AABBResult = packed struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
    inside: bool = true,
};

pub fn pointRectAABB(p: Point, r1: Point, r2: Point) AABBResult {
    var result = AABBResult{};

    result.left = p.x < r1.x and p.x < r2.x;
    result.right = p.x > r1.x and p.x > r2.x;
    result.up = p.y < r1.y and p.y < r2.y;
    result.down = p.y > r1.y and p.y > r2.y;
    result.inside = !(result.left or result.right or result.down or result.up);
    return result;
}

const GenAsteroidGeometryResult = struct { g: []Point, m: f32 };
pub fn genAsteroidGeometry(r: rand.Random, geometry: []Point) f32 {
    // var rgen = rand.DefaultPrng.init(12321);
    // var geometry: []Point = allocator.alloc(Point, Asteroid.num_points) catch unreachable;

    var max_radius: f32 = 0.0;
    for (geometry[1..]) |_, i| {
        var dist = 20 * r.float(f32) + 6;
        if (dist > max_radius) max_radius = dist;
        geometry[i] = polarPoint(dist, 0.2222 * maths.pi * @intToFloat(f32, i));
    }

    geometry[0] = geometry[geometry.len - 1];

    return max_radius;
}

pub fn timestepMovement(entity: anytype, dt: f32) void {
    entity.pos.x += entity.dpos.x * dt;
    entity.pos.y += entity.dpos.y * dt;
    // log("x: {d:.4}    y: {d:.4}", .{ entity.pos.x, entity.pos.y });
    if (@hasField(@TypeOf(entity.*), "rotation") and @hasField(@TypeOf(entity.*), "rotation_speed"))
        entity.rotation += entity.rotation_speed * dt;
    mutWrapPoint(&entity.pos);
}

pub fn newAsteroid(r: rand.Random) Asteroid {
    const edge = r.uintLessThan(u8, 4);
    const pos = switch (edge) {
        0 => point(@intToFloat(f32, r.int(u16) % screen_width), 0.0),
        1 => point(@intToFloat(f32, r.int(u16) % screen_width), screen_height),
        2 => point(0.0, @intToFloat(f32, r.int(u16) % screen_height)),
        3 => point(screen_width, @intToFloat(f32, r.int(u16) % screen_height)),
        else => unreachable,
    };

    var asteroid = Asteroid{
        .pos = pos,
        .dpos = point(
            r.float(f32) * 100 - 50.0,
            r.float(f32) * 100 - 50.0,
        ),
        .max_radius = 0.0,
        .rotation_speed = r.float(f32) * 10 - 5,
    };
    asteroid.max_radius = genAsteroidGeometry(r, asteroid.geometry[0..]);
    return asteroid;
}

// http://paulbourke.net/geometry/pointlineplane/
pub fn doLinesCollide(p1: Point, p2: Point, p3: Point, p4: Point) bool {
    const uan = (p4.x - p3.x) * (p1.y - p3.y) - (p4.y - p3.y) * (p1.x - p3.x);
    const ubn = (p2.x - p1.x) * (p1.y - p3.y) - (p2.y - p1.y) * (p1.x - p3.x);
    const ud = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x);

    const ua = uan / ud;
    const ub = ubn / ud;
    const result = (ua <= 1 and 0 <= ua and ub <= 1 and 0 <= ub);
    //    std.log.info("line1 x1: {d:.2}, y1: {d:.2}, x2: {d:.2}, y2: {d:.2}\r", .{ p1.x, p1.y, p2.x, p2.y });
    //    std.log.info("line2 x3: {d:.2}, y3: {d:.2}, x4: {d:.2}, y4: {d:.2}\r", .{ p3.x, p3.y, p4.x, p4.y });
    //    std.log.info("collision ua: {d}, ub: {d}, result: {}\r", .{ ua, ub, result });

    return result;
}

var timeOffset: f32 = 0.0;
pub fn timeSinceStart() f32 {
    return @intToFloat(f32, SDL.getPerformanceCounter()) / @intToFloat(f32, SDL.getPerformanceFrequency()) - timeOffset;
}

// const characters = struct {
//     const a = [_]Point{ point(5, 0), point(5, 10), point(0, 5), point(5, 0) };
// };
