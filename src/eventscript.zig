const std = @import("std");

// Create an event system from a tagged union
pub fn EventSystem(comptime T: type) type {
    return struct {
        pub const Event = T;
        pub const Script = []const T;

        // Union of all possible Event States
        const StateUnion: type = blk: {
            var unionFields: []const std.builtin.Type.UnionField = &.{};
            inline for (@typeInfo(Event).Union.fields) |field| {
                if (@hasDecl(field.field_type, "State")) {
                    unionFields = unionFields ++ [_]std.builtin.Type.UnionField{.{
                        .name = field.name,
                        .field_type = field.field_type.State,
                        .alignment = 0,
                    }};
                }
            }
            break :blk @Type(std.builtin.Type{ .Union = .{
                .layout = .Auto,
                .tag_type = null,
                .fields = unionFields,
                .decls = &.{},
            } });
        };

        // tick a specific event
        // returns `true` when the event is finished
        fn tickEvent(event: *const Event, eventTick: usize, state: *StateUnion) bool {
            if (eventTick == 0) {
                inline for (@typeInfo(Event).Union.fields) |field| {
                    if (@hasField(StateUnion, field.name)) {
                        if (event.* == @field(Event, field.name)) {
                            state.* = @unionInit(StateUnion, field.name, .{});
                        }
                    }
                }
            }
            inline for (@typeInfo(Event).Union.fields) |field| {
                if (event.* == @field(Event, field.name)) {
                    if (@hasField(StateUnion, field.name)) {
                        return @field(event, field.name).tick(eventTick, &@field(state, field.name));
                    } else {
                        return @field(event, field.name).tick(eventTick);
                    }
                }
            }
            unreachable;
        }

        // script runner
        pub const Runner = struct {
            script: *const Script,
            eventI: usize = 0,
            eventTick: usize = 0,
            eventState: StateUnion = undefined,

            pub fn init(script: *const Script) Runner {
                return Runner{ .script = script };
            }

            // run the script
            // returns `true` when the script is finished
            pub fn tick(self: *Runner) bool {
                if (self.eventI < self.script.len) {
                    if (tickEvent(&self.script.*[self.eventI], self.eventTick, &self.eventState)) {
                        self.eventI += 1;
                        self.eventTick = 0;
                    } else {
                        self.eventTick += 1;
                    }
                }
                return self.eventI >= self.script.len;
            }
        };

        // optional comptime eventscript parser
        pub fn parse(comptime str: []const u8) Script {
            comptime {
                @setEvalBranchQuota(100000);
                var script: Script = &.{};
                var args: []const []const u8 = &.{};
                var curArg: []const u8 = "";
                var inString = false;
                var escape = false;
                var i = 0;
                while (i <= str.len) : (i += 1) {
                    if (escape) {
                        if (str[i] == 'x') {
                            curArg = curArg ++ &[_]u8{(std.fmt.parseUnsigned(u8, str[i + 1 .. i + 3], 16) catch unreachable)};
                            i += 2;
                        }
                        escape = false;
                        continue;
                    }
                    if (inString) {
                        if (str[i] == '\\') {
                            escape = true;
                        } else if (str[i] == '"') {
                            inString = false;
                        } else {
                            curArg = curArg ++ str[i .. i + 1];
                        }
                        continue;
                    }

                    if (i == str.len or str[i] == '\n' or str[i] == ' ') {
                        if (curArg.len > 0) {
                            args = args ++ &[_][]const u8{curArg};
                            curArg = "";
                        }
                    } else if (str[i] == '"') {
                        inString = true;
                    } else {
                        curArg = curArg ++ str[i .. i + 1];
                    }

                    if (i == str.len or str[i] == '\n') {
                        if (args.len > 0) {
                            const eventName = args[0];
                            const argCtx = struct {
                                raw: []const []const u8,

                                pub fn str(self: *const @This(), n: usize) []const u8 {
                                    return self.raw[n];
                                }
                                pub fn int(self: *const @This(), n: usize) isize {
                                    return std.fmt.parseInt(isize, self.raw[n], 10) catch unreachable;
                                }
                                pub fn uint(self: *const @This(), n: usize) usize {
                                    return std.fmt.parseUnsigned(usize, self.raw[n], 10) catch unreachable;
                                }
                            }{ .raw = args[1..] };

                            var found = false;
                            for (@typeInfo(Event).Union.fields) |field| {
                                if (std.mem.eql(u8, eventName, field.name)) {
                                    if (!@hasDecl(field.field_type, "parse")) {
                                        @compileError("Missing parse function for " ++ eventName);
                                    }
                                    script = script ++ &[_]Event{
                                        @unionInit(Event, eventName, field.field_type.parse(argCtx)),
                                    };
                                    found = true;
                                    args = &.{};
                                    break;
                                }
                            }
                            if (!found) {
                                @compileError("Missing event " ++ eventName);
                            }
                        }
                    }
                }
                return script;
            }
        }
    };
}
