import Foundation
// The phone reads Companion.Pressure off the chat list: fields a Mac leaves out get defaults, and
// a pressure field it can't read is dropped rather than failing the whole list.
var failures = 0
func check(_ ok: Bool, _ text: String) { print(ok ? "PASS: \(text)" : "FAIL: \(text)"); if !ok { failures += 1 } }
let list = #"{"revision":3,"groups":[],"pressure":{"level":"ok","updatedAt":"2099-01-01T00:00:00Z","updated":4070908800,"summary":"load 6.0 on 16 cores"}}"#
let decoded = try? Companion.decoder.decode(Companion.ChatList.self, from: Data(list.utf8))
check(decoded?.pressure?.level == "ok" && decoded?.pressure?.reasons == [] && decoded?.pressure?.holding == [] && decoded?.pressure?.isOK == true,
      "a reading without reasons, holding or readings decodes, with defaults")
let broken = #"{"revision":4,"groups":[],"pressure":{"summary":"no level"}}"#
let survived = try? Companion.decoder.decode(Companion.ChatList.self, from: Data(broken.utf8))
check(survived?.revision == 4 && survived?.pressure == nil, "an unreadable pressure field is dropped; the chat list still decodes")
let busy = Companion.Pressure(level: "busy", updatedAt: Date(), updated: 0, summary: "x", memory: "warning", swapUsedGB: 1, swapGrowthGB: 0,
                              load1: 30, load5: 20, load15: 10, cores: 16, thermal: "nominal", holding: ["Builds run one at a time"], waiting: 1)
let again = try? Companion.decoder.decode(Companion.Pressure.self, from: Companion.encoder.encode(busy))
check(again?.level == "busy" && again?.holding == busy.holding && again?.label == "Mac busy" && again?.waiting == 1, "a full reading round-trips")
if failures > 0 { exit(1) }
print("All companion pressure checks passed")
