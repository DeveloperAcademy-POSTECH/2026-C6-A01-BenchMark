//
//  compare.swift
//  compare
//
//  Created by 이돈혁 on 11/18/26.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Pixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]
    init(_ path: String) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "image", code: 1) }
        width = image.width; height = image.height
        bytes = Array(repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { memory -> Bool in
            guard let c = CGContext(data: memory.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !success { throw NSError(domain: "bitmap", code: 1) }
    }
}
func write(_ bytes: [UInt8], width: Int, height: Int, path: String) throws {
    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "png", code: 1) }
}
let reference = try Pixels(CommandLine.arguments[1]), actual = try Pixels(CommandLine.arguments[2])
precondition(reference.width == actual.width && reference.height == actual.height)
let w = reference.width, h = reference.height
var overlay = reference.bytes, heat = reference.bytes
var metrics: [[String: Any]] = []
for (name, x0, y0, x1, y1) in [("app",0,62,w,h-34),("header",0,62,w,129),("cards",20,129,w-20,729),("footer",20,742,w-20,840),("button",20,788,w-20,838)] {
    var changed = 0, total = 0, error = 0, maxError = 0
    for y in y0..<min(y1,h) { for x in x0..<min(x1,w) {
        let offset = (y*w+x)*4
        var delta = 0
        for c in 0..<3 { let d = abs(Int(reference.bytes[offset+c])-Int(actual.bytes[offset+c])); error += d; delta = max(delta,d) }
        maxError = max(maxError,delta); if delta > 8 { changed += 1 }; total += 1
    }}
    metrics.append(["region":name,"pixels":total,"differentOver8":changed,"percentOver8":Double(changed)*100/Double(total),"meanChannelError":Double(error)/Double(total*3),"maxChannelError":maxError])
}
for pixel in 0..<(w*h) {
    let o = pixel*4
    let delta = (0..<3).map { abs(Int(reference.bytes[o+$0])-Int(actual.bytes[o+$0])) }.max()!
    for c in 0..<3 { overlay[o+c] = UInt8((Int(reference.bytes[o+c])+Int(actual.bytes[o+c]))/2) }
    heat[o] = UInt8(min(255,delta*4)); heat[o+1] = 0; heat[o+2] = UInt8(min(255,delta*4)); heat[o+3] = 255
}
try write(overlay,width:w,height:h,path:CommandLine.arguments[3]+"-overlay.png")
try write(heat,width:w,height:h,path:CommandLine.arguments[3]+"-diff.png")
let json = try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys])
try json.write(to:URL(fileURLWithPath:CommandLine.arguments[3]+"-metrics.json"))
print(String(decoding:json,as:UTF8.self))
