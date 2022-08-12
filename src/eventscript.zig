const std = @import("std");

fn MakeEventInit(comptime SystemType: type, comptime RunnerType: type, entry: anytype) type {
    const funcName = entry[0];
    return struct {
        pub fn call(runnerInst: *RunnerType) void {
            if (@hasField(SystemType.EventStateUnion, funcName)) {
                runnerInst.eventState = @unionInit(SystemType.EventStateUnion, funcName, .{});
            }
        }
    };
}

fn MakeEventTick(comptime SystemType: type, comptime RunnerType: type, entry: anytype) type {
    const funcName = entry[0];
    const args = if (entry.len > 1) entry[1] else .{};
    return struct {
        pub fn call(runnerInst: *RunnerType) void {
            if (@hasField(SystemType.EventStateUnion, funcName)) {
                var params = .{runnerInst, &@field(runnerInst.eventState, funcName)} ++ args;
                @call(.{}, @field(SystemType.Def, funcName), params);
            } else {
                var params = .{runnerInst} ++ args;
                @call(.{}, @field(SystemType.Def, funcName), params);
            }
        }
    };
}

pub fn System(comptime systemDef: type) type {
    return struct {
        const SystemType = @This();
        const Def = systemDef;

        // Union of all possible event state types with the function as name
        // TODO: handle systems without any event states
        const EventStateUnion: type = blk: {
            var fields: []const std.builtin.Type.UnionField = &.{};
            for (@typeInfo(Def).Struct.decls) |fnDecl| {
                const fnDeclField = @field(Def, fnDecl.name);
                if (@typeInfo(@TypeOf(fnDeclField)) == .Fn) {
                    const stateDeclName = fnDecl.name ++ "State";
                    if (@hasDecl(Def, stateDeclName)) {
                        const stateDecl = @field(Def, stateDeclName);
                        fields = fields ++ [_]std.builtin.Type.UnionField{.{
                            .name = fnDecl.name,
                            .field_type = stateDecl,
                            .alignment = @alignOf(stateDecl),
                        }};
                    }
                }
            }
            break :blk @Type(std.builtin.Type{ .Union = .{
                .layout = .Auto,
                .tag_type = null,
                .fields = fields,
                .decls = &.{},
            } });
        };

        pub const Script = struct {
            const EventFns = struct {
                init: fn (*Runner) void,
                tick: fn (*Runner) void,
            };

            events: []EventFns,

            pub fn create(eventList: anytype) Script {
                var eventFns: [eventList.len]Script.EventFns = undefined;
                for (eventList) |entry, i| {
                    eventFns[i].init = MakeEventInit(SystemType, Runner, entry).call;
                    eventFns[i].tick = MakeEventTick(SystemType, Runner, entry).call;
                }
                return Script{ .events = &eventFns };
            }
        };

        pub const ScriptCtx = struct {
            script: *const Script,
            kept: bool,
            eventI: usize,
            eventTick: usize,
            eventState: EventStateUnion,
        };

        pub const Runner = struct {
            stack: []RunCtx = &.{},
            stackSize: usize = 0,

            pub fn returnScript(self: *Runner) void {

            }
            pub fn execScript(self: *Runner, script: *const Script) void {
                self.stack[self.stackSize - 1].script = script;
                self.stack[self.stackSize - 1].kept = true; // incase this is ran from a script
                self.stack[self.stackSize - 1].eventI = 0;
                self.stack[self.stackSize - 1].eventTick = 0;
            }
            pub fn callScript(self: *Runner, script: *const Script) void {
                if (self.stackSize + 1 >= self.stack.len) {
                    // TODO: stack overflow
                }
                self.stackSize += 1;
                self.execScript(script);
            }
            pub fn keep(self: *Runner) void {
                self.stack[self.stackSize - 1].kept = true;
            }
            pub fn tick(self: *Runner) void {
                if (self.script) |scriptNN| {
                    while (self.eventI < scriptNN.events.len) {
                        self.kept = false;
                        if (self.eventTick == 0) {
                            scriptNN.events[self.eventI].init(self);
                        }
                        scriptNN.events[self.eventI].tick(self);
                        self.eventTick += 1;
                        if (self.kept) {
                            break;
                        }
                        self.eventI += 1;
                        self.eventTick = 0;
                    }
                }
            }
        };
    };
}
