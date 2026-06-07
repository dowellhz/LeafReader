#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/leafreader-fluidaudio-runtime}"
REPO_URL="${REPO_URL:-https://github.com/FluidInference/FluidAudio.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/leafreader/kokoro-coreml}"
OUTPUT_NAME="${OUTPUT_NAME:-fluidaudiocli}"

rm -rf "$WORK_DIR"
git clone "$REPO_URL" "$WORK_DIR"
cd "$WORK_DIR"

cat > Sources/FluidAudioCLI/FluidAudioCLI.swift <<'SWIFT'
#if os(macOS)
import FluidAudio
import Foundation

@main
struct FluidAudioCLI {
    static let logger = AppLogger(category: "Main")

    static func main() async {
        var arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "tts" {
            arguments = arguments.dropFirst()
        }
        if arguments.first == "--help" || arguments.first == "-h" || arguments.isEmpty {
            printUsage()
            exit(arguments.isEmpty ? 1 : 0)
        }
        await TTS.run(arguments: Array(arguments))
    }

    static func printUsage() {
        logger.info(
            """
            Usage: fluidaudio [tts] "text" --backend kokoro-ane|supertonic3 --output output.wav

            Kokoro:
              fluidaudio tts "Hello" --backend kokoro-ane --variant en --voice af_heart --output out.wav

            Supertonic:
              fluidaudio tts "Hello" --backend supertonic3 --voice M1 --lang en --total-steps 8 --speed 1.0 --output out.wav
            """
        )
    }
}
#else
#error("FluidAudioCLI is only supported on macOS")
#endif
SWIFT

cat > Sources/FluidAudioCLI/Commands/TTSCommand.swift <<'SWIFT'
import CoreML
import FluidAudio
import Foundation

public struct TTS {
    private static let logger = AppLogger(category: "TTSCommand")

    public static func run(arguments: [String]) async {
        var backend: TtsBackend = .kokoroAne
        var output = "output.wav"
        var voice = TtsConstants.recommendedVoice
        var text: String?
        var variant: KokoroAneVariant = .english
        var language = "en"
        var totalSteps = Supertonic3Constants.defaultTotalSteps
        var speed = Supertonic3Constants.defaultSpeed
        var cpuOnly = false

        var i = 0
        while i < arguments.count {
            let argument = arguments[i]
            switch argument {
            case "--help", "-h":
                printUsage()
                return
            case "--backend":
                if i + 1 < arguments.count {
                    switch arguments[i + 1].lowercased() {
                    case "kokoro-ane", "kokoroane", "kokoro":
                        backend = .kokoroAne
                    case "supertonic3", "supertonic-3", "sup3":
                        backend = .supertonic3
                    default:
                        logger.warning("Unknown backend '\(arguments[i + 1])'; using kokoro-ane")
                    }
                    i += 1
                }
            case "--output", "-o":
                if i + 1 < arguments.count {
                    output = arguments[i + 1]
                    i += 1
                }
            case "--voice", "-v":
                if i + 1 < arguments.count {
                    voice = arguments[i + 1]
                    i += 1
                }
            case "--variant", "--model-variant":
                if i + 1 < arguments.count {
                    switch arguments[i + 1].lowercased() {
                    case "en", "english":
                        variant = .english
                    case "zh", "mandarin", "zh-cn", "zh_cn":
                        variant = .mandarin
                    default:
                        logger.warning("Unknown Kokoro variant '\(arguments[i + 1])'; using en")
                    }
                    i += 1
                }
            case "--lang":
                if i + 1 < arguments.count {
                    language = arguments[i + 1].lowercased()
                    i += 1
                }
            case "--total-steps":
                if i + 1 < arguments.count, let value = Int(arguments[i + 1]) {
                    totalSteps = value
                    i += 1
                }
            case "--speed":
                if i + 1 < arguments.count, let value = Float(arguments[i + 1]) {
                    speed = value
                    i += 1
                }
            case "--cpu-only":
                cpuOnly = true
            case "--text":
                if i + 1 < arguments.count {
                    text = arguments[i + 1]
                    i += 1
                }
            default:
                if text == nil {
                    text = argument
                } else {
                    logger.warning("Ignoring unexpected argument '\(argument)'")
                }
            }
            i += 1
        }

        guard let text else {
            printUsage()
            exit(1)
        }

        switch backend {
        case .kokoroAne:
            await runKokoroAne(text: text, output: output, voice: voice, variant: variant)
        case .supertonic3:
            await runSupertonic3(
                text: text,
                output: output,
                voice: voice,
                language: language,
                totalSteps: totalSteps,
                speed: speed,
                cpuOnly: cpuOnly
            )
        default:
            logger.error("Unsupported backend for LeafReader runtime")
            exit(1)
        }
    }

    private static func runKokoroAne(text: String, output: String, voice: String, variant: KokoroAneVariant) async {
        do {
            let resolvedVoice = voice == TtsConstants.recommendedVoice ? variant.defaultVoice : voice
            let manager = KokoroAneManager(variant: variant, defaultVoice: resolvedVoice)
            try await manager.initialize()
            let detailed = try await manager.synthesizeDetailed(text: text, voice: resolvedVoice, speed: 1.0)
            let wav = try AudioWAV.data(from: detailed.samples, sampleRate: Double(detailed.sampleRate))
            try write(wav, to: output)
        } catch {
            logger.error("KokoroAne failed: \(error)")
            exit(1)
        }
    }

    private static func runSupertonic3(
        text: String,
        output: String,
        voice: String,
        language: String,
        totalSteps: Int,
        speed: Float,
        cpuOnly: Bool
    ) async {
        do {
            let computeUnits: MLComputeUnits = cpuOnly ? .cpuOnly : .cpuAndNeuralEngine
            let manager = Supertonic3Manager(computeUnits: computeUnits, vectorEstimator: .fp16Dynamic)
            try await manager.initialize()
            let selectedVoice = Supertonic3Voice(name: voice) ?? .default
            let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(selectedVoice)
            let result = try await manager.synthesize(
                text: text,
                language: language,
                style: style,
                totalSteps: totalSteps,
                speed: speed
            )
            let wav = try AudioWAV.data(from: result.samples, sampleRate: Double(Supertonic3Constants.sampleRate))
            try write(wav, to: output)
        } catch {
            logger.error("Supertonic-3 failed: \(error)")
            exit(1)
        }
    }

    private static func write(_ data: Data, to path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(expanded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func printUsage() {
        logger.info("Usage: fluidaudio [tts] \"text\" --backend kokoro-ane|supertonic3 --output output.wav")
    }
}
SWIFT

python3 - <<'PY'
from pathlib import Path
path = Path("Package.swift")
text = path.read_text()
old = '''        .executableTarget(
            name: "FluidAudioCLI",
            dependencies: ["FluidAudio"],
            path: "Sources/FluidAudioCLI",
            exclude: ["README.md"],
            resources: [
                .process("Utils/english.json")
            ]
        ),'''
new = '''        .executableTarget(
            name: "FluidAudioCLI",
            dependencies: ["FluidAudio"],
            path: "Sources/FluidAudioCLI",
            exclude: [
                "README.md",
                "Commands/ASR",
                "Commands/DiarizationBenchmark.swift",
                "Commands/DiarizationBenchmarkUtils.swift",
                "Commands/DownloadCommand.swift",
                "Commands/G2PBenchmark.swift",
                "Commands/LSEENDBenchmark.swift",
                "Commands/LSEENDCommand.swift",
                "Commands/MagpieCommand.swift",
                "Commands/MinimaxCorpusCommand.swift",
                "Commands/ProcessCommand.swift",
                "Commands/SortformerBenchmark.swift",
                "Commands/SortformerCommand.swift",
                "Commands/TTSAsrVerifyCommand.swift",
                "Commands/TtsBenchmarkCommand.swift",
                "Commands/VadAnalyzeCommand.swift",
                "Commands/VadBenchmark.swift",
                "DatasetParsers",
                "Models",
                "Utils",
            ]
        ),'''
if old not in text:
    raise SystemExit("Package.swift target block did not match expected upstream layout")
path.write_text(text.replace(old, new))
PY

swift build -c release --product fluidaudiocli

mkdir -p "$INSTALL_DIR"
cp ".build/release/$OUTPUT_NAME" "$INSTALL_DIR/$OUTPUT_NAME"
strip -u -r "$INSTALL_DIR/$OUTPUT_NAME" || true
codesign --force --sign - "$INSTALL_DIR/$OUTPUT_NAME"
ls -lh "$INSTALL_DIR/$OUTPUT_NAME"
