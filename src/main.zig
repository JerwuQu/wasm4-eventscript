const w4 = @import("wasm4.zig");
const eventscript = @import("eventscript.zig");

var gLastPad: u8 = 0;
var gPad: u8 = 0;
var gPadPressed: u8 = 0;

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

const System = eventscript.EventSystem(union(enum(u8)) {
    wait: struct {
        duration: usize,

        pub fn tick(self: *const @This(), eventTick: usize) bool {
            return eventTick + 1 >= self.duration;
        }
        pub fn parse(comptime args: anytype) @This() {
            return .{ .duration = args.uint(0) };
        }
    },
    requirePresses: struct {
        pub const State = struct {
            presses: u8 = 0,
        };

        amount: u8,

        pub fn tick(self: *const @This(), eventTick: usize, state: *State) bool {
            _ = eventTick;
            w4.text("Presses left: ", 10, 40);
            var buf: [2]u8 = undefined;
            buf[0] = '0' + self.amount - state.presses;
            buf[1] = 0;
            w4.text(buf[0..2], 130, 40);
            if (gPadPressed & w4.BUTTON_1 > 0) {
                state.presses += 1;
            }
            return state.presses >= self.amount;
        }
        pub fn parse(comptime args: anytype) @This() {
            return .{ .amount = args.uint(0) };
        }
    },
    showText: struct {
        text: []const u8,
        duration: u8,

        pub fn tick(self: *const @This(), eventTick: usize) bool {
            w4.text(self.text, 20, 20);
            return eventTick + 1 >= self.duration;
        }
        pub fn parse(comptime args: anytype) @This() {
            return .{ .duration = args.uint(0), .text = args.str(1) };
        }
    },
    dialogue: struct {
        text: []const u8,

        pub fn tick(self: *const @This(), eventTick: usize) bool {
            w4.text("Dialogue", 20, 10);
            const shownChars = eventTick / 2;
            const allShown = shownChars >= self.text.len;
            const h = dialogueTextWrap(self.text, 5, 22, 150, if (allShown) self.text.len else shownChars);
            if (allShown and (eventTick / 30) % 2 == 0) {
                w4.text("\x80", 20, 24 + h);
            }
            return gPadPressed & w4.BUTTON_1 > 0;
        }
        pub fn parse(comptime args: anytype) @This() {
            return .{ .text = args.str(0) };
        }
    },
});

// const testScript: System.Script = &[_]System.Event{ .{.tracef = .{.text = "Hello"}} };
const testScript = System.parse(@embedFile("testScript.txt"));
var testScriptRunner = System.Runner.init(&testScript);

export fn update() void {
    w4.DRAW_COLORS.* = 2;

    gPad = w4.GAMEPAD1.*;
    gPadPressed = (gPad ^ gLastPad) & gPad;
    gLastPad = gPad;

    _ = testScriptRunner.tick();
}
