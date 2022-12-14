const w4 = @import("wasm4.zig");
const eventscript = @import("eventscript.zig");

var gLastPad: u8 = 0;
var gPad: u8 = 0;
var gPadPressed: u8 = 0;

fn padCheck(btn: u8) bool {
    if (gPadPressed & btn > 0) {
        gPadPressed &= ~btn; // consume
        return true;
    } else {
        return false;
    }
}

fn dialogueTextWrap(txt: []const u8, x: i32, y: i32, w: usize, charsShown: usize) u16 {
    const chW = w / 8;
    var i: usize = 0;
    var row: u16 = 0;
    while (i < txt.len and i <= charsShown) : (row += 1) {
        var wrapAt = @minimum(i + chW, txt.len);
        if (txt.len > i + chW) {
            var j: usize = chW;
            while (j >= chW / 3) : (j -= 1) {
                if (txt[i + j] == ' ') {
                    wrapAt = i + j + 1;
                    break;
                }
            }
        }
        w4.text(txt[i..@maximum(i, @minimum(charsShown, wrapAt))], x, y + row * 8);
        i = wrapAt;
    }
    return row * 8;
}

const mySystem = eventscript.System(struct {
    pub fn wait(s: anytype, duration: usize) void {
        if (s.eventTick + 1 < duration) {
            s.keep();
        }
    }

    pub const requirePressesState = struct {
        presses: u8 = 0,
    };
    pub fn requirePresses(s: anytype, state: *requirePressesState, amount: u8) void {
        if (padCheck(w4.BUTTON_1)) {
            state.presses += 1;
        }
        if (state.presses < amount) {
            w4.text("Presses left: ", 10, 40);
            var buf: [2]u8 = undefined;
            buf[0] = '0' + amount - state.presses;
            buf[1] = 0;
            w4.text(buf[0..2], 130, 40);
            s.keep();
        }
    }

    pub fn showText(s: anytype, text: []const u8, duration: u8) void {
        if (s.eventTick < duration) {
            w4.text(text, 20, 20);
            s.keep();
        }
    }

    pub const dialogueState = struct {
        skipped: bool = false,
    };
    pub fn dialogue(s: anytype, state: *dialogueState, text: []const u8) void {
        const shownChars = s.eventTick / 2;
        const allShown = state.skipped or shownChars >= text.len;
        if (padCheck(w4.BUTTON_1)) {
            if (allShown) {
                return;
            } else {
                state.skipped = true;
            }
        }
        w4.text("Dialogue", 20, 10);
        const h = dialogueTextWrap(text, 5, 22, 150, if (allShown) text.len else shownChars);
        if (allShown and (s.eventTick / 30) % 2 == 0) {
            w4.text("\x80", 20, 24 + h);
        }
        s.keep();
    }

    pub fn call(s: anytype, script: *const mySystem.Script) void {
        _ = s;
        runner.callScript(script);
    }
});

const Script1 = mySystem.Script.create(.{
    .{"dialogue", .{"Hi!"}},
    .{"dialogue", .{"Gonna need ya to press \x80 a few times, ok?"}},
    .{"requirePresses", .{5}},
    .{"showText", .{"Hold on.", 60}},
    .{"showText", .{"Hold on..", 60}},
    .{"showText", .{"Hold on...", 60}},
    .{"dialogue", .{"Good job!"}},
    .{"dialogue", .{"Time for script 2?"}},
    .{"call", .{&Script2}},
    .{"dialogue", .{"Did you enjoy script 2?"}},
});
const Script2 = mySystem.Script.create(.{
    .{"dialogue", .{"Ayo, this is the second script!"}},
    .{"showText", .{"Just a sec...", 60}},
    .{"dialogue", .{"Okay bye"}},
});

var scriptStack: [8]mySystem.ScriptCtx = undefined;
var runner = mySystem.Runner.init(&scriptStack);

export fn start() void {
    runner.callScript(&Script1);
}

export fn update() void {
    w4.DRAW_COLORS.* = 2;

    gPad = w4.GAMEPAD1.*;
    gPadPressed = (gPad ^ gLastPad) & gPad;
    gLastPad = gPad;

    runner.tick();
}
