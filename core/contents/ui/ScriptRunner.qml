import QtQuick
import org.kde.plasma.plasma5support as PlasmaSupport

// Runs one of the package's helper scripts in contents/code/ and hands back its JSON output
PlasmaSupport.DataSource {
    engine: "executable"
    connectedSources: []

    // The script's output, parsed
    signal succeeded(var result)
    // Why there is no usable output: the script's (shortened) stderr, or a generic reason
    signal failed(string error)

    // e.g. run("python3", "fetch_usage.py", ["--cached"])
    function run(interpreter, script, args) {
        var command = interpreter + " " + quote(path(script))
        for (var arg of args || []) {
            command += " " + quote(arg)
        }
        connectSource(command)
    }

    // Absolute path to a script shipped in contents/code/
    function path(script) {
        return decodeURIComponent(Qt.resolvedUrl("../code/" + script).toString().replace(/^file:\/\//, ""))
    }

    // Single-quote for the shell, so paths and arguments pass through untouched
    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    onNewData: function (source, data) {
        disconnectSource(source)

        var stdout = data["stdout"] || ""
        var stderr = data["stderr"] || ""
        var exitCode = data["exit code"] || 0

        if (exitCode === 0 && stdout) {
            var result
            try {
                result = JSON.parse(stdout)
            } catch (e) {
                failed("Parse error")
                return
            }
            succeeded(result)
        } else if (stderr) {
            failed(stderr.length > Constants.errorMessageMaxLength
                ? stderr.substring(0, Constants.errorMessageMaxLength - 3) + "..."
                : stderr)
        } else {
            failed("Command failed")
        }
    }
}
