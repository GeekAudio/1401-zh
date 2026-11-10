import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAILED: " + message) }
    print("ok   " + message)
}

let catalog = DriverSettings.load(try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let surround = catalog.find("surround")!
let card = catalog.find("card")!

check(NativeSettingsControlValues.framebufferMask("default") == 0, "default surround selects no framebuffer")
check(NativeSettingsControlValues.framebufferSelected(0, in: "129") &&
      NativeSettingsControlValues.framebufferSelected(7, in: "129") &&
      !NativeSettingsControlValues.framebufferSelected(1, in: "129"), "surround selection decodes the eight framebuffer bits")
check(NativeSettingsControlValues.settingFramebuffer(7, selected: true, in: "1") == "129", "surround checkbox sets its bit")
check(NativeSettingsControlValues.settingFramebuffer(0, selected: false, in: "1") == "default", "clearing the last surround checkbox restores default")
check(NativeSettingsControlValues.settingFramebuffer(8, selected: true, in: "3") == "3", "out-of-range framebuffer indices leave the value unchanged")
check((try? DriverSettings.normalize(catalog, surround, "129")) == "129", "surround mask remains accepted by the shared settings validator")
check((try? DriverSettings.normalize(catalog, surround, "default")) == nil, "empty surround mask clears the setting")

let parsed = NativeSettingsControlValues.cardSelection("Game=1,*=0")
check(parsed.defaultCard == 0 && parsed.applications == [NativeCardApplication(name: "Game", card: 1)],
      "card parser reads global and per-application selection")
check(NativeSettingsControlValues.cardValue(defaultCard: parsed.defaultCard, applications: parsed.applications) == "Game=1,*=0",
      "card serializer preserves the upstream mapping format")
check(NativeSettingsControlValues.cardValue(defaultCard: 3, applications: []) == "3", "a single global card stays a plain number")
check(NativeSettingsControlValues.cardValue(defaultCard: nil, applications: []) == "default", "an empty card selection restores default")
check((try? DriverSettings.normalize(catalog, card, "Game=1,*=0")) == "Game=1,*=0" &&
      (try? DriverSettings.normalize(catalog, card, "3")) == "3", "structured card values remain accepted by the shared settings validator")
check((try? DriverSettings.normalize(catalog, card, "Game=8")) == nil &&
      (try? DriverSettings.normalize(catalog, card, "=2")) == nil, "card selections outside 0–7 or without an app name are refused")
print("Native settings control conversion checks passed")
