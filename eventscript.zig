const std = @import("std");

fn MakeEventInit(comptime SystemType: type, comptime CtxType: type, entry: anytype) type {
    const funcName = entry[0];
    return struct {
        pub fn call(ctx: *CtxType) void {
            if (@hasField(SystemType.EventStateUnion, funcName)) {
                ctx.eventState = @unionInit(SystemType.EventStateUnion, funcName, .{});
            }
        }
    };
}

fn MakeEventTick(comptime SystemType: type, comptime CtxType: type, entry: anytype) type {
    const funcName = entry[0];
    const args = if (entry.len > 1) entry[1] else .{};
    return struct {
        pub fn call(ctx: *CtxType) void {
            if (@hasField(SystemType.EventStateUnion, funcName)) {
                var params = .{ctx, &@field(ctx.eventState, funcName)} ++ args;
                @call(.{}, @field(SystemType.Def, funcName), params);
            } else {
                var params = .{ctx} ++ args;
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
                init: *const fn (*ScriptCtx) void,
                tick: *const fn (*ScriptCtx) void,
            };

            events: []EventFns,

            pub fn create(eventList: anytype) Script {
                var eventFns: [eventList.len]Script.EventFns = undefined;
                for (eventList) |entry, i| {
                    eventFns[i].init = &MakeEventInit(SystemType, ScriptCtx, entry).call;
                    eventFns[i].tick = &MakeEventTick(SystemType, ScriptCtx, entry).call;
                }
                return Script{ .events = &eventFns };
            }
        };

        pub const ScriptCtx = struct {
            kept: bool,
            ignored: bool,
            script: *const Script,
            userData: ?*anyopaque,
            eventI: usize,
            eventTick: usize,
            eventState: EventStateUnion,

            pub fn keep(self: *ScriptCtx) void {
                self.kept = true;
            }
        };

        pub const Runner = struct {
            stack: []ScriptCtx,
            stackSize: usize = 0,
            userData: ?*anyopaque = null,

            // pub fn asyncScript(self: *Runner, script: *const Script) void {
            // }
            pub fn init(stack: []ScriptCtx) Runner {
                return Runner{ .stack = stack };
            }
            pub fn currentScript(self: *Runner) ?*const Script {
                if (self.stackSize > 0) {
                    return self.stack[self.stackSize - 1].script;
                }
                return null;
            }
            pub fn startScript(self: *Runner, script: *const Script) void {
                self.stackSize = 0;
                self.callScript(script);
            }
            pub fn execScript(self: *Runner, script: *const Script) void {
                self.stack[self.stackSize - 1].userData = self.userData;
                self.stack[self.stackSize - 1].script = script;
                self.restartScript();
            }
            pub fn callScript(self: *Runner, script: *const Script) void {
                if (self.stackSize < self.stack.len) {
                    self.stackSize += 1;
                    self.execScript(script);
                } else {
                    // TODO: stack overflow
                }
            }
            pub fn jumpToIndex(self: *Runner, i: usize) void {
                self.stack[self.stackSize - 1].eventI = i;
                self.stack[self.stackSize - 1].eventTick = 0;
                self.stack[self.stackSize - 1].ignored = true;
            }
            pub fn returnScript(self: *Runner) void {
                if (self.stackSize > 0) {
                    self.stack[self.stackSize - 1].ignored = true; // incase this is ran from a script
                    self.stackSize -= 1;
                }
            }
            pub fn restartScript(self: *Runner) void {
                var scriptCtx = &self.stack[self.stackSize - 1];
                scriptCtx.eventTick = 0;
                scriptCtx.eventI = 0;
                scriptCtx.ignored = true; // incase this is ran from a script
            }
            pub fn tick(self: *Runner) void {
                while (self.stackSize > 0) {
                    var scriptCtx = &self.stack[self.stackSize - 1];
                    if (scriptCtx.eventI >= scriptCtx.script.events.len) {
                        self.stackSize -= 1; // return
                        continue;
                    }
                    scriptCtx.kept = false;
                    scriptCtx.ignored = false;
                    if (scriptCtx.eventTick == 0) {
                        scriptCtx.script.events[scriptCtx.eventI].init(scriptCtx);
                    }
                    scriptCtx.script.events[scriptCtx.eventI].tick(scriptCtx);
                    if (scriptCtx.ignored) {
                        continue;
                    }
                    scriptCtx.eventTick += 1;
                    if (scriptCtx.kept) {
                        return;
                    }
                    scriptCtx.eventI += 1;
                    scriptCtx.eventTick = 0;
                }
            }
        };
    };
}
