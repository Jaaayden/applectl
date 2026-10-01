import AppleCore
import Darwin
import Foundation

@main
struct AppleCtlMain {
    @MainActor
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var resultFile: URL?
        if arguments.first == "--result-file", arguments.count >= 2 {
            resultFile = URL(fileURLWithPath: arguments[1])
            arguments.removeFirst(2)
        }
        if resultFile == nil && (arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"]) {
            print(Runner.help); return
        }
        if resultFile == nil && arguments == ["--version"] { print(ToolVersion.current); return }
        let response = await Runner().run(arguments)
        do {
            let data = try response.encoded()
            if let resultFile { try data.write(to: resultFile, options: .atomic) }
            else { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) }
        } catch {
            FileHandle.standardError.write(Data("Cannot write command result: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(response.meta.exitCode)
    }
}
