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
        if (txt.len > chW) {
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

    pub fn dialogue(s: anytype, text: []const u8) void {
        if (!padCheck(w4.BUTTON_1)) {
            w4.text("Dialogue", 20, 10);
            const shownChars = s.eventTick / 2;
            const allShown = shownChars >= text.len;
            const h = dialogueTextWrap(text, 5, 22, 150, if (allShown) text.len else shownChars);
            if (allShown and (s.eventTick / 30) % 2 == 0) {
                w4.text("\x80", 20, 24 + h);
            }
            s.keep();
        }
    }

    pub fn restartScript(s: anytype) void {
        s.eventI = 0;
        s.eventTick = 0;
        s.keep();
    }
});

const MyScript = mySystem.Script(.{
    .{"dialogue", .{"Hi!"}},
    .{"dialogue", .{"Gonna need ya to press \x80 a few times, ok?"}},
    .{"requirePresses", .{5}},
    .{"showText", .{"Hold on.", 60}},
    .{"showText", .{"Hold on..", 60}},
    .{"showText", .{"Hold on...", 60}},
    .{"dialogue", .{"Good job!"}},
    .{"dialogue", .{"Time to restart?"}},
    .{"restartScript"},
});

var script = MyScript{};

export fn update() void {
    w4.DRAW_COLORS.* = 2;

    gPad = w4.GAMEPAD1.*;
    gPadPressed = (gPad ^ gLastPad) & gPad;
    gLastPad = gPad;

    script.tick();
}
