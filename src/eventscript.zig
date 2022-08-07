const std = @import("std");

fn MakeEventCall(comptime T: type, entry: anytype) type {
    const func = entry[0];
    const args = if (entry.len > 1) entry[1] else .{};
    return struct {
        pub fn call(scriptInst: *T) void {
            var params = .{scriptInst} ++ args;
            @call(.{}, func, params);
        }
    };
}

pub fn Script(eventList: anytype) type {
    return struct {
        const ScriptType = @This();

        const events = eventsBlk: {
            var eventFns: [eventList.len]fn (*ScriptType) void = undefined;
            for (eventList) |eventListEntry, i| {
                eventFns[i] = MakeEventCall(ScriptType, eventListEntry).call;
            }
            break :eventsBlk eventFns;
        };

        kept: bool = false,
        eventI: usize = 0,
        eventTick: usize = 0,

        pub fn keep(self: *ScriptType) void {
            self.kept = true;
        }
        pub fn tick(self: *ScriptType) void {
            while (self.eventI < events.len) {
                self.kept = false;
                events[self.eventI](self);
                self.eventTick += 1;
                if (self.kept) {
                    break;
                }
                self.eventI += 1;
                self.eventTick = 0;
            }
        }
    };
}
