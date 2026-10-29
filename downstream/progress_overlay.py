"""Add reversible, observation-only progress hooks to the upstream implementation."""

def replace_once(source, before, after):
    if source.count(before) != 1:
        raise RuntimeError('Progress observation anchor changed: ' + before[:100])
    return source.replace(before, after)

# Neither the command, authorization, report contents nor result handling changes.
SOURCE_EDITS = [
    ('func uploadReports(files: [URL], pendingFiles: [URL], in dir: URL, notes: String, batch: String) -> UploadOutcome {',
     'func uploadReports(files: [URL], pendingFiles: [URL], in dir: URL, notes: String, batch: String, progress: ((Int, Int) -> Void)? = nil) -> UploadOutcome {'),
    ('    for entry in selected {',
     '    var processedForProgress = 0\n    progress?(0, selected.count)\n    for entry in selected {'),
    ('        if let error = outcome.1 { out.errors.append("\\(name): \\(error)") }',
     '        if let error = outcome.1 { out.errors.append("\\(name): \\(error)") }\n        processedForProgress += 1\n        progress?(processedForProgress, selected.count)'),
    ('            let cmd = Privileged.bundleScript(script, [], env: sample.isEmpty ? "" : "NULLMOTH_SAMPLE=\\(sample) ")',
     '''            let progressSession = NativeProgressSession { fraction in
                self.send("taskProgress", ["task": "logs", "fraction": fraction])
            }
            defer { progressSession.close() }
            let cmd = Privileged.bundleScript(script, [], env: progressSession.environment + (sample.isEmpty ? "" : "NULLMOTH_SAMPLE=\\(sample) "))'''),
    ('            do { collectionErrors += try SavedReports.importCollection(run.output, to: dir) }',
     '            self.send("taskProgress", ["task": "logs", "fraction": 0.62])\n            do { collectionErrors += try SavedReports.importCollection(run.output, to: dir) }'),
    ('            if let executable = Bundle.main.executableURL {\n                let map = HardwareMapWorker.run(executable: executable)',
     '            self.send("taskProgress", ["task": "logs", "fraction": 0.65])\n            if let executable = Bundle.main.executableURL {\n                let map = HardwareMapWorker.run(executable: executable)'),
    ('            var files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])',
     '            self.send("taskProgress", ["task": "logs", "fraction": 0.70])\n            var files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])'),
    ('            let sent = uploadReports(files: files, pendingFiles: pendingFiles, in: dir, notes: notes, batch: batch)',
     '''            let sent = uploadReports(files: files, pendingFiles: pendingFiles, in: dir, notes: notes, batch: batch) { completed, total in
                self.send("taskProgress", ["task": "logs", "fraction": 0.75 + 0.24 * Double(completed) / Double(max(total, 1)),
                    "completed": completed, "total": total])
            }'''),
    ('        let cmd = Privileged.bundleScript(res.appendingPathComponent("nullmoth-operation-capture.sh").path, args)',
     '''        let progressSession = NativeProgressSession { fraction in
            self.send("taskProgress", ["task": "setup", "fraction": fraction])
        }
        let cmd = Privileged.bundleScript(res.appendingPathComponent("nullmoth-operation-capture.sh").path, args, env: progressSession.environment)'''),
    ('        DispatchQueue.global().async {\n            var captureFailed = false',
     '        DispatchQueue.global().async {\n            defer { progressSession.close() }\n            var captureFailed = false'),
    ('            let zip = work.appendingPathComponent(l.name), out = work.appendingPathComponent("unpacked")',
     '            self.send("taskProgress", ["task": "appUpdate", "fraction": 0.60])\n            let zip = work.appendingPathComponent(l.name), out = work.appendingPathComponent("unpacked")'),
    ('            _ = sh("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])',
     '            self.send("taskProgress", ["task": "appUpdate", "fraction": 0.75])\n            _ = sh("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])'),
    ('            let v = Process(); v.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); v.arguments = ["--verify", "--deep", new.path]',
     '            self.send("taskProgress", ["task": "appUpdate", "fraction": 0.85])\n            let v = Process(); v.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); v.arguments = ["--verify", "--deep", new.path]'),
    ('            let backup = support.appendingPathComponent("app-update/previous.app"), swap = work.appendingPathComponent("swap.sh")',
     '            self.send("taskProgress", ["task": "appUpdate", "fraction": 0.95])\n            let backup = support.appendingPathComponent("app-update/previous.app"), swap = work.appendingPathComponent("swap.sh")'),
]

SETUP_SUPPORT = '''# BEGIN GEEKAUDIO PRESENTATION PROGRESS
downstream_progress() {
  [[ "${GEEK_PROGRESS_CHANNEL:-}" =~ ^io\\.github\\.geekaudio\\.1401-zh\\.progress\\.[A-Fa-f0-9-]{36}$ ]] || return 0
  [[ "$1" =~ ^[0-9]{1,2}$ ]] || return 0
  /usr/bin/notifyutil -q -z 0 -s "$GEEK_PROGRESS_CHANNEL" "$1" -p "$GEEK_PROGRESS_CHANNEL" >/dev/null 2>&1 || :
  return 0
}
downstream_progress_step() {
  case "$*" in
    "Checking the driver package") downstream_progress 5;;
    "package matches its SHA-256") downstream_progress 12;;
    "Finding the OpenCore partition") downstream_progress 20;;
    "Test-building the driver (nothing is changed yet)") downstream_progress 30;;
    "Checking the OpenCore settings"|"Checking the OpenCore removal settings") downstream_progress 50;;
    "backed up the config to "*) downstream_progress 65;;
    "OpenCore config updated") downstream_progress 75;;
    "Installing the driver"|"Installing the USB map"|"Turning verbose startup "*|"Turning built-in screen brightness "*|"Turning HiDPI modes "*) downstream_progress 80;;
    "HiDPI modes "*" - takes effect at the next restart") downstream_progress 95;;
    "Adding WhateverXe to OpenCore"|"Installing WhateverXe Graphics "*|"Removing WhateverXe Graphics "*) downstream_progress 10;;
    "WhateverXe Graphics removed") downstream_progress 65;;
    "WhateverXe added to OpenCore - restart"*|"WhateverXe is already in OpenCore's config "*|"Intel Xe graphics installed "*) downstream_progress 95;;
    "WhateverXe taken out of OpenCore "*|"Intel Xe graphics off - restart to finish") downstream_progress 90;;
    "install record written to "*) downstream_progress 90;;
    "boot picker way back armed "*) downstream_progress 95;;
    "Removing the NullMoth driver") downstream_progress 5;;
    "Taking the AMD/Intel driver from its package") downstream_progress 25;;
    "Downloading the GPU firmware "*) downstream_progress 45;;
    "Installing the AMD/Intel GPU driver"|"Removing the AMD/Intel GPU driver") downstream_progress 75;;
    "Preparing this Mac for the macOS 26 Tahoe update"|"Setting the driver up for macOS "*) downstream_progress 80;;
  esac
  return 0
}
# END GEEKAUDIO PRESENTATION PROGRESS
'''

# A milestone is sent only after the preceding block has returned. No time-based progress.
SETUP_EDITS = [
    ('step() { echo "STEP $*"; }; ok() { echo "OK $*"; }; note() { echo "NOTE $*"; }',
     'step() { echo "STEP $*"; downstream_progress_step "$*"; }; ok() { echo "OK $*"; downstream_progress_step "$*"; }; note() { echo "NOTE $*"; }'),
]
COLLECTION_ANCHORS = [
    ('  # "Record flicker": 20 s of display timing', 3),
    ('  n=0; collection_errors=0', 10),
    ('  for f in "$ST"/*.log "$ST/state";', 20),
    ('  # the kernel\'s own words from the last boots:', 25),
    ('  # 1.9.0 report (10-10, 2K 165 Hz monitor stuck at 1080p 60 Hz):', 30),
    ('  # A boot that hung or went black never writes a panic:', 35),
    ('  # Every GPU and the processor, whatever the vendor and age,', 40),
    ('  # NPUs (Intel NPU, AMD Ryzen AI):', 45),
    ('  # Release builds report failures to syslog rather than nvmtl.log.', 50),
    ('  # The rolling logs above keep only the newest lines,', 55),
    ('  # -h: act on a symbolic link itself,', 60),
]

def instrument_source(source):
    for before, after in SOURCE_EDITS: source = replace_once(source, before, after)
    return source

def strip_source(source):
    for before, after in reversed(SOURCE_EDITS): source = replace_once(source, after, before)
    return source

def instrument_setup(source):
    source = replace_once(source, 'PATH=/usr/bin:/bin:/usr/sbin:/sbin\nB=7C436110', 'PATH=/usr/bin:/bin:/usr/sbin:/sbin\n' + SETUP_SUPPORT + 'B=7C436110')
    for before, after in SETUP_EDITS: source = replace_once(source, before, after)
    for anchor, percent in COLLECTION_ANCHORS:
        source = replace_once(source, anchor, f'  downstream_progress {percent} # GEEKAUDIO PRESENTATION\n' + anchor)
    return source

def strip_setup(source):
    for anchor, percent in reversed(COLLECTION_ANCHORS):
        source = replace_once(source, f'  downstream_progress {percent} # GEEKAUDIO PRESENTATION\n' + anchor, anchor)
    for before, after in reversed(SETUP_EDITS): source = replace_once(source, after, before)
    return replace_once(source, SETUP_SUPPORT, '')
