// Created by 이돈혁

import CoreText
import Foundation

@main
struct AppClipFontChecks {
    private static let requiredFonts: [(file: String, postScriptName: String)] = [
        ("PearToucan-Regular", "PearToucan-Regular"),
        ("Paperlogy-2ExtraLight", "Paperlogy-2ExtraLight"),
        ("Paperlogy-4Regular", "Paperlogy-4Regular"),
        ("Paperlogy-6SemiBold", "Paperlogy-6SemiBold"),
        ("Paperlogy-7Bold", "Paperlogy-7Bold")
    ]

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fail("Usage: checks <built-OiDonationClip.app>")
        }
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        do {
            let plistData = try Data(contentsOf: appURL.appendingPathComponent("Info.plist"))
            guard let info = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == "com.Spero.OiDonation.Clip",
                  let executable = info["CFBundleExecutable"] as? String,
                  FileManager.default.fileExists(atPath: appURL.appendingPathComponent(executable).path),
                  FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Assets.car").path) else {
                fail("Expected an actual built com.Spero.OiDonation.Clip app bundle")
            }

            var weights: [String: Double] = [:]
            for expected in requiredFonts {
                let fileName = expected.file + ".ttf"
                let candidates = [appURL.appendingPathComponent(fileName),
                                  appURL.appendingPathComponent("Fonts").appendingPathComponent(fileName)]
                guard let fileURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                    fail("Missing bundled font: \(fileName). Source fonts must not be used as a substitute.")
                }
                guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as? [CTFontDescriptor],
                      descriptors.contains(where: {
                          CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == expected.postScriptName
                      }) else {
                    fail("Bundled \(fileName) does not declare \(expected.postScriptName)")
                }

                var registrationError: Unmanaged<CFError>?
                guard CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &registrationError) else {
                    let detail = registrationError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
                    fail("Could not register bundled \(fileName): \(detail)")
                }
                let font = CTFontCreateWithName(expected.postScriptName as CFString, 20, nil)
                let actualName = CTFontCopyPostScriptName(font) as String
                guard actualName == expected.postScriptName else {
                    fail("Font fallback: requested \(expected.postScriptName), got \(actualName)")
                }
                guard let loadedURL = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
                      loadedURL.standardizedFileURL.resolvingSymlinksInPath() == fileURL.standardizedFileURL.resolvingSymlinksInPath() else {
                    fail("\(expected.postScriptName) resolved outside the supplied app bundle")
                }
                let traits = CTFontCopyTraits(font) as NSDictionary
                guard let weight = traits[kCTFontWeightTrait] as? NSNumber else {
                    fail("Missing font weight: \(expected.postScriptName)")
                }
                weights[expected.postScriptName] = weight.doubleValue
                print("PASS: bundled \(fileName) → \(actualName), weight \(weight)")
            }
            guard let extraLight = weights["Paperlogy-2ExtraLight"],
                  let regular = weights["Paperlogy-4Regular"],
                  let semibold = weights["Paperlogy-6SemiBold"],
                  let bold = weights["Paperlogy-7Bold"], extraLight < regular, regular < semibold, semibold < bold else {
                fail("Paperlogy ExtraLight, Regular, SemiBold, and Bold must retain distinct increasing weights")
            }
            print("PASS: all \(requiredFonts.count) required fonts load from the actual App Clip bundle without fallback")
        } catch {
            fail("Could not inspect built App Clip: \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
